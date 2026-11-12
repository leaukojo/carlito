class_name VehicleSelect
extends Control
## Vehicle selector: family list (left), variant + attachment cards (middle), one live turntable
## preview + spec (right, one SubViewport reused rather than one per card).
##
## Nothing is hidden or refused: DRIVE on a family this level won't spawn offers its home level
## (`LevelRegistry.home_of`) behind a confirmation. No emoji; never touches the scene tree it is
## picking for — it emits, and the shell respawns or loads (standing rule 6).

## Emitted on DRIVE. `attachment_chosen` follows immediately after, and only when the picked
## machine tows — so a sentinel is never needed for "no attachment" (DETACHED and BOBTAIL are
## both the empty string, and both are real choices).
signal vehicle_chosen(variant: String)
signal attachment_chosen(id: String)
## Also follows DRIVE, and only for a family whose contract takes a gear byte (`has_gearbox`).
signal gearbox_chosen(manual: bool)
## Also follows DRIVE, and only for a variant that fits more than its stock class (`tyre_choices`).
## Carries the variant: the level may refuse the body, and the choice is still that variant's.
signal tyre_chosen(variant: String, id: String)
## Confirmed DRIVE on a family this level cannot spawn: load `scene_path` with `variant` on it.
## Follows `gearbox_chosen` and `tyre_chosen` (neither needs the level). `attachment` is null when
## the body tows nothing; "" is a real choice (BOBTAIL, DETACHED).
signal level_drive_chosen(scene_path: String, variant: String, attachment: Variant)
signal closed

const CardGrid := preload("res://src/ui/card_grid.gd")

## Logical px (all scaled through UiTheme.px).
const FAMILY_W := 190.0
const CARD_W := 176.0
const PREVIEW_W := 380.0
const FOOTER_W := 240.0  ## larger than a default button: DRIVE is the screen's whole purpose
const CONFIRM_W := 520.0  ## the home-level question's wrap width
const PULSE_S := 1.1       ## the DRIVE button's one pulse, triggered by a press on the picked card
## What the DRIVE button's modulate reaches at the pulse's peak: the accent fill turns green.
const PULSE_TINT := Color(0.55, 1.35, 0.6)
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
var _level_scene := ""  ## the level open under the garage; a family whose home it is never redirects
var _has_rail := false
## `Level.has_spawn_for`, bound by the shell; invalid (unset) reads as "assume a spawn exists" so
## a caller that doesn't pass it keeps the old behaviour rather than refusing everything.
var _has_spawn := Callable()
var _variant := ""
var _attachment := ""                  ## seeded from the driven machine, then owned by the preview
## Variant `_attachment` was seeded from. "" is not "nothing handed over" — it's BOBTAIL and
## DETACHED, both real choices; without this a car's "" browsed to the semi would show bobtail.
var _attachment_of := ""
var _manual_gearbox := false  ## seeded from the shell's free-play choice
var _tyres := {}  ## variant -> TyreClass id, seeded from the shell's store; a pick updates it
var _tyre := ""   ## the class picked for the variant on show; "" with no TYRES row or a lone class

var _pulse_left := 0.0  ## seconds left of the DRIVE button's pulse (0 = at rest)

var _family := ""
var _col: VBoxContainer
var _families_scroll: ScrollContainer
var _families: VBoxContainer
var _cards: VBoxContainer
var _preview_frame: SubViewportContainer
var _preview_panel: PanelContainer
var _viewport: SubViewport
var _camera: Camera3D
var _preview: Node3D = null
var _spec_label: Label
var _drive_btn: Button
var _back_btn: Button
var _confirm: ColorRect       ## the home-level question, over the whole screen while up
var _confirm_title: Label
var _confirm_line: Label
var _confirm_load: Button
var _confirm_cancel: Button
var _yaw := VehicleShot.VIEW_YAW_DEG
var _bounds := AABB()
var _settle := 0


