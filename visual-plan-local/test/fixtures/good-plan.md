# Add rate limiting to the export endpoint

Artifact: https://claude.ai/code/artifact/example-1234

Objective: stop the export endpoint from being hammered by a single client.
Done when a client exceeding the limit gets a 429 with a Retry-After header,
verified by an integration test.

## Scope & Non-goals

In scope: per-IP rate limiting on `/api/export`. Non-goal: per-user quotas
(deferred — needs auth context this endpoint doesn't have yet).

## Decisions

- Token bucket in-process, not Redis: single-instance deployment today, no
  need for cross-instance shared state yet. Revisit if we ever scale out.

## Steps

01. Add `lib/rate-limiter.ts` — token bucket helper, pure function, no deps.
02. Wire it into `routes/export.ts` — check-and-consume before the handler
    body runs.

## Risks

- Bucket state resets on process restart, allowing a burst right after
  deploy — accepted, low blast radius for this endpoint.

## Verification

1. Run `npm test -- rate-limiter` — unit test for the bucket logic.
2. Manual: hit `/api/export` 20x in a loop, confirm the 21st returns 429.

## Open Questions

- Should the limit be configurable via env var, or hardcoded for now?
  Recommended: hardcoded — no other endpoint needs this yet, add config only
  when a second consumer needs a different limit.
