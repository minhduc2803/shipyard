# Harness Generalization — Phase 3 (Dashboard de-hardcoding) Plan

> Execute task-by-task; verify the data-driven dashboard on a SCRATCH PORT before restarting the live one. Behavior-preserving for clinical.

**Goal:** Remove the dashboard's per-project coupling so the watch view works for any project: drive the PR-link repo, dev-site/tracker labels, and QA placeholder from the active profile's config, and make the dev-QC / ticket map nodes integration-aware (no permanent ⚠ when an integration is off).

**Honest scope note (descope):** the pipeline "subway map" SVG is hand-tuned geometry for the **ship-feature workflow**, not for clinical-the-project. Any adopter who keeps the ship-feature pipeline (the common case — the pipeline ships with the harness) reuses the map unchanged. Fully externalizing the node graph into `workflow.json` is therefore a *custom-workflow* feature, NOT project-generalization, and is **out of Phase 3 scope** (revisit only if an adopter needs a different pipeline shape). Phase 3 does the project-level decoupling: strings + integration awareness, both driven by `profiles/<PROFILE>/integrations.env`.

---

## Tasks

### P3.1 — Config in the payload + de-hardcode the 4 string leaks
**Files:** `dashboard/server/services/config.js`, `dashboard/src/` (rewritten from app.py to Node.js+React).
- Backend: add `PROFILE`/`PROFILE_DIR`, `loadEnvFile()`, and `harnessConfig()` returning `{profile, repo (CI_REPO), dev_site (host of DEV_SITE_URL), tracker_host (host of TRACKER_URL), integrations:{tracker,dev_qc,ci_wait}}`. Add `"config": harnessConfig()` to `lanesPayload()`.
- Frontend: read `data.config`. Replace:
  - L737 `const repo='EastAgile/stack-clinical'` → `const repo=(CFG().repo)||''`; render the PR cell as a link only when `repo` is set, else plain `#N`.
  - L944 `'this lane · dev.stackclinical.com'` → `'this lane · '+(CFG().dev_site||'dev site')`.
  - L946 `'shared · tracker.eastagile.com'` → `'shared · '+(CFG().tracker_host||'tracker')`.
  - L961 placeholder `qa-laneN@eastagile.com` → neutral `qa account email`.
- Verify on scratch port (below). Commit.

### P3.2 — Integration-aware map nodes
**Files:** `dashboard/src/components/PipelineNodes.jsx`.
- In `laneMap`, when `CFG().integrations.dev_qc` is false, render the **dev QC** node (index 9) as a dim `na` node (no ⚠ evidence, tip "dev-QC integration off"); when `integrations.tracker` is false, render the **ticket** node dim `na`. Clinical (all on) is unchanged.
- Add a `.node.na{opacity:.32}` style + dim label.
- Verify on scratch port. Commit.

### P3.3 — Scratch-port verification + restart live dashboard
- Start a SECOND dashboard on port 8099 (`DASHBOARD_PORT=8099 PROFILE=clinical`) against the same state; `curl :8099/api/lanes` shows `config.repo=EastAgile/stack-clinical`, `config.dev_site=dev.stackclinical.com`, integrations all true; `curl :8099/` returns 200 and contains the map. Also test a `_template`-profile instance (PROFILE=_template) → `config.repo=""`, integrations false (proves the generic path).
- Stop the scratch instance. Restart the live dashboard via `bin/dashboard.sh restart` so it serves the new code. Confirm `:8090/api/lanes` carries `config`.
- Merge Phase 3 to main; delete branch.

## Verify-before-done
- Clinical: dashboard renders identically (repo/labels resolve to the same East Agile values via config; all map nodes behave as today).
- `_template` profile: repo blank (PR cells are plain `#N`), dev-site/tracker labels generic, dev-QC + ticket nodes show `na`.