## `allowed` is the level's raw allow-list, `rail` its runtime closed-loop answer — both rather
## than a pre-filtered roster, since the screen shows what it cannot spawn and must say why.
## `has_spawn` is `Level.has_spawn_for`, invalid (default) when the caller has none to offer.
## `tyres` is the stored class per variant (`UserSettings.tyre_of`). `level_scene` is the open
## level's path.
func setup(allowed: PackedStringArray, level_name: String, rail: bool,
		variant: String, attachment: String, manual_gearbox := false,
		has_spawn := Callable(), tyres := {}, level_scene := "") -> void:
	_tyres = tyres.duplicate()
	_allowed = allowed
	_level_name = level_name
	_level_scene = level_scene
	_has_rail = rail
	_variant = variant if VehicleCatalog.VARIANTS.has(variant) else ""
	_attachment = attachment
	_attachment_of = _variant
	_manual_gearbox = manual_gearbox
	_has_spawn = has_spawn


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_col = VBoxContainer.new()
	var col := _col
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
	_confirm = _build_confirm()
	add_child(_confirm)  # last: drawn over everything, and its scrim takes every click

	if _variant.is_empty():
		_variant = _first_available_variant()
	_family = VehicleCatalog.family_of(_variant)
	_refresh_families()
	_refresh_cards()
	_show_preview(_variant)
	resized.connect(_reflow)
	_apply_sizes()
	set_process(true)
	var entry := _drive_btn if not _drive_btn.disabled else _back_btn
	entry.grab_focus()


## Every pixel size, from the theme's scale. Run on build and again on a theme change (a window
## resize or UI SIZE), when the fonts have grown and these would otherwise stay as they were.
func _apply_sizes() -> void:
	_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE,
			int(UiTheme.px(self, UiTheme.MARGIN)))
	_families_scroll.custom_minimum_size.x = UiTheme.px(self, FAMILY_W)
	_preview_panel.custom_minimum_size.x = UiTheme.px(self, PREVIEW_W)
	var inner := PREVIEW_W - UiTheme.PAD_X * 2.0
	_preview_frame.custom_minimum_size = Vector2(UiTheme.px(self, inner),
			UiTheme.px(self, inner * VehicleShot.CARD_ASPECT))
	var footer_size := Vector2(UiTheme.px(self, FOOTER_W), UiTheme.px(self, UiTheme.TOUCH_MIN * 1.5))
	_back_btn.custom_minimum_size = footer_size
	_drive_btn.custom_minimum_size = footer_size
	_confirm_load.custom_minimum_size = footer_size
	_confirm_cancel.custom_minimum_size = footer_size
	_reflow()


## The theme is rebuilt on a resize: lay the page out again. Deferred, as the cards it replaces are
## still being walked by the propagation that fired this.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _drive_btn != null:
		_relayout.call_deferred()


func _relayout() -> void:
	var key := _focus_key()
	_apply_sizes()
	_refresh_families()
	_refresh_cards()
	_refresh_tyres()
	_refocus(key)


## Rebuilding a column frees the button the pad was on. Each family button and card carries a
## "pick" key, so the rebuild can put focus back on its twin: left / right / down then go on from
## where the player was, not from nothing.
func _focus_key() -> String:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return String(focus.get_meta("pick", "")) if focus != null else ""


## Focus the control keyed `key`, for a keyboard or pad. A mouse needs none: the picked card is
## already marked, and a focus rim would only echo the hover one.
func _refocus(key: String) -> void:
	if key.is_empty() or _pointer_in_use():
		return
	for column: Control in [_families, _cards]:
		for b in column.find_children("*", "Button", true, false):
			if String(b.get_meta("pick", "")) == key:
				(b as Button).grab_focus()
				return


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
	_families_scroll = scroll
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
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_preview_frame = SubViewportContainer.new()
	_preview_frame.stretch = true
	_preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_preview_frame)

	_viewport = SubViewport.new()
	_preview_frame.add_child(_viewport)
	_camera = VehicleShot.build_stage(_viewport)

	_spec_label = Label.new()
	_spec_label.theme_type_variation = &"Dim"
	_spec_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_spec_label)
	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	_back_btn = Button.new()
	_back_btn.text = "BACK"
	_back_btn.theme_type_variation = &"Back"
	_back_btn.pressed.connect(func() -> void: closed.emit())
	row.add_child(_back_btn)

	# Pulses once on a press on the picked card, see _pulse_drive.
	_drive_btn = Button.new()
	_drive_btn.text = "DRIVE"
	_drive_btn.theme_type_variation = &"Primary"
	_drive_btn.pressed.connect(_on_drive)
	row.add_child(_drive_btn)
	_wrap(row)
	return row


