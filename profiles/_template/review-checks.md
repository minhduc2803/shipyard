# Stack-specific merge-safety / review checks — <your project>

Read at runtime by the senior-gate-reviewer + pr-reviewer. Describe the
collision classes that merge CLEANLY but break your stack — and the exact command
to detect each. Leave this file empty to rely on the agents' general principle
(they'll inspect the merged tree themselves).

Common classes to cover (delete what doesn't apply, add what does):
- **Migration collisions** — how your migration tool numbers/orders migrations,
  and the command to detect two branches claiming the same id.
- **Contract/schema drift** — the command that fails if a generated API contract
  (OpenAPI/GraphQL/protobuf) wasn't regenerated after an API change.
- **Lockfile / fixture / test-id collisions** — anything else that two clean
  branches can duplicate.

Worked example: `profiles/clinical/review-checks.md`.
