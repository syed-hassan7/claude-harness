Audit, fix, and permanently verify claude-harness's reliability — not just in
this session, but for every new and existing session on every project that
installs it.

Before starting, read (in this repo):
- `audit-log/2026-08-27-external-audit.md` — the original 27-finding audit.
- `audit-log/2026-08-27-reliability-overhaul-prompt.md` — the full brief:
  thesis, gap inventory, methodology, web-research questions, deliverables.

Follow that brief's methodology strictly — empirical proof over read-and-
reasoned, adversarial tests that try to break each gate, a self-check
mechanism demonstrated RED against a deliberately-broken install before any
GREEN from it is trusted. Treat its gap list as a floor, not a ceiling:
research further, explore beyond it, use your own judgment anywhere it
doesn't cover something. Call `advisor()` before committing to an approach
and again before declaring done. Human approval gate before any commit or
push — no exceptions for scale.
