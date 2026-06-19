---
name: harness-adapt
description: "Onboard the parallel feature harness to a NEW project. Invoke as /harness-adapt after cloning the harness, pointed at (or run from) the target app repo. Inspects the repo's stack, drafts a per-project profile (profiles/<name>/ — profile.env + integrations.env + the 7 lifecycle hooks) from profiles/_template using profiles/clinical as the worked reference, confirms what it can't infer, validates with harness-doctor, and dry-runs one lane. Use when a different engineer wants to run the harness against their own repo."
---

# Harness Adapt (onboard a new project)

You set up the harness for a NEW target project by writing a **profile** — the only project-specific surface. The harness engine (`bin/`, `dashboard/`) stays generic; your profile supplies the stack lifecycle + integration config. Reference: `docs/superpowers/specs/2026-06-15-harness-generalization-design.md`.

## Setup
```bash
HARNESS="@@HARNESS_ROOT@@"     # populated to the real harness path when the harness is installed
```
- Confirm the harness is cloned and `bin/install-claude-assets.sh` has been run (so skills/agents are linked).
- Identify the **target repo** (the app to build features in) and a short **profile name** (e.g. `acme`). Profiles live at `$HARNESS/profiles/<name>/`.

## Stage 0 — Inspect the target repo (autonomous)
Read the repo to infer the stack — do NOT guess; cite what you found:
- **Package managers / languages**: lockfiles + manifests (`uv.lock`/`pyproject.toml`, `package.json`+`pnpm-lock.yaml`/`package-lock.json`, `Gemfile`, `go.mod`, …).
- **Service layout**: backend/frontend dirs (or single service); the dev `docker-compose.yml` and its service names (DB, cache, etc.).
- **Run/build/test/migrate commands**: how the API starts, how the FE builds+serves, the test command, the migration command, any seed script, the health endpoint.
- **Branch model**: PR base branch + integration branch.
- **Datastore**: DB engine + driver scheme; whether there's a cache (Redis).
Use `Explore`/`general-purpose` subagents for breadth, then read key files yourself.

## Stage 1 — Scaffold the profile
```bash
cp -R "$HARNESS/profiles/_template" "$HARNESS/profiles/<name>"
```
Fill `profiles/<name>/profile.env` from Stage 0 (db scheme, api path, upload subdir, backend/frontend dirs, db service, compose services, branches, branch prefix). Keep every key the template documents.

## Stage 2 — Implement the hooks
Edit each `profiles/<name>/hooks/*.sh`, replacing the TODO stub with the real commands for this stack. The harness exports the env contract (`LANE_DIR`, `API_PORT`, `FE_PORT`, `DATABASE_URL`, `REDIS_URL`, `API_BASE`, `FE_URL`, `DB_NAME`, … + your profile.env vars); use `harness_spawn <name> <wd> <cmd…>` inside `boot.sh` to background services. **Read `profiles/clinical/hooks/*.sh` as the worked example for each hook.** Hooks: `bootstrap` (deps), `migrate`, `seed`, `boot` (build+start), `health` (readiness, exit 0 when up), `ci-gate` (lint/test/contract — uses `TEST_DATABASE_URL`), `e2e` (under the e2e lock).

## Stage 3 — Integrations (ask the human, default off)
Set `profiles/<name>/integrations.env`. Ask which the project has:
- **Tracker** (file tickets)? If yes: provider, URL, project, status, assignee, and the MCP server name. (Only `eastagile` ships as a worked example — see `profiles/clinical/tracker-notes.md`; for Jira/Linear/GitHub-Issues, write your profile's `tracker-notes.md`.)
- **Dev-site QC**? If yes: `DEV_SITE_URL` + the dev-QC MCP server name.
- **CI deploy-wait**? If yes: `CI_REPO` + `CI_DEPLOY_CONTEXT` (a GitHub commit-status context).
Leave any the project lacks at `*_ENABLED=0` — the harness simply skips those pipeline stages.
Register the MCP servers you named in the source project (`.mcp.json` / `~/.claude.json`), since the agents call them by name.

## Stage 4 — Validate
```bash
"$HARNESS/bin/harness-doctor.sh" <name>
```
Fix every ✗ (unimplemented hooks, missing config) until it reports `0 error(s)`. Address ⚠ warnings too where they apply.

## Stage 5 — Point the harness at the profile + dry-run one lane
- Set the active profile: in `$HARNESS/config/lanes.env` (or via env) set `PROFILE=<name>`, `SOURCE_REPO=<target repo path>`, `DB_PREFIX`, and ports if 3000/8000 clash. Set `config/secrets.env` (LLM keys, seed account, any integration creds).
- Bring up shared infra + one lane:
  ```bash
  "$HARNESS/bin/db-shared-up.sh"
  "$HARNESS/bin/lane-bootstrap.sh" 1
  "$HARNESS/bin/lane-up.sh" 1
  ```
  Confirm `lane 1 live`, then `"$HARNESS/bin/lane-ci-gate.sh" 1` green. Fix hooks and re-run until the lane boots + gates pass.
- Start the dashboard: `"$HARNESS/bin/dashboard.sh" start` → http://127.0.0.1:8090.

## Done
Report: the profile path, what each hook runs, which integrations are on, and the dry-run result. The adopter can now `/ship-feature <requirement>` in a lane. Keep `profiles/clinical/` as the reference; never put another project's specifics in `bin/` or `dashboard/`.
