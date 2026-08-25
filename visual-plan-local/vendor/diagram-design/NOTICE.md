# Vendored dependency — provenance

- **Upstream**: https://github.com/cathrynlavery/diagram-design
- **Path vendored**: `skills/diagram-design/` (the self-contained skill directory only — this repo's own `docs/`, `scripts/` (repo-root CI tooling), ADRs, and plugin-marketplace config were left behind; they're maintainer packaging, not part of the skill itself)
- **Pinned commit**: `4faae6696c2953b59dee2b89ad89c688f80c3a67`
- **License**: MIT (see `LICENSE` in this directory, copied verbatim)
- **Vendored on**: 2026-08-25, by claude-harness's `visual-plan-local` skill build

This directory is an unmodified, full copy of the upstream skill at the
commit above — used as the diagram-rendering engine for `visual-plan-local`
(see `../../skills/visual-plan-local/SKILL.md`), chosen specifically because
it is a self-contained HTML/SVG generator with zero external service
dependency (unlike BuilderIO's `visual-plan`, which requires a hosted MCP
connector — see this pack's own gap analysis in
`skills/manifest.yaml`'s `visual-plan-local` entry).

**Updating this vendor:** re-clone upstream at a new commit, diff against
this directory, and replace it wholesale — do not hand-edit files inside
`diagram-design/` directly. A hand-edit here silently diverges from the
upstream quality bar this vendor exists to inherit. If a claude-harness-
specific change is genuinely needed, make it in `visual-plan-local`'s own
files (`SKILL.md`, `template.html`), not inside this vendored tree.
