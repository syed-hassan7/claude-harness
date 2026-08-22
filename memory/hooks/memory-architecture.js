#!/usr/bin/env node
'use strict';
// PostToolUse (matcher: Read|Edit|Write) -- file-touch recall + staleness
// flagging for project-architecture notes. Fires on every Read/Edit/Write in
// a tracked repo, so this stays cheap: one watch-map.json lookup keyed by the
// touched file's repo-relative path, never a directory scan of every note's
// watch_files. Output shape verified directly against
// code.claude.com/docs/en/hooks.md: PostToolUse uses a FLAT top-level
// `additionalContext` field, unlike UserPromptSubmit/SessionStart's nested
// `hookSpecificOutput.additionalContext` -- do not nest it here.
// See memory/SPEC.md's "Project-architecture memory" section.

const fs = require('fs');
const path = require('path');
const lib = require('./_lib');

function main() {
  const input = lib.readHookInput();
  const cwd = input.cwd || process.cwd();
  const toolName = input.tool_name || '';
  const filePath = (input.tool_input || {}).file_path;
  if (!filePath || !/^(Read|Edit|Write)$/.test(toolName)) return;

  const { scope, base } = lib.resolveScope(cwd);
  if (scope !== 'project') return; // watch_files are repo-relative; nothing to match in global scope

  const root = path.dirname(base);
  const rel = path.relative(root, filePath).split(path.sep).join('/');
  if (rel.startsWith('..')) return; // touched file is outside this repo

  const watchMap = lib.readWatchMap(base);
  const noteIds = watchMap[rel];
  if (!noteIds || !noteIds.length) return;

  const archDir = path.join(base, 'architecture');
  const indexPath = path.join(archDir, 'index.md');
  const isEdit = /^(Edit|Write)$/.test(toolName);

  if (isEdit) {
    const lockPath = path.join(archDir, '.architecture.lock');
    lib.ensureDir(archDir);
    lib.withLock(lockPath, () => {
      for (const id of noteIds) {
        const notePath = path.join(archDir, 'notes', `${id}.md`);
        if (!fs.existsSync(notePath)) continue;
        let body = fs.readFileSync(notePath, 'utf8');
        if (!/^status:\s*current\s*$/m.test(body)) continue; // already stale/superseded -- no-op
        body = body.replace(/^status:\s*current\s*$/m, 'status: possibly-stale');
        const marker = `<!-- possibly-stale-since: ${lib.nowISO()} -- edited: ${rel} -->`;
        body = /## Staleness check\s*\n/.test(body)
          ? body.replace(/(## Staleness check\s*\n)/, `$1${marker}\n`)
          : body + `\n## Staleness check\n${marker}\n`;
        lib.atomicWrite(notePath, body);
        lib.flagIndexLineStale(indexPath, id);
      }
    });
    // withLock returning false (lock contended) means this cycle's flagging
    // is skipped, same "skip, don't block the edit" tradeoff memory-checkpoint.js
    // already makes -- the file's next touch will retry.
  }

  // Surface the note(s) either way (Read, or just-flagged Edit/Write) -- this
  // is the "touching a file surfaces its architecture note" behavior, done by
  // exact watch_files match, no semantic guessing.
  const blocks = [];
  for (const id of noteIds) {
    const notePath = path.join(archDir, 'notes', `${id}.md`);
    if (!fs.existsSync(notePath)) continue;
    const body = fs.readFileSync(notePath, 'utf8');
    const summary = lib.extractSection(body, 'Summary');
    if (summary) blocks.push(`- **${id}**: ${summary}`);
  }
  if (!blocks.length) return;

  process.stdout.write(
    JSON.stringify({
      additionalContext:
        '## Claude Harness -- architecture note(s) for this file\n\n' +
        blocks.join('\n') +
        "\n\n(Surfaced because this file is listed in a tracked note's watch_files -- see memory/SPEC.md.)",
    })
  );
}

try {
  main();
} catch (_) {
  // Fail open: a broken recall/staleness pass must never block the tool call --
  // PostToolUse fires after the tool already ran, same posture as memory-checkpoint.js.
}
process.exit(0);