## A footer button's text wraps rather than widening it past a narrow window (`_fit_pair`):
## "DRIVE IN LEVEL 5 - RAILWAY" is the longest.
static func _wrap(row: Node) -> void:
	for b in row.get_children():
		(b as Button).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The home-level question: a scrim over the whole screen with a centred panel, hidden until DRIVE
## is pressed on a family this level cannot spawn. Texts are written as it opens (`_show_confirm`).
func _build_confirm() -> ColorRect:
	var scrim := ColorRect.new()
	scrim.color = UiTheme.SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	_confirm_title = Label.new()
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_title.theme_type_variation = &"Title"
	box.add_child(_confirm_title)
	_confirm_line = Label.new()
	_confirm_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_confirm_line)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_confirm_load = UiTheme.button(self, "", _on_load_home)
	_confirm_load.theme_type_variation = &"Primary"
	row.add_child(_confirm_load)
	_confirm_cancel = UiTheme.button(self, "CANCEL", _hide_confirm)
	_confirm_cancel.theme_type_variation = &"Back"
	row.add_child(_confirm_cancel)
	_wrap(row)
	return scrim


# --- family column ------------------------------------------------------------

## Order is the selector's own, not the catalog's: road machines first, then the rest. A family
## missing from FAMILY_ORDER still lists (catalog order, after the named ones).
const FAMILY_ORDER := ["car", "truck", "tractor", "boat", "drone", "plane", "train"]

## Ends every refusal: DRIVE is dead, and the BODY heading says what to do about it. Only reached
## by a family whose home level is the one open (`_redirect`), so a level that has lost its spawn.
const CHOOSE_ANOTHER := " - choose another level"
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
		return "cannot spawn in %s%s" % [_level_name, CHOOSE_ANOTHER]
	if family == "train":
		return "" if _has_rail else "no closed rail loop here" + CHOOSE_ANOTHER
	if _has_spawn.is_valid() and not bool(_has_spawn.call(family)):
		return "cannot spawn here" + CHOOSE_ANOTHER
	return ""


## The scene DRIVE loads for `family` instead: its home level, when this level refuses it and is
## not that home. "" when the family drives here, or is refused with no elsewhere to go.
func _redirect(family: String) -> String:
	if _refusal(family).is_empty():
		return ""
	var home := LevelRegistry.home_of(family)
	return home if home != _level_scene else ""


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
		b.set_meta("pick", "family:" + family)
		b.pressed.connect(_on_family_pressed.bind(family))
		_families.add_child(b)


func _on_family_pressed(family: String) -> void:
	var key := _focus_key()
	if family == _family:
		_refresh_families()  # toggle buttons un-toggle themselves; this is a radio group
		_refocus(key)
		return
	_family = family
	_refresh_families()
	_refocus(key)
	_refresh_cards()
	_show_preview(VehicleCatalog.first_in_family(family))


# --- card grid ----------------------------------------------------------------

func _refresh_cards() -> void:
	_clear(_cards)
	var reason := _refusal(_family)
	var home := _redirect(_family)
	var note := reason
	var tip := ""
	if not home.is_empty():  # not refused: DRIVE goes to the home level
		tip = "drives in " + LevelRegistry.name_of(home)
		note = "not in %s: %s" % [_level_name, tip]
		reason = ""
	if FamilyGearbox.has_gearbox(_family):
		_cards.add_child(_gearbox_row())
	_cards.add_child(_heading("BODY", note))
	_cards.add_child(_card_grid(VehicleCatalog.variants_in_family(_family), _variant,
			reason, _on_variant_pressed, tip))
	_refresh_attachments()


