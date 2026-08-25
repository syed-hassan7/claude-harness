# Add rate limiting to the export endpoint

As discussed above, we're revising the earlier approach.

## Scope & Non-goals

In scope: rate limiting.

## Decisions

Unlike the previous version, this revision uses a token bucket.

## Steps

01. Add rate limiting somewhere.

## Open Questions

- Should the limit be configurable?

## Open Questions

- Should it use Redis?
