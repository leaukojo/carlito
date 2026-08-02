class_name VehicleSelect
extends Control
## The vehicle selector — three axes on one screen, where there used to be a stack of text
## buttons naming FAMILIES and two invisible key cycles (V bodies, E attachments) that nothing
## told you about.
##
##   left    every family in VehicleCatalog, with what it speaks on the bus
##   middle  the family's variants as pictures, and — when the previewed machine tows — a second
##           row of what it can pull
##   right   ONE SubViewport with the selected machine on a turntable, and its spec
##
## ONE live preview, never one per card: ~30 variants would be ~30 SubViewports. The stills on the
## cards are pre-baked by tools/gen_vehicle_thumbs.tscn through the same VehicleShot framing the
## turntable uses, so the card and the model beside it are the same picture.
##
## NOTHING IS HIDDEN. A family this level will not spawn is still browsable, still previews, and
## carries the reason on its cards — "no closed rail loop here" teaches something about the level
## and about the machine; a missing card teaches nothing. Only DRIVE is refused.
##
## Built in code like every other shell screen; sizing and colour from the inherited theme
## (UiTheme), no emoji. It never touches the scene tree it is picking for: it emits, and the shell
## respawns (standing rule 6).

## Emitted on DRIVE. `attachment_chosen` follows immediately after, and only when the picked
## machine tows — so a sentinel is never needed for "no attachment" (DETACHED and BOBTAIL are
## both the empty string, and both are real choices).
signal vehicle_chosen(variant: String)
signal attachment_chosen(id: String)
signal closed

## Logical px (all scaled through UiTheme.px).
const FAMILY_W := 190.0
const CARD_W := 176.0
const PREVIEW_W := 380.0
## The footer buttons (BACK / DRIVE). Deliberately larger than a default button: DRIVE is the
## screen's whole purpose and was easy to walk past, and BACK matches it so the row stays even.
const FOOTER_W := 240.0
## The live DRIVE button's attention pulse: how far its brightness swings, and how fast.
const PULSE_DEPTH := 0.16
const PULSE_HZ := 0.9
## A card's frame, and the amount its picture is inset by so the frame is visible at all.
const BORDER_W := 3.0
## Below this the preview column is dropped: three columns do not fit a phone, and the cards are
## the part you cannot pick without. It is the width the three columns actually need — the family
## list, the preview, and TWO cards across (a one-card column is a list wearing pictures) plus the
## screen margins — not a round number.
const NARROW_W := FAMILY_W + PREVIEW_W + CARD_W * 2.0 + UiTheme.MARGIN * 4.0
const TURNTABLE_DEG_PER_S := 24.0
## Frames after a preview swap during which the subject's bounds are re-measured every frame
## rather than cached. A body is not its final size on the tick it is added: RayWheel poses the
## wheel visuals on the first physics tick, and the semi couples its trailer on a countdown
## (SemiTractor.SPAWN_COUPLE_TICKS). After that the body is frozen, so its bounds cannot change
## and walking every VisualInstance3D per frame would be pure waste.
const SETTLE_FRAMES := 20

var _allowed: PackedStringArray = []   ## the level's LevelInfo.allowed_vehicles, unfiltered
var _level_name := "this level"
var _has_rail := false
var _variant := ""
var _attachment := ""                  ## seeded from the driven machine, then owned by the preview
## The variant `_attachment` was seeded FROM. Needed because "" is not "nothing was handed over" —
## it is BOBTAIL and DETACHED, both real choices. Without it, opening the selector while driving a
## car (which answers "") and browsing to the semi would show it bobtail rather than with the box
## it actually spawns pulling.
var _attachment_of := ""

var _pulse_t := 0.0  ## phase of the DRIVE button's attention pulse, in turns

var _family := ""
var _families: VBoxContainer
var _cards: VBoxContainer
var _preview_panel: PanelContainer
var _viewport: SubViewport
var _camera: Camera3D
var _preview: Node3D = null
var _spec_label: Label
var _drive_btn: Button
var _back_btn: Button
var _reason_label: Label
var _yaw := VehicleShot.VIEW_YAW_DEG
var _bounds := AABB()
var _settle := 0


