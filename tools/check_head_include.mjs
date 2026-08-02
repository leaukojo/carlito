// Guard for the manual head-include sync (CLAUDE.md: "edit the source and re-paste
// into the preset; they must match"): the <script> block of
// src/bridge/web/head_include.html must equal export_presets.cfg's html/head_include.
// Exit 1 with a diff hint when they drift. Run standalone or via preflight/pre-commit.
import { readFileSync } from "node:fs";

const norm = (s) => s.replace(/\r\n/g, "\n").trim();

const cfg = readFileSync("export_presets.cfg", "utf8");
const key = 'html/head_include="';
const start = cfg.indexOf(key);
if (start < 0) {
  console.error("check_head_include: html/head_include not found in export_presets.cfg");
  process.exit(1);
}
// Scan to the closing unescaped quote (the value spans real newlines; ConfigFile
// escapes internal quotes as \" and backslashes as \\).
let i = start + key.length;
let val = "";
for (; i < cfg.length; i++) {
  const c = cfg[i];
  if (c === "\\" && i + 1 < cfg.length) {
    val += cfg[i + 1] === "n" ? "\n" : cfg[i + 1] === "t" ? "\t" : cfg[i + 1];
    i++;
  } else if (c === '"') {
    break;
  } else {
    val += c;
  }
}

// The file's comment header mentions "<script>" in prose, so take the LAST opening tag.
const src = readFileSync("src/bridge/web/head_include.html", "utf8");
const open = src.lastIndexOf("<script>");
const close = src.lastIndexOf("</script>");
if (open < 0 || close < open) {
  console.error("check_head_include: no <script> block in src/bridge/web/head_include.html");
  process.exit(1);
}
const block = src.slice(open, close + "</script>".length);

if (norm(val) !== norm(block)) {
  console.error(
    "check_head_include: export_presets.cfg html/head_include differs from the\n" +
    "<script> block of src/bridge/web/head_include.html.\n" +
    "Fix: edit the source file, then paste its <script> block verbatim into the\n" +
    "Web export preset's Head Include field (or directly into export_presets.cfg)."
  );
  process.exit(1);
}
console.log("check_head_include: preset matches source.");
