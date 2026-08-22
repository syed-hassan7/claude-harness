# Security invariants — always on

These rules govern the agent on **every session, every surface** it actually runs on. They are **not** profile-gated, not rigor-gated, not optional, and do not depend on any phase or mode. Today that means Claude Code only — wired via the `CLAUDE.md` pointer block. The design intent is broader (this file written so it *can* be copied verbatim into another adapter's always-applied context — `AGENTS.md`, `.cursor/rules/security.mdc`, etc.), but no root `AGENTS.md` or `.cursor/` adapter actually ships in this repo yet (see README.md's intro) — don't assume Cursor/Codex enforcement exists until one does.

Mechanical backstop: `secret-guard.js` (the one hook Claude Harness v4 keeps) blocks writes matching secret patterns. Rules below are the full contract; the hook enforces the subset it can check mechanically.

*Drift canary applies to this file — see `WORKFLOW.md`'s "Drift canary" note. Exception: the Auto-Clarity carve-out already pulls security warnings out of caveman mode, and the canary must not delay or dilute a live warning — name Zarak in the same breath, never instead of the warning.*

---

## Tier 0 — Secrets (hard stop, no exceptions)

- **Never read, peek, search, or print secret-bearing files**: `.env`, `.env.*`, `*.pem`, `*.key`, `credentials*`, `secrets.*`, `.npmrc`, `.netrc`, `*.tfvars`, service-account JSON, any file matching a gitignored secret pattern.
- **Never echo, log, paste, or commit** secret contents into chat, code, commit messages, or generated docs.
- **Never stage or commit** secret files — keep them gitignored.
- Allowed: read `.env.example` / `.env.sample` templates (placeholders only, never a populated `.env`).
- Allowed: check file **existence** or gitignore status without reading contents.
- If a task genuinely requires knowing a secret's current value, ask the user to confirm it verbally — never read it from disk yourself.

## Tier 0 — Auth & data (always)

- Scope every database query to the session user — no exceptions, no "just this once for debugging."
- Return **404** (not 403) for unauthorized resource access — do not leak resource existence to unauthorized callers.
- Rate limit every auth endpoint and every public endpoint before it reaches production.
- Secrets live in environment variables — never hardcoded in source, never committed, never logged.
- Use UUIDs for user-facing resource IDs — sequential integer IDs leak enumeration information.

## Tier 0 — Web transport & session hygiene (always)

- Every `<form>` with sensitive fields must have `method="post"` — HTML defaults to GET, and a hydration failure puts field values in the URL, browser history, and server logs.
- Cookies: `SameSite=None; Secure` in production (cross-origin), `SameSite=Lax` in dev. Never `SameSite=Strict` — breaks legitimate cross-site navigation flows without adding real protection over `Lax`.
- Trust the **last** hop of `X-Forwarded-For` for security/rate-limit decisions (`[-1]`, load-balancer-appended, unforgeable) — never the first (`[0]`, client-controlled, trivially spoofed).

## Tier 0 — Agent behavior (always)

- Never mutate a user's global agent configs (`~/.claude`, `~/.cursor`, shell rc files, global git config) unless explicitly asked.
- Never install tools, plugins, or dependencies, or edit user configs, without an explicit request.
- **External verification before "done."** Run the tests, the linter, the build — read their actual output. Never self-grade completion from having written plausible-looking code.
- Match the scope of any destructive or hard-to-reverse action (force-push, `git reset --hard`, dropping data, deleting branches) to what was actually asked — never expand scope on your own initiative.

## Enforcement model

1. **Rules** (this file) — loaded into every agent's always-applied context, every session, regardless of task type.
2. **Hooks** — `secret-guard.js` mechanically blocks writes matching secret file patterns as a backstop; rules cover everything a static pattern match can't catch (reading, echoing, scope-widening, auth logic).

"Tier 0" in the headings above is a naming holdover, not an active hierarchy — no tier system in v5, one always-on invariant set, full stop.
