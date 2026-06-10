# De-obfuscating Dense Shell Functions

A skill for making terse, expert-written POSIX shell functions readable **without
changing their behaviour**. The goal is to lower the mental load of parsing each line,
not to rewrite the logic.

## When to use

The user points at one or more shell functions written in concise, expressive "senior
Unix engineer" style (single-letter vars, chained `awk`/`sed`/`grep`, clever parameter
expansions) and wants them to read smoothly.

## Core rules

1. **Preserve behaviour exactly.** De-obfuscation ≠ refactor. If a clean-up would
   change *what the code does* (not just how it reads), stop and ask first. Flag it
   explicitly; don't fold it in silently.
2. **`awk` → `sed`** where an equivalent exists. Watch the field-separator gotcha:
   `awk '{print "    ",$0}'` outputs the 4-space literal **plus** the one-space `OFS`
   = **5** spaces, so the faithful sed is `sed 's/^/     /'` (5 spaces). Verify counts.
3. **Comment every `sed` and every regex** — one line each. Say what it matches/does,
   ideally with a concrete before→after example for non-trivial expressions.
4. **Informative variable names.** No single letters or cryptic abbreviations
   (`__f` → `script_file` / `exe_name`, `__g` → `alias_name`, `__nf` →
   `wrapper_link_count`). **But** keep short names that are already clear and used
   script-wide (e.g. `os`, `out`→`tarball_name` is good, `os`→`operating_system` is
   needless).
5. **Brevity beats completeness in comments.** One line per construct. No multi-line
   banner blocks explaining what `case ... esac` does. Large volumes of text are
   themselves mental load. If a single clause is self-evident from a renamed variable,
   don't comment it.
6. Modernise deprecated spellings when behaviour is identical: `egrep` → `grep -E`,
   `fgrep` → `grep -F`. (Comment-and-ask if a detection dance exists *because* of the
   deprecation — see rule 1.)

## Process

1. **Re-read the function from the file immediately before editing** — the user may
   have made minor edits since you last looked. Never edit from memory.
2. Go **one function at a time**. After each, offer a diff and check in before the next.
3. Replace the whole function body in a single `Edit` (cleaner than many tiny edits).
4. Run `sh -n <script>` after edits to catch syntax slips.
5. Provide a **scoped diff** to review:
   `git diff --no-color -U2 -- <file> | sed -n '/<func_name>/,/<end marker>/p'`
   (terminal previews can garble; regenerating a clean diff on request is normal).

## Explaining the "why"

When the user asks to go step by step, explain the **purpose** behind constructs, not a
line-by-line paraphrase. Group into the function's logical steps and surface the
genuinely non-obvious bits (e.g. *why* paths are rewritten for relocatability, *why* a
binary is copied behind `libexec/`). Keep it scannable; trim once the user signals the
"sweet spot" is overshot.

## Handling puzzling fragments

For an unexplained filter or magic value (the `grep -v "kak$"` case):
- **Investigate first** (grep the script, read the code path) — but don't over-dig.
  If the user says history won't help (e.g. code pasted from another dev), stop
  archaeology and reason from what the code *does*.
- **Be honest about uncertainty.** Give the 1–2 most plausible hypotheses (a deliberate
  carve-out; a likely typo — `kak$` vs `bak$` for backup files) rather than asserting a
  reason you can't verify.
- **Assess blast radius.** "On a normal install nothing matches, so it only ever
  excludes, never breaks" is the kind of framing that lets the user decide calmly.
- **Recommend keep-or-strip with reasoning**, and let the user choose. If they confirm
  it's dead/safe (e.g. typo, and `.orig` backups make it moot), remove it.

## Common transformations (reference)

```sh
# awk indentation -> sed (mind the OFS: literal + one separator)
... | awk '{print "    ",$0}'      ->  ... | sed 's/^/     /'   # 5 spaces

# egrep -> grep -E, with the regex explained
| egrep -v " skipping| 0 fonts"    ->  # drop the " skipping"/" 0 fonts" noise (| = OR)
                                       | grep -E -v " skipping| 0 fonts"

# parameter expansion, commented
${name%-bin}                       ->  exe_name=${exe_name%-bin}   # strip trailing "-bin"

# sed with % delimiter on paths (avoids escaping "/")
s%$PREFIX/%...%g                   ->  # $PREFIX before a sub-path; "%" delimiter, no "/" escaping
```

## Anti-patterns to avoid

- Multi-line comment banners restating control flow (`# this case statement decides…`).
- Commenting the obvious (`i=0   # set i to zero`).
- Renaming for the sake of it (`os` → `operating_system`).
- Silent behaviour changes justified as "cleanup".
- Editing without re-reading the current file state.