## AUTOMATIC | MANUAL as one ButtonGroup (InputRouter.set_manual_gearbox): MANUAL is sloppyCAN's
## gear byte while a bridge is connected, else the local driver's shift control.
func _gearbox_row() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_heading("GEARBOX"))
	var row := HBoxContainer.new()
	var group := ButtonGroup.new()
	for manual: bool in [false, true]:
		var b := Button.new()
		b.text = "MANUAL" if manual else "AUTOMATIC"
		b.custom_minimum_size.y = UiTheme.px(self, UiTheme.TOUCH_MIN)
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"Choice"
		b.button_pressed = manual == _manual_gearbox
		b.pressed.connect(_on_gearbox_pressed.bind(manual))
		row.add_child(b)
	box.add_child(row)
	return box


func _on_gearbox_pressed(manual: bool) -> void:
	_manual_gearbox = manual


## The classes the previewed body may fit, as one ButtonGroup between GEARBOX and BODY; none only
## for a body with no ground drive. Read off the preview's spec, so it is rebuilt on every preview swap.
func _refresh_tyres() -> void:
	for child in _cards.get_children():
		if child.has_meta("tyres"):
			_cards.remove_child(child)
			child.queue_free()
	_tyre = ""
	var spec: VehicleSpec = _preview.spec if _preview != null and "spec" in _preview else null
	var choices := VehicleSelect.tyre_choices(spec.ground_drive if spec != null else null)
	if choices.is_empty():
		return
	var ids := choices.map(func(c: TyreClass) -> String: return c.id)
	var stored := String(_tyres.get(_variant, ""))
	# One class is no choice: the row shows it picked, and DRIVE sends no tyre.
	var single := choices.size() < 2
	_tyre = "" if single else (stored if ids.has(stored) else choices[0].id)
	var box := VBoxContainer.new()
	box.set_meta("tyres", true)
	box.add_child(_heading("TYRES"))
	var row := HFlowContainer.new()
	var group := ButtonGroup.new()
	for cls in choices:
		var b := Button.new()
		b.text = cls.display_name.to_upper()
		b.custom_minimum_size.y = UiTheme.px(self, UiTheme.TOUCH_MIN)
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"Choice"
		b.button_pressed = single or cls.id == _tyre
		if not single:  # the lone class is shown picked, and there is nothing to pick instead
			b.pressed.connect(_on_tyre_pressed.bind(cls.id))
		row.add_child(b)
	box.add_child(row)
	_cards.add_child(box)
	_cards.move_child(box, 1 if FamilyGearbox.has_gearbox(_family) else 0)


func _on_tyre_pressed(id: String) -> void:
	_tyre = id
	_tyres[_variant] = id


## The classes a body of `gd` may fit, its stock first and then `TyreCatalog`'s order; empty only
## with no ground drive (a boat). A body that fits only its stock lists that one class.
static func tyre_choices(gd: GroundDriveSpec) -> Array[TyreClass]:
	var out: Array[TyreClass] = []
	if gd == null or gd.tyre == null:
		return out
	out.append(gd.tyre)
	for cls in TyreCatalog.fitting(gd.tyre_fit):
		if cls.id != gd.tyre.id:
			out.append(cls)
	return out


func _heading(text: String, reason := "") -> Label:
	var l := Label.new()
	l.text = text if reason.is_empty() else "%s  -  %s" % [text, reason.to_upper()]
	l.theme_type_variation = &"Title" if reason.is_empty() else &"MutedSmall"
	return l


## `ids` are thumbnail ids (a variant id, or an attachment scene path resolved through
## VehicleShot.id_for_scene); the empty id is a real catalog entry, plated NONE. `reason` refuses
## the cards; `tip` is the tooltip of a live one.
func _card_grid(ids: PackedStringArray, selected: String, reason: String,
		on_press: Callable, tip := "") -> Control:
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in ids:
		grid.add_child(_make_card(id, id == selected, reason, on_press, tip))
	return grid


