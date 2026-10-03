extends GdUnitTestSuite
## Rule 10: the web font has no emoji glyphs. test_action_registry and test_challenge_registry
## guard the registry labels and the challenge defs' text fields; this guards every other string
## literal the player can see — the UI, the shell, and the challenge goals' runtime messages —
## against the font itself, so a glyph Barlow does carry (the dashboard's degree sign) passes.

const FONT := "res://src/ui/theme/font/Barlow-Regular.ttf"
const DIRS: Array[String] = ["res://src/ui", "res://src/shell", "res://src/challenges"]
const EXTS: Array[String] = ["gd", "tscn", "tres"]


func test_every_player_facing_string_is_in_the_font() -> void:
	var font := load(FONT) as FontFile
	assert_object(font).is_not_null()
	# The check can fail: the font really lacks an emoji and really has the degree sign.
	assert_bool(font.has_char(0x1F600)).is_false()
	assert_bool(font.has_char(0x00B0)).is_true()
	var files: Array[String] = []
	for dir in DIRS:
		_walk(dir, files)
	assert_int(files.size()).is_greater(0)
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for c in _string_chars(lines[i], path.get_extension() == "gd"):
				assert_bool(font.has_char(c)) \
					.override_failure_message("%s:%d: U+%04X is not in %s" % [
						path, i + 1, c, FONT.get_file()]) \
					.is_true()


## The non-ASCII code points inside quoted literals on one line. In GDScript a `#` outside a
## string ends the code, so prose in comments is not checked. A resource's multi-line strings
## span raw lines, so there every character counts.
func _string_chars(line: String, is_gd: bool) -> Array[int]:
	var out: Array[int] = []
	if not is_gd:
		for i in line.length():
			if line.unicode_at(i) >= 128:
				out.append(line.unicode_at(i))
		return out
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote != "":
			if ch == "\\":
				i += 1
			elif ch == quote:
				quote = ""
			elif line.unicode_at(i) >= 128:
				out.append(line.unicode_at(i))
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "#":
			break
		i += 1
	return out


func _walk(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in EXTS:
			out.append(dir.path_join(file))
