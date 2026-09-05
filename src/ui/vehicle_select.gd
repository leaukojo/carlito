class_name VehicleSelect
extends Control
## Vehicle selector: family list (left), variant + attachment cards (middle), one live turntable
## preview + spec (right, one SubViewport reused rather than one per card).
##
## Nothing is hidden: a family this level won't spawn is still browsable and carries the reason
## on its cards. Only DRIVE is refused. No emoji; never touches the scene tree it is picking
## for — it emits, and the shell respawns (standing rule 6).

## Emitted on DRIVE. `attachment_chosen` follows immediately after, and only when the picked
## machine tows — so a sentinel is never needed for "no attachment" (DETACHED and BOBTAIL are
## both the empty string, and both are real choices).
signal vehicle_chosen(variant: String)
signal attachment_chosen(id: String)
signal closed

const CardGrid := preload("res://src/ui/card_grid.gd")

## Logical px (all scaled through UiTheme.px).
const FAMILY_W := 190.0
const CARD_W := 176.0
const PREVIEW_W := 380.0
const FOOTER_W := 240.0  ## larger than a default button: DRIVE is the screen's whole purpose
const PULSE_DEPTH := 0.16  ## DRIVE button attention pulse: brightness swing
const PULSE_HZ := 0.9      ## ...and speed
const BORDER_W := 3.0
## Width the three columns need (family list + preview + two cards + margins); below this the
## preview column is dropped since it's the phone-unfriendly one and cards are what you can't
## pick without.
const NARROW_W := FAMILY_W + PREVIEW_W + CARD_W * 2.0 + UiTheme.MARGIN * 4.0
const TURNTABLE_DEG_PER_S := 24.0
## Frames after a preview swap during which bounds are re-measured every frame instead of
## cached: a body isn't its final size on the tick it's added (wheel poses, trailer coupling).
const SETTLE_FRAMES := 20

var _allowed: PackedStringArray = []   ## the level's LevelInfo.allowed_vehicles, unfiltered
var _level_name := "this level"
var _has_rail := false
var _variant := ""
var _attachment := ""                  ## seeded from the driven machine, then owned by the preview
## Variant `_attachment` was seeded from. "" is not "nothing handed over" — it's BOBTAIL and
## DETACHED, both real choices; without this a car's "" browsed to the semi would show bobtail.
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


## `allowed` is the level's raw allow-list, `rail` its runtime closed-loop answer — both rather
## than a pre-filtered roster, since the screen shows what it cannot spawn and must say why.
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
	var entry := _drive_btn if not _drive_btn.disabled else _back_btn
	entry.grab_focus()


## Wipe a container now rather than at end of frame: `queue_free` alone leaves the old children
## in `get_children()` until the flush, so the next rebuild would see and re-free them.
static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- construction -------------------------------------------------------------

func _build_families() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.x = UiTheme.px(self, FAMILY_W)
	_families = VBoxContainer.new()
	_families.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_families)
	return scroll


func _build_cards() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards)
	return scroll


## The SubViewport is built once and outlives every selection; only the body inside it swaps.
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

	# Breathes while live, see _process.
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

## Order is the selector's own, not the catalog's: road machines first, then the rest. A family
## missing from FAMILY_ORDER still lists (catalog order, after the named ones).
const FAMILY_ORDER := ["car", "truck", "tractor", "boat", "drone", "plane", "train"]

const BETA_FAMILIES := ["train", "boat", "plane", "drone"]  ## rougher than road vehicles, labelled so

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


## Why this level will not spawn `family`, or "" when it will. Both reasons are derived rather
## than hand-written prose, so this stays the one place the truth about a level lives.
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
		# `Choice` marks it like the picture cards; the theme's plain `pressed` box reads recessed.
		b.theme_type_variation = &"Choice"
		b.button_pressed = family == _family
		b.tooltip_text = VehicleSelect.protocols_for(family)
		b.pressed.connect(_on_family_pressed.bind(family))
		_families.add_child(b)


func _on_family_pressed(family: String) -> void:
	if family == _family:
		_refresh_families()  # toggle buttons un-toggle themselves; this is a radio group
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
	_refresh_attachments()


func _heading(text: String, reason := "") -> Label:
	var l := Label.new()
	l.text = text if reason.is_empty() else "%s  -  %s" % [text, reason.to_upper()]
	l.theme_type_variation = &"Title" if reason.is_empty() else &"MutedSmall"
	return l


## `ids` are thumbnail ids (a variant id, or an attachment scene path resolved through
## VehicleShot.id_for_scene); the empty id is a real catalog entry, plated NONE.
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
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(state,
				CardGrid.card_box(self, BORDER_W, selected or state in ["hover", "focus"]))
	card.pressed.connect(on_press.bind(id))

	# The picture is inset by the border: a StyleBox is the button's background, so a full-rect
	# child would paint over it and hide the selection border entirely.
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
		VehicleShot.pin_display(_preview)
	_refresh_attachments()