## Called by the shell BEFORE add_child (the setup pattern the pause menu follows too).
## `allowed` is the level's raw allow-list and `rail` its runtime closed-loop answer — both, rather
## than a pre-filtered roster, because the screen shows what it cannot spawn and has to say WHY.
func setup(allowed: PackedStringArray, level_name: String, rail: bool,
		variant: String, attachment: String) -> void:
	_allowed = allowed
	_level_name = level_name
	_has_rail = rail
	_variant = variant if VehicleCatalog.VARIANTS.has(variant) else ""
	_attachment = attachment
	_attachment_of = _variant


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	add_child(col)

	var title := Label.new()
	title.text = "VEHICLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"Display"
	col.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_families())
	body.add_child(_build_cards())
	_preview_panel = _build_preview()
	body.add_child(_preview_panel)

	col.add_child(_build_footer())

	if _variant.is_empty():
		_variant = _first_available_variant()
	_family = VehicleCatalog.family_of(_variant)
	_refresh_families()
	_refresh_cards()
	_show_preview(_variant)
	resized.connect(_reflow)
	_reflow()
	set_process(true)
	# Keyboard/gamepad start point, like every other shell screen — but DRIVE is disabled when the
	# level refuses the previewed family, and a disabled button is not a place to leave the focus
	# ring. Fall back to BACK, which is always live.
	var entry := _drive_btn if not _drive_btn.disabled else _back_btn
	entry.grab_focus()


## Wipe a container NOW rather than at the end of the frame. `queue_free` alone leaves the old
## children in `get_children()` until the flush, so the very next rebuild sees them, queue_frees
## them a second time and counts them as its own.
static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- construction -------------------------------------------------------------

func _build_families() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # arrowing past the fold has to bring the family into view
	scroll.custom_minimum_size.x = UiTheme.px(self, FAMILY_W)
	_families = VBoxContainer.new()
	_families.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_families)
	return scroll


func _build_cards() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # the attachment row sits below the fold on a short window
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)
	return scroll


## The one live preview. The SubViewport is built ONCE and outlives every selection — only the
## body inside it is swapped — so clicking through thirty variants leaks neither a viewport nor a
## world.
func _build_preview() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = UiTheme.px(self, PREVIEW_W)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(UiTheme.px(self, PREVIEW_W - UiTheme.PAD_X * 2.0),
			UiTheme.px(self, (PREVIEW_W - UiTheme.PAD_X * 2.0) * VehicleShot.CARD_ASPECT))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(frame)

	_viewport = SubViewport.new()
	frame.add_child(_viewport)
	_camera = VehicleShot.build_stage(_viewport)

	_spec_label = Label.new()
	_spec_label.theme_type_variation = &"Dim"
	_spec_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_spec_label)
	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var footer_size := Vector2(UiTheme.px(self, FOOTER_W),
			UiTheme.px(self, UiTheme.TOUCH_MIN * 1.5))

	_back_btn = Button.new()
	_back_btn.text = "BACK"
	_back_btn.custom_minimum_size = footer_size
	_back_btn.pressed.connect(func() -> void: closed.emit())
	row.add_child(_back_btn)

	# The screen's purpose, and it was being missed: accent-filled (theme `Primary`), the same size
	# as BACK for symmetry, and breathing while it is live — see _process.
	_drive_btn = Button.new()
	_drive_btn.text = "DRIVE"
	_drive_btn.theme_type_variation = &"Primary"
	_drive_btn.custom_minimum_size = footer_size
	_drive_btn.pressed.connect(_on_drive)
	row.add_child(_drive_btn)

	_reason_label = Label.new()
	_reason_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reason_label.theme_type_variation = &"MutedSmall"
	row.add_child(_reason_label)
	return row


