## Rewrites one generated region of a doc in place: the lines between
## `<!-- measure:<id> ... -->` and `<!-- /measure:<id> -->`. The measure tools' `doc=<id>` presets
## write their figure tables through it, so a figure refreshes by re-running the tool; the opening
## marker names that run line, and hand edits between the markers are overwritten.

const DOC := "res://docs/vehicles.md"
const WIDTH := 100


## Replaces region `id`'s body with `lines` and prints what it did; false (and a printed error)
## when the doc or either marker is missing, the doc then left untouched.
static func write(id: String, lines: Array[String]) -> bool:
	var path := ProjectSettings.globalize_path(DOC)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("doc region %s: cannot read %s" % [id, DOC])
		return false
	var raw := f.get_as_text()
	var crlf := raw.contains("\r\n")
	var text := raw.replace("\r\n", "\n")
	f.close()
	var open := text.find("<!-- measure:%s " % id)
	var body_start := text.find("\n", open) + 1 if open >= 0 else -1
	var close := text.find("<!-- /measure:%s -->" % id, body_start) if body_start > 0 else -1
	if close < 0:
		printerr("doc region %s: markers not found in %s" % [id, DOC])
		return false
	text = text.substr(0, body_start) + "\n".join(lines) + "\n" + text.substr(close)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.replace("\n", "\r\n") if crlf else text)
	f.close()
	print("doc region %s: %d line(s) written to %s" % [id, lines.size(), DOC])
	return true


## `text` broken at spaces into lines of at most WIDTH, the doc's own wrap.
static func wrap(text: String) -> Array[String]:
	var lines: Array[String] = []
	var line := ""
	for word in text.split(" ", false):
		if line != "" and line.length() + 1 + word.length() > WIDTH:
			lines.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		lines.append(line)
	return lines


## "Measured YYYY-MM-DD", today's date: every region opens on it.
static func measured() -> String:
	return "Measured %s" % Time.get_date_string_from_system()