## Exists only when the previewed machine says it tows (duck-type, same as the shell uses for
## cycle_implement). Rebuilt on every preview swap.
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

## `display_only` keeps the preview out of InputRouter's single vehicle slot, else it would take
## the driven body's place in local arbitration and null it again on its way out.
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
	# See _attachment_of for why "" cannot be the test here.
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
	# remove_child before queue_free: physics steps run before the end-of-frame flush, so a
	# deferred free alone would leave the old machine in the world under the new one.
	if _preview.get_parent() != null:
		_preview.get_parent().remove_child(_preview)
	_preview.queue_free()
	_preview = null
	_bounds = AABB()
	_settle = 0


## Camera orbits, never the body — rotating a frozen RigidBody3D fights the physics server for
## a transform it already writes every tick. Runs while the tree is paused, so _process is the
## clock here.
func _process(delta: float) -> void:
	_pulse_drive(delta)
	if _preview == null or not is_instance_valid(_preview) or not _preview_panel.visible:
		return
	_yaw = fmod(_yaw + TURNTABLE_DEG_PER_S * delta, 360.0)
	if _settle > 0:
		_settle -= 1
		_bounds = VehicleShot.subject_bounds(_preview)
		if _settle == 0:
			_spec_label.text = _spec_text(_variant)
	if _bounds.size == Vector3.ZERO:
		return
	VehicleShot.frame(_camera, _bounds, _yaw)


## Modulate rather than a Tween: must stop dead when the level refuses the previewed family, or
## a still-pulsing disabled button invites the press the screen is about to reject.
func _pulse_drive(delta: float) -> void:
	if _drive_btn.disabled:
		_drive_btn.modulate = Color.WHITE
		_pulse_t = 0.0
		return
	_pulse_t = fmod(_pulse_t + delta * PULSE_HZ, 1.0)
	var k := 1.0 + PULSE_DEPTH * sin(_pulse_t * TAU)
	_drive_btn.modulate = Color(k, k, k)


# --- spec line ----------------------------------------------------------------

## Read out of the contract rather than typed here (rule 4): a family's flavors are its
## borrowed profiles; one that borrows none says so.
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
		if spec.has_engine:  # drone/train have no crank to quote
			lines.append("Gears: %d   Redline: %d rpm" % [spec.gear_ratios.size(),
					roundi(spec.redline_rpm)])
	# Measured off the settled body, not a spec number, so an artic reports the combination's
	# length, not its cab's.
	if _bounds.size != Vector3.ZERO:
		lines.append("Size: %.1f x %.1f x %.1f m" % [_bounds.size.z, _bounds.size.x,
				_bounds.size.y])
	return "\n".join(lines)


## Same reading garage.gd's wall screen uses: the tractor spawns rear-drive but engages its
## front axle at runtime, so plain RWD would hide half the driveline.
static func _drive_text(spec: VehicleSpec) -> String:
	var gd := spec.ground_drive
	if gd == null:
		return "none"
	if gd.driven_front and gd.driven_rear:
		return "AWD"
	if gd.driven_front:
		return "FWD"
	if gd.driven_rear:
		return "RWD/MFWD" if gd.front_axle_engageable else "RWD"
	return "none"


# --- footer / layout ----------------------------------------------------------

func _update_drive_button() -> void:
	var reason := _refusal(VehicleCatalog.family_of(_variant))
	_drive_btn.disabled = not reason.is_empty()
	_reason_label.text = reason.to_upper()
	if _drive_btn.disabled and _drive_btn.has_focus() and _back_btn != null:
		_back_btn.grab_focus()  # must not strand the focus ring on a button that just went dead


## Checked here too, not only via the button's `disabled`: the level is the authority on what
## may spawn.
func _on_drive() -> void:
	if not _refusal(VehicleCatalog.family_of(_variant)).is_empty():
		return
	vehicle_chosen.emit(_variant)
	if _preview != null and _preview.has_method("set_attachment"):
		attachment_chosen.emit(_attachment)


func _reflow() -> void:
	if _preview_panel == null:
		return
	_preview_panel.visible = size.x >= UiTheme.px(self, NARROW_W)
	# The body still exists while the panel is hidden; only the rendering is switched off.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _preview_panel.visible \
			else SubViewport.UPDATE_DISABLED


func _first_available_variant() -> String:
	for variant: String in VehicleCatalog.VARIANTS:
		if _refusal(VehicleCatalog.family_of(variant)).is_empty():
			return variant
	return VehicleCatalog.VARIANTS.keys()[0]