func _make_card(id: String, selected: bool, reason: String, on_press: Callable,
		tip := "") -> Button:
	var thumb_id := VehicleShot.id_for_scene(id) if id.contains("/") else id
	var thumb_path := VehicleShot.thumb_path(thumb_id) if not thumb_id.is_empty() else ""
	var refused := not reason.is_empty()
	var card := CardGrid.picture_card(self, CARD_W, VehicleShot.CARD_ASPECT, BORDER_W, selected,
			thumb_path, _pretty(thumb_id) if not thumb_id.is_empty() else "NONE",
			&"MutedSmall" if refused else &"Dim", "", Color.TRANSPARENT, refused)
	card.disabled = refused
	card.tooltip_text = reason if refused else tip
	card.set_meta("pick", "card:" + id)
	card.pressed.connect(on_press.bind(id))
	return card


static func _pretty(id: String) -> String:
	return id.replace("-", " ").replace("_", " ").to_upper()


func _on_variant_pressed(variant: String) -> void:
	if variant == _variant:
		_point_at_drive()
		return
	var key := _focus_key()
	_variant = variant
	_refresh_cards()
	_show_preview(variant)
	_refocus(key)


## A press on what is already picked means "this one": DRIVE pulses once. Focus stays on the card,
## so a pad can still step to the next body. A refused body has no live DRIVE to point at.
func _point_at_drive() -> void:
	if not _drive_btn.disabled:
		_pulse_left = PULSE_S


## Whether the mouse or a finger was the last device used (UiScale owns that). Unknown (no
## UiScale above, as in a bare test) reads as no.
func _pointer_in_use() -> bool:
	var node := get_parent()
	while node != null and not node is UiScale:
		node = node.get_parent()
	return node != null and (node as UiScale).device() == UiScale.Device.POINTER


func _on_attachment_pressed(id: String) -> void:
	if id == _attachment and _attachment_of == _variant:
		_point_at_drive()
		return
	var key := _focus_key()
	_attachment = id
	_attachment_of = _variant
	if _preview != null and _preview.has_method("set_attachment"):
		_preview.set_attachment(id)
		VehicleShot.pin_display(_preview)
	_refresh_attachments()
	_refocus(key)


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
	_tyre = ""  # a body that fails to show offers no TYRES row, so DRIVE sends none
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
	_refresh_tyres()
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
		_pulse_left = 0.0
		return
	if _pulse_left <= 0.0:
		_drive_btn.modulate = Color.WHITE
		return
	_pulse_left = maxf(_pulse_left - delta, 0.0)
	# A hue change, not a brightness swing: the blue fill goes green and back, holding near full.
	var swell := clampf(sin((1.0 - _pulse_left / PULSE_S) * PI) * 1.4, 0.0, 1.0)
	_drive_btn.modulate = Color.WHITE.lerp(PULSE_TINT, swell)


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
		lines.append("Drive: %s" % GroundDriveSpec.layout_text(spec.ground_drive))
		lines.append("Mass: %d kg" % roundi(spec.mass))
		if spec.has_engine:  # drone/train have no crank to quote
			lines.append("Gears: %s   Redline: %d rpm" % [Drivetrain.gears_label(spec),
					roundi(spec.redline_rpm)])
	# Measured off the settled body, not a spec number, so an artic reports the combination's
	# length, not its cab's.
	if _bounds.size != Vector3.ZERO:
		lines.append("Size: %.1f x %.1f x %.1f m" % [_bounds.size.z, _bounds.size.x,
				_bounds.size.y])
	return "\n".join(lines)


# --- footer / layout ----------------------------------------------------------

func _update_drive_button() -> void:
	var family := VehicleCatalog.family_of(_variant)
	var home := _redirect(family)
	_drive_btn.text = "DRIVE" if home.is_empty() \
			else "DRIVE IN " + LevelRegistry.name_of(home).to_upper()
	_drive_btn.disabled = home.is_empty() and not _refusal(family).is_empty()
	if _drive_btn.disabled and _drive_btn.has_focus() and _back_btn != null:
		_back_btn.grab_focus()  # must not strand the focus ring on a button that just went dead


