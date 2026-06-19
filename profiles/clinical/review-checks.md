# Stack-specific merge-safety / review checks — clinical

Read and applied at runtime by the **senior-gate-reviewer** (before the
`development` push) and the **pr-reviewer** (on the PR diff). This is clinical's
instantiation of the general "collisions that don't surface as git conflicts"
principle; an adopter writes their own `review-checks.md` (or leaves it empty to
rely on the agents' general principle).

- **Migration collisions** — filename-sorted SQL runner (NOT alembic):
  `backend/app/db/migrations_sql/NNN_*.sql`, tracked by name in
  `schema_migrations` (`migrate.py` supports only `upgrade`). On the merged tree,
  check for duplicate number prefixes:
  `ls <lane>/backend/app/db/migrations_sql | sed -E 's/^([0-9]+)_.*/\1/' | sort | uniq -d`
  — ANY output means two branches claimed the same `NNN` ⇒ NO-GO (renumber the
  feature's migration). Also confirm the feature's new migration number is HIGHER
  than the highest already on `origin/development`.
- **Contract drift** — `cd <lane> && make openapi-check-host` must be clean; if
  the API changed and `frontend/contracts/openapi.json` wasn't regenerated
  (`make openapi`) ⇒ NO-GO.
