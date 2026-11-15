# Brief: produce the FINAL standalone markdown for one language tab

The online doc can no longer be edited, so the final documents (HTML, PDF, DOCX, PPTX) will be built from local markdown files. Your job: merge the v2 draft for your language with the old tab content into ONE complete, standalone markdown file.

## Inputs (read all)
- **v2 draft:** your language's `*-v2.md` in `scratchpad/deep/<lang>/v2/`. This is the new structure and new content, and it wins on any conflict.
  - Its `[MOVED: ...]` markers point at existing blocks of the old tab, by doc block id (`.3153`, `mttvddjsrgd.4167`) or by old heading name.
  - `[KEEP: ...]`, `[DELETE: ...]` and HTML comments tell you what to drop or keep.
- **Old tab as markdown:** `scratchpad/export/md-old/<Tab>.md`, converted from today's export of the online doc (current content). Resolve every marker from this file.
  - Block ids are not in it, so match by the description in the marker and the surrounding text. The marker text usually says what the block is, for example "client table", "server table" or "default-server paragraph + code".
  - If a marker's description is unclear, also look at the agent's old work files in `scratchpad/deep/<lang>/`. For example, `Java.md`, `s2-s4.md` and `configs.md` hold the old Java tab text with headings.
- `scratchpad/deep/BRIEF-LANG-V2.md`: the required section order and cases A–J.

All paths are under `/private/tmp/claude-501/-Users-kishoremooli-development-cybersecurity/21fa377a-bc06-46f9-9e49-4588545ba6c2/`.

## Output
Write `/Users/kishoremooli/development/pqc/src/<NN>-<lang>.md`. The file names are set: `03-go.md`, `04-python.md`, `05-nodejs.md`, `06-java.md`, `07-dotnet.md`.

Rules:
- GitHub-flavoured markdown. Start with one `# ` H1, the tab title: "Go", "Python", "Node.js", "Java" or ".NET".
- Every other heading is `##` or deeper. Sections follow BRIEF-LANG-V2 order:
  1. Problem statement
  2. Versions and native support
  3. Cases: what to change (A–J, with C and D the fullest)
  4. Solution and automation
  5. How to test
  6. Pitfalls and rollback
  7. Full configuration files (last)
- **No markers left.** No `[MOVED`, `[KEEP`, `[DELETE`, HTML comments or "lead:" notes. Every moved block is copied in full at its marker's position, unchanged except where the v2 draft says to edit it.
- **Nothing correct is lost.** Every old-tab block either appears in the output or was deliberately dropped by the draft as a duplicate. Configuration files from the old "Full configuration files" section are kept, with the v2 additions appended.
- **No content duplicated.** If the draft rewrote a block and also MOVEs the old version, keep one.
- **Keep links and evidence labels:** every Tested, Documented, Claimed and Unverified label, and every source link.
- **Old content that contradicts the draft:** the draft wins. Example: the old Java tab said "root cause not found" for the BCJSSE EC certificate issue; the draft has the cause and the fix.
- Plain English, short sentences. Don't add new technical claims; this is a merge, not new research.

## Checks before hand-back
Run each of these and report the results:
- `grep -cE '\[(MOVED|KEEP|DELETE)|<!--' <out>`, which must be 0.
- The heading outline: `grep -n '^#' <out>`.
- Count the fenced code blocks in the old "Full configuration files" section and in the output's. The output must be greater than or equal to the old.
- Render it once: run `docker run --rm -v <dir>:/d -w /d pandoc/core@sha256:5b8a29d9b70d5d8ca766e5d1dcfc41916b23ab79276a80527be70516110f4c1e <file> -f gfm -t html -o /tmp/x.html` and check that it exits 0.
  - Docker is at `/Applications/Docker.app/Contents/Resources/bin/docker`.
  - Add `--label run=pqc-final` to the run.

Don't use the Claude Docs tools. Don't run any other containers. Don't install anything.

## Hand-back (800 characters at most)
- Output path.
- Line count.
- Section outline (H2 only).
- Marker count (must be 0).
- Code block counts, old vs new.
- Anything you could not resolve.
