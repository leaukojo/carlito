// Catches GDScript text damaged by a scripted edit, which still parses and still passes its tests:
//   - a `\` outside a string or comment that is not a line continuation (a dropped newline
//     glued `foo \` onto the next line, or wrote a literal `\n` where a line break belonged);
//   - a file with both CRLF and LF line endings: a warning only, since git stores LF either way;
//     it marks a checkout made before .gitattributes forced LF (tools/setup_machine.ps1 fixes it);
//   - an editor-only class as a type annotation: it parse-fails in an exported build, where the
//     node then silently does nothing (this emptied the deployed terrain once).
//   node tools/check_gd_text.mjs [files...]     # default: every tracked .gd outside addons/
import fs from 'fs';
import { execFileSync } from 'child_process';

const files = (process.argv.length > 2 ? process.argv.slice(2).filter(f => f.endsWith('.gd'))
  : execFileSync('git', ['ls-files', '*.gd'], { encoding: 'utf8' }).split('\n'))
      .filter(f => f && !f.startsWith('addons/'));

// The [^#]* prefix skips comment-only mentions.
const EDITOR_TYPE = /^[^#]*((:|->)\s*|Array\[|\sas\s+)Editor[A-Z][A-Za-z0-9]*/;
const problems = [], mixed = [], editorTypes = [];
for (const f of files) {
  let text;
  try { text = fs.readFileSync(f, 'utf8'); } catch { continue; }
  const crlf = (text.match(/\r\n/g) || []).length;
  const lf = (text.match(/\n/g) || []).length;
  if (crlf && crlf !== lf) mixed.push(f);
  text.split('\n').forEach((l, i) => {
    if (EDITOR_TYPE.test(l)) editorTypes.push(`  ${f}:${i + 1}: ${l.trim()}`);
  });

  // One pass over the file: strings (', ", ''', """, with r/&/^ prefixes) and comments skipped.
  let line = 1, quote = null;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '\n') { line++; if (quote && quote.length === 1) quote = null; continue; }
    if (quote) {
      if (c === '\\') { i++; if (text[i] === '\n') line++; continue; }
      if (text.startsWith(quote, i)) { i += quote.length - 1; quote = null; }
      continue;
    }
    if (c === '#') { while (i + 1 < text.length && text[i + 1] !== '\n') i++; continue; }
    if (c === '"' || c === "'") { quote = text.startsWith(c.repeat(3), i) ? c.repeat(3) : c; i += quote.length - 1; continue; }
    if (c === '\\') {
      const after = text.slice(i + 1, text.indexOf('\n', i + 1) < 0 ? text.length : text.indexOf('\n', i + 1));
      if (after.trim() !== '') problems.push(`  ${f}:${line}: stray \`\\\` outside a string: ${text.slice(i, i + 40).split('\n')[0].trim()}`);
    }
  }
}

if (mixed.length) {
  console.log(`check_gd_text: warning: ${mixed.length} file(s) with mixed line endings in this checkout ` +
    `(${mixed.slice(0, 3).join(', ')}${mixed.length > 3 ? ', ...' : ''}); run tools/setup_machine.ps1 on a clean tree.`);
}
if (editorTypes.length) {
  console.log(`check_gd_text: ${editorTypes.length} editor-only type annotation(s) outside addons/ (breaks exported builds):\n\n${editorTypes.join('\n')}\n`);
  console.log('Fetch it via Engine.get_singleton(&"EditorInterface") into an UNTYPED var.');
}
if (problems.length) {
  console.log(`check_gd_text: ${problems.length} damaged line(s):\n\n${problems.join('\n')}\n`);
  console.log('A scripted (sed/heredoc/python) edit dropped a line break or mixed line endings. Restore the');
  console.log('lines with the Edit tool: a `\\` continuation ends its line, and the file is all LF.');
}
if (editorTypes.length || problems.length) process.exit(1);
console.log(`check_gd_text: ${files.length} GDScript file(s) clean.`);