# --- family column ------------------------------------------------------------

## Every family the catalog knows, in LIST order. A family this level refuses is listed too and
## still opens — see the class comment.
##
## The order is the selector's own, not the catalog's: the three road machines the sandbox is
## really about come first, then the rest. A family missing from FAMILY_ORDER still lists (in
## catalog order, after the named ones), so adding one to the catalog cannot make it disappear
## from the menu.
const FAMILY_ORDER := ["car", "truck", "tractor", "boat", "drone", "plane", "train", "bike"]

## Families whose button carries "(beta)": they drive, but they are rougher than the road vehicles
## and the label is what stops that reading as breakage.
const BETA_FAMILIES := ["bike", "train", "boat", "plane", "drone"]

func _all_families() -> PackedStringArray:
	var found := PackedStringArray()
	for variant: String in VehicleCatalog.VARIANTS:
		var fam := VehicleCatalog.family_of(variant)
		if not found.has(fam):
			found.append(fam)
	var out := PackedStringArray()
	for fam in FAMILY_ORDER:
		if found.has(fam):
			out.append(fam)
	for fam in found:
		if not out.has(fam):
			out.append(fam)
	return out


## Why this level will not spawn `family`, or "" when it will. Two reasons and both are DERIVED:
## the level's own allow-list, and the runtime closed-rail answer (Level.has_closed_rail, the one
## walk the spawn gate uses). No per-family prose — a hand-written "the boat needs water" is a
## third place the truth about a level lives, and it would drift the way the key-hint label did.
func _refusal(family: String) -> String:
	if not _allowed.is_empty() and not _allowed.has(family):
		return "no spawn for it in %s" % _level_name
	if family == "train" and not _has_rail:
		return "no closed rail loop here"
	return ""