## Checked here too, not only via the button's `disabled`: the level is the authority on what
## may spawn. A family it refuses goes to its home level, after asking.
func _on_drive() -> void:
	var family := VehicleCatalog.family_of(_variant)
	if not _redirect(family).is_empty():
		_show_confirm()
		return
	if not _refusal(family).is_empty():
		return
	vehicle_chosen.emit(_variant)
	if _tows():
		attachment_chosen.emit(_attachment)
	_emit_fit(family)


## The gearbox and tyre picks, which neither the level nor the body on show needs to apply.
func _emit_fit(family: String) -> void:
	if FamilyGearbox.has_gearbox(family):
		gearbox_chosen.emit(_manual_gearbox)
	if not _tyre.is_empty():
		tyre_chosen.emit(_variant, _tyre)


func _tows() -> bool:
	return _preview != null and _preview.has_method("set_attachment")


## Leaving the level is a bigger step than a respawn (the position and the level's state go), so
## the redirect asks. LOAD takes the focus: DRIVE was already a deliberate press.
func _show_confirm() -> void:
	var home := _redirect(VehicleCatalog.family_of(_variant))
	var level := LevelRegistry.name_of(home)
	var weight := LevelRegistry.weight_text(home)
	_confirm_title.text = "NOT AVAILABLE IN " + _level_name.to_upper()
	_confirm_line.text = "Leave %s and load %s%s to drive the %s?" % [_level_name, level,
			" (%s)" % weight if not weight.is_empty() else "", _pretty(_variant)]
	_confirm_load.text = "LOAD " + level.to_upper()
	# The pair keeps the focus: the cards under the scrim must not be reachable on a pad.
	for b: Button in [_confirm_load, _confirm_cancel]:
		var other := _confirm_cancel if b == _confirm_load else _confirm_load
		b.focus_neighbor_left = b.get_path_to(other)
		b.focus_neighbor_right = b.get_path_to(other)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_next = b.get_path_to(other)
		b.focus_previous = b.get_path_to(other)
	_confirm.visible = true
	_confirm_load.grab_focus()


func _hide_confirm() -> void:
	_confirm.visible = false
	if not _pointer_in_use():
		_drive_btn.grab_focus()


func _on_load_home() -> void:
	var family := VehicleCatalog.family_of(_variant)
	var home := _redirect(family)
	_hide_confirm()
	if home.is_empty():
		return
	_emit_fit(family)
	level_drive_chosen.emit(home, _variant, _attachment if _tows() else null)


## Circle / Esc (the shell's back): closes the question first, the garage only after. True when it
## closed something here.
func back() -> bool:
	if _confirm != null and _confirm.visible:
		_hide_confirm()
		return true
	return false


func _reflow() -> void:
	if _preview_panel == null:
		return
	# The footer and the question narrow, and their texts wrap, inside a phone-width window
	# rather than running off its edges.
	var room := size.x - UiTheme.px(self, UiTheme.MARGIN * 2.0)
	if room <= 0.0:  # not laid out yet: the full sizes
		room = INF
	var panel := _confirm_line.get_parent().get_parent() as PanelContainer
	var inner := room - panel.get_theme_stylebox(&"panel").get_minimum_size().x
	_confirm_line.custom_minimum_size.x = minf(UiTheme.px(self, CONFIRM_W), inner)
	_fit_pair(_back_btn, _drive_btn, room)
	_fit_pair(_confirm_load, _confirm_cancel, inner)
	_preview_panel.visible = size.x >= UiTheme.px(self, NARROW_W)
	# The body still exists while the panel is hidden; only the rendering is switched off.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _preview_panel.visible \
			else SubViewport.UPDATE_DISABLED


## Two buttons side by side at FOOTER_W each, or half of `room` each when that is less.
func _fit_pair(a: Button, b: Button, room: float) -> void:
	var gap := float((a.get_parent() as Control).get_theme_constant(&"separation"))
	var w := minf(UiTheme.px(self, FOOTER_W), (room - gap) * 0.5)
	a.custom_minimum_size.x = w
	b.custom_minimum_size.x = w


func _first_available_variant() -> String:
	for variant: String in VehicleCatalog.VARIANTS:
		if _refusal(VehicleCatalog.family_of(variant)).is_empty():
			return variant
	return VehicleCatalog.VARIANTS.keys()[0]
