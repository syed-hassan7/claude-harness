#!/usr/bin/env node
'use strict';
// UserPromptSubmit -- mechanical keyword recall for project-architecture
// notes. Fires on EVERY prompt (Claude Code docs: UserPromptSubmit has "no
// matcher support," always fires) -- must stay fast. Input field verified
// directly against code.claude.com/docs/en/hooks-guide.md: "UserPromptSubmit
// hooks get the `prompt` text." Output shape also verified there: nested
// hookSpecificOutput.additionalContext, NOT a top-level field -- Claude Code
// silently drops additionalContext placed at the top level for this event.
// See memory/SPEC.md's "Project-architecture memory" -> Recall section.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

const MAX_NOTES_INJECTED = 3; // bound how many full notes one prompt can pull in

function collect(base) {
  const idxPath = path.join(base, 'architecture', 'index.md');
  return lib.readArchIndexEntries(idxPath).map((entry) => ({ entry, base }));
}

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const promptText = input.prompt || '';
  if (!promptText.trim()) return;

  const { scope, base } = lib.resolveScope(cwd);
  const homeBase = path.join(lib.homeDir(), '.claude');

  // Global index is pooled in BOTH scopes -- a question about another
  // tracked project asked from inside this repo must still recall it (the
  // exact gap this store exists to close). Project scope also pools its own
  // repo-local index. Global scope's base already equals homeBase, so only
  // pool it once either way -- never double-collect the same file.
  const pools = scope === 'project' ? [...collect(base), ...collect(homeBase)] : collect(homeBase);

  const matched = [];
  const seen = new Set();
  for (const { entry, base: entryBase } of pools) {
    if (matched.length >= MAX_NOTES_INJECTED) break;
    if (seen.has(entry.id)) continue;
    if (!lib.architectureEntryMatches(entry, promptText)) continue;
    seen.add(entry.id);
    matched.push({ entry, base: entryBase });
  }
  if (!matched.length) return;

  const blocks = matched.map(({ entry, base: entryBase }) => {
    const notePath = path.join(entryBase, 'architecture', 'notes', `${entry.id}.md`);
    let summary = entry.summary;
    let detail = '';
    if (fs.existsSync(notePath)) {
      const body = fs.readFileSync(notePath, 'utf8');
      summary = lib.extractSection(body, 'Summary') || summary;
      detail = lib.extractSection(body, 'Detail');
    }
    const flag = entry.stale ? ' [STALE? -- verify against current code before trusting]' : '';
    const detailLine = detail ? `\n  ${detail.replace(/\n/g, '\n  ')}` : '';
    return `- **${entry.id}** (${entry.project})${flag}: ${summary}${detailLine}`;
  });

  const additionalContext =
    '## Claude Harness -- matched architecture note(s)\n\n' +
    blocks.join('\n\n') +
    '\n\n(Mechanically matched on tags/project against this message -- see memory/SPEC.md\'s "Project-architecture memory" section. Not a substitute for reading the file if it matters.)';

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'UserPromptSubmit',
        additionalContext,
      },
    })
  );
}

try {
  main();
} catch (_) {
  // Fail open: a broken recall lookup must never block the user's prompt.
}
process.exit(0);