func _refresh_families() -> void:
	_clear(_families)
	for family in _all_families():
		var b := Button.new()
		b.text = family.to_upper() + (" (beta)" if BETA_FAMILIES.has(family) else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = UiTheme.px(self, UiTheme.TOUCH_MIN)
		b.toggle_mode = true
		# A radio group, not a push button: the theme's plain `pressed` box reads as RECESSED,
		# which is the opposite of chosen. `Choice` marks it with the same accent border the
		# picture cards use, so one selection language runs across the whole screen.
		b.theme_type_variation = &"Choice"
		b.button_pressed = family == _family
		b.tooltip_text = VehicleSelect.protocols_for(family)
		b.pressed.connect(_on_family_pressed.bind(family))
		_families.add_child(b)


func _on_family_pressed(family: String) -> void:
	if family == _family:
		_refresh_families()  # a toggle button un-toggles itself; the column is a radio group
		return
	_family = family
	_refresh_families()
	_refresh_cards()
	_show_preview(VehicleCatalog.first_in_family(family))


# --- card grid ----------------------------------------------------------------

func _refresh_cards() -> void:
	_clear(_cards)
	var reason := _refusal(_family)
	_cards.add_child(_heading("BODY", reason))
	_cards.add_child(_card_grid(VehicleCatalog.variants_in_family(_family), _variant,
			reason, _on_variant_pressed))
	# The attachment row is rebuilt by _show_preview: what can be towed is the PREVIEWED machine's
	# own answer, not something this screen knows about a family.
	_refresh_attachments()


func _heading(text: String, reason := "") -> Label:
	var l := Label.new()
	l.text = text if reason.is_empty() else "%s  -  %s" % [text, reason.to_upper()]
	l.theme_type_variation = &"Title" if reason.is_empty() else &"MutedSmall"
	return l


## One row of picture cards. `ids` are thumbnail ids (a variant id, or an attachment scene path
## resolved through VehicleShot.id_for_scene); the empty id is a real catalog entry with nothing
## to photograph and gets a plate reading NONE.
func _card_grid(ids: PackedStringArray, selected: String, reason: String,
		on_press: Callable) -> Control:
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ids:
		grid.add_child(_make_card(id, id == selected, reason, on_press))
	return grid


func _make_card(id: String, selected: bool, reason: String, on_press: Callable) -> Button:
	var card_w := UiTheme.px(self, CARD_W)
	var card := Button.new()
	card.custom_minimum_size = Vector2(card_w, roundf(card_w * VehicleShot.CARD_ASPECT))
	card.clip_contents = true
	card.disabled = not reason.is_empty()
	card.tooltip_text = reason
	# The card IS the picture: the theme's Button padding would inset it.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, _card_box(selected or state in ["hover", "focus"]))
	card.pressed.connect(on_press.bind(id))

	# THE PICTURE IS INSET BY THE BORDER, and that is not a taste call: a StyleBox is the button's
	# BACKGROUND, so a full-rect child paints straight over it and the selection border does not
	# exist at all on any card carrying a thumbnail. Measured — the only card showing its border
	# was the one with no picture. It is also why the border WIDTH is fixed rather than growing
	# when lit: a width that changed would have to move the inset with it.
	var inset := UiTheme.px(self, BORDER_W)

	var thumb_id := VehicleShot.id_for_scene(id) if id.contains("/") else id
	var thumb_path := VehicleShot.thumb_path(thumb_id)
	if not thumb_id.is_empty() and ResourceLoader.exists(thumb_path):
		var thumb := TextureRect.new()
		thumb.texture = ResourceLoader.load(thumb_path)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.modulate = Color(1, 1, 1, 0.45) if card.disabled else Color.WHITE
		thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = inset
		thumb.offset_top = inset
		thumb.offset_right = -inset
		thumb.offset_bottom = -inset
		card.add_child(thumb)

	var strip := ColorRect.new()
	strip.color = UiTheme.SCRIM
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = inset
	strip.offset_right = -inset
	strip.offset_top = -UiTheme.px(self, 28.0)
	strip.offset_bottom = -inset
	card.add_child(strip)

	var label := Label.new()
	label.text = _pretty(thumb_id) if not thumb_id.is_empty() else "NONE"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"MutedSmall" if card.disabled else &"Dim"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = UiTheme.px(self, 8.0)
	strip.add_child(label)
	return card


static func _pretty(id: String) -> String:
	return id.replace("-", " ").replace("_", " ").to_upper()


## A card's frame: the picture is the fill, so this is only the border that marks selection and
## focus. The theme's Button box cannot do it — that box exists to pad text.
func _card_box(lit: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UiTheme.SURFACE_LO
	s.set_corner_radius_all(int(UiTheme.px(self, UiTheme.RADIUS)))
	s.border_color = UiTheme.ACCENT if lit else UiTheme.BORDER
	s.set_border_width_all(int(UiTheme.px(self, BORDER_W)))
	return s


func _on_variant_pressed(variant: String) -> void:
	if variant == _variant:
		return
	_variant = variant
	_refresh_cards()
	_show_preview(variant)


func _on_attachment_pressed(id: String) -> void:
	_attachment = id
	_attachment_of = _variant
	if _preview != null and _preview.has_method("set_attachment"):
		_preview.set_attachment(id)
		VehicleShot.pin_display(_preview)  # a body swapped in under the showroom is pinned with it
	_refresh_attachments()


## The second row, and it exists only when the PREVIEWED machine says it tows — the same
## duck-type the shell uses for cycle_implement, so this screen never learns what a trailer or an
## implement is. Rebuilt on every preview swap, because a semi tows and a garbage truck does not.
func _refresh_attachments() -> void:
	for child in _cards.get_children():
		if child.has_meta("attachments"):
			_cards.remove_child(child)
			child.queue_free()
	if _preview == null or not _preview.has_method("attachment_ids"):
		return
	var ids: PackedStringArray = _preview.attachment_ids()
	if ids.is_empty():
		return
	var head := _heading("ON THE BACK")
	head.set_meta("attachments", true)
	_cards.add_child(head)
	var grid := _card_grid(ids, _attachment, "", _on_attachment_pressed)
	grid.set_meta("attachments", true)
	_cards.add_child(grid)


# --- preview ------------------------------------------------------------------

## Swap the body inside the one long-lived viewport. Frozen and hovering (VehicleShot), so it
## cannot fall out of frame, and `display_only` keeps it out of InputRouter's single vehicle slot
## — without that a preview would take the driven body's place in local arbitration and null it
## again on its way out.
func _show_preview(variant: String) -> void:
	_variant = variant
	_free_preview()
	_spec_label.text = ""
	_update_drive_button()
	var scene_path := VehicleCatalog.scene_of(variant)
	if scene_path.is_empty():
		return
	_preview = VehicleShot.spawn_display(scene_path)
	if _preview == null:
		push_error("vehicle selector: cannot instantiate " + scene_path)
		return
	_viewport.add_child(_preview)
	VehicleShot.pin_display(_preview)
	# Re-seat the attachment on the machine it came FROM (a fresh tractor carries the catalog's
	# first implement, not the one you left on the linkage). Any other machine keeps its own
	# default and tells us what that is — see _attachment_of for why "" cannot be the test.
	if _preview.has_method("set_attachment"):
		var ids: PackedStringArray = _preview.attachment_ids()
		if variant == _attachment_of and ids.has(_attachment):
			_preview.set_attachment(_attachment)
			VehicleShot.pin_display(_preview)
		else:
			_attachment = String(_preview.current_attachment())
			_attachment_of = variant
	_refresh_attachments()
	_settle = SETTLE_FRAMES
	_bounds = AABB()
	_spec_label.text = _spec_text(variant)


func _free_preview() -> void:
	if _preview == null:
		return
	# remove_child before queue_free (the semi's own _drop_trailer discipline): queue_free flushes
	# at the end of the frame and physics steps run before that, so a deferred free alone leaves
	# the old machine in the world while the next one is laid on top of it. A body that owns
	# another body drops it in its own _exit_tree.
	if _preview.get_parent() != null:
		_preview.get_parent().remove_child(_preview)
	_preview.queue_free()
	_preview = null
	_bounds = AABB()
	_settle = 0


## Turntable: the CAMERA orbits, never the body. Rotating a frozen RigidBody3D (or its parent)
## fights the physics server for a transform it is already writing every tick. This screen runs
## while the tree is paused, so _process is the clock here.
func _process(delta: float) -> void:
	_pulse_drive(delta)
	if _preview == null or not is_instance_valid(_preview) or not _preview_panel.visible:
		return
	_yaw = fmod(_yaw + TURNTABLE_DEG_PER_S * delta, 360.0)
	if _settle > 0:
		_settle -= 1
		_bounds = VehicleShot.subject_bounds(_preview)
		if _settle == 0:
			# The rig is whole now (wheels posed, any trailer coupled), so the measured size on
			# the spec line is the final one rather than the first frame's.
			_spec_label.text = _spec_text(_variant)
	if _bounds.size == Vector3.ZERO:
		return
	VehicleShot.frame(_camera, _bounds, _yaw)


## Breathe the DRIVE button while it is live, so the way out of the menu is the thing that moves.
## Modulate rather than a Tween: it has to STOP dead when the level refuses the previewed family,
## and a disabled button that is still pulsing invites the press the screen is about to reject.
func _pulse_drive(delta: float) -> void:
	if _drive_btn.disabled:
		_drive_btn.modulate = Color.WHITE
		_pulse_t = 0.0
		return
	_pulse_t = fmod(_pulse_t + delta * PULSE_HZ, 1.0)
	var k := 1.0 + PULSE_DEPTH * sin(_pulse_t * TAU)
	_drive_btn.modulate = Color(k, k, k)


# --- spec line ----------------------------------------------------------------

## What the machine IS, and this is a CAN sandbox, so what it speaks is part of that. The protocol
## line is read out of the contract rather than typed here (rule 4): a family's flavors ARE its
## borrowed profiles, and a family that borrows none says so instead of being given a label.
static func protocols_for(family: String) -> String:
	if Contract.data == null or not Contract.data.is_valid():
		return "-"
	var seen := PackedStringArray()
	for dir in Contract.DIRS:
		for sig in Contract.data.signals_for_vehicle(family, dir):
			if not sig.flavor.is_empty() and not seen.has(sig.flavor):
				seen.append(sig.flavor)
	if seen.is_empty():
		return "generic - borrows no profile"
	seen.sort()
	var upper := PackedStringArray()
	for flavor in seen:
		upper.append(flavor.to_upper())
	return ", ".join(upper)


func _spec_text(variant: String) -> String:
	var family := VehicleCatalog.family_of(variant)
	var lines := PackedStringArray([
		_pretty(variant),
		"Family: %s" % family,
		"Bus: %s" % VehicleSelect.protocols_for(family),
	])
	var spec: VehicleSpec = _preview.spec if "spec" in _preview else null
	if spec != null:
		lines.append("Drive: %s" % _drive_text(spec))
		lines.append("Mass: %d kg" % roundi(spec.mass))
		lines.append("Gears: %d   Redline: %d rpm" % [spec.gear_ratios.size(),
				roundi(spec.redline_rpm)])
	# Measured off the body standing in the viewport, not off a number in a spec — and off the
	# SETTLED body, so an artic reports the length of the combination and not of its cab.
	if _bounds.size != Vector3.ZERO:
		lines.append("Size: %.1f x %.1f x %.1f m" % [_bounds.size.z, _bounds.size.x,
				_bounds.size.y])
	return "\n".join(lines)


## Same reading garage.gd puts on the wall screen: the tractor spawns rear-drive but engages its
## front axle at runtime, so plain RWD would hide half the driveline.
static func _drive_text(spec: VehicleSpec) -> String:
	if spec.driven_front and spec.driven_rear:
		return "AWD"
	if spec.driven_front:
		return "FWD"
	if spec.driven_rear:
		return "RWD/MFWD" if spec.front_axle_engageable else "RWD"
	return "none"


# --- footer / layout ----------------------------------------------------------

func _update_drive_button() -> void:
	var reason := _refusal(VehicleCatalog.family_of(_variant))
	_drive_btn.disabled = not reason.is_empty()
	_reason_label.text = reason.to_upper()
	# Browsing onto a family this level refuses must not strand the focus ring on the button that
	# just went dead — a gamepad player would be pressing a control that no longer answers.
	if _drive_btn.disabled and _drive_btn.has_focus() and _back_btn != null:
		_back_btn.grab_focus()


## The refusal is checked here and not only on the button: `disabled` is how it LOOKS, this is
## what it means. The level is the authority on what may spawn, and a screen that emitted a pick
## the level would then refuse would put the error somewhere nobody is looking.
func _on_drive() -> void:
	if not _refusal(VehicleCatalog.family_of(_variant)).is_empty():
		return
	vehicle_chosen.emit(_variant)
	if _preview != null and _preview.has_method("set_attachment"):
		attachment_chosen.emit(_attachment)


## Three columns do not fit a phone. The preview is the one that goes: the cards are what you
## cannot pick without, and the turntable is the luxury.
func _reflow() -> void:
	if _preview_panel == null:
		return
	_preview_panel.visible = size.x >= UiTheme.px(self, NARROW_W)
	# The BODY still exists while the panel is hidden — the attachment row is the previewed
	# machine's own answer, so freeing it would take the trailers off a phone entirely. What is
	# switched off is the RENDERING, which is the part that costs anything.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _preview_panel.visible \
			else SubViewport.UPDATE_DISABLED


func _first_available_variant() -> String:
	for variant: String in VehicleCatalog.VARIANTS:
		if _refusal(VehicleCatalog.family_of(variant)).is_empty():
			return variant
	return VehicleCatalog.VARIANTS.keys()[0]
