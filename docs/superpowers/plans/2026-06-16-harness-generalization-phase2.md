# Harness Generalization — Phase 2 (Config + Integration Toggles) Plan

> **For agentic workers:** execute task-by-task; each task ends green + committed. Behavior-preserving for clinical (all clinical values = today's; all integrations ON).

**Goal:** Lift the remaining clinical/stack literals into `profiles/clinical/profile.env`, add `profiles/clinical/integrations.env` with optional+pluggable tracker / dev-QC / CI-wait, and de-hardcode the agent templates + ship-feature skill so a GitHub-only adopter's pipeline runs with integrations off.

**Architecture:** `bin/_common.sh` sources `profile.env` (stack shape) + `integrations.env` (org tools), each with harness defaults so a missing key never breaks clinical. Lifecycle scripts use the config vars instead of literals. `lane-agents-install.sh` injects the integration values into per-lane agent copies; the agent templates + skill reference those instead of `EastAgile`/`dev.stackclinical.com`/CircleCI literals, and skip stages whose integration is disabled.

**Scope note:** NO dashboard edits in Phase 2 — the dashboard string leaks (repo for PR links, dev-site/tracker labels) move to Phase 3 with the renderer work (one restart).

---

## File Structure

**Created:**
- `profiles/clinical/profile.env` — stack shape (db scheme, api path, dirs, branches, service names)
- `profiles/clinical/integrations.env` — tracker / dev-qc / ci-wait toggles + config (clinical: all on)
- `profiles/_template/profile.env` — adopter stub (commented)
- `profiles/_template/integrations.env` — adopter stub (all integrations off)

**Modified:**
- `bin/_common.sh` — source profile.env + integrations.env; config-ize `lane_db_url`/`lane_api_base`/`lane_upload_dir`; add `harness_integration_enabled`
- `bin/lane-bootstrap.sh`, `bin/lane-integrate.sh`, `bin/lane-reset.sh`, `bin/lane-push-dev.sh` — `development`/`main` → `$INTEGRATION_BRANCH`/`$BASE_BRANCH`; `postgres` → `$DB_SERVICE`
- `bin/lane-ci-gate.sh` — `postgres` → `$DB_SERVICE`
- `bin/db-shared-up.sh` — `postgres redis adminer` → `$COMPOSE_SERVICES`; `pg_isready/exec postgres` → `$DB_SERVICE`
- `bin/lane-agents-install.sh` — inject `DEV_SITE_URL`/`TRACKER_*`/`CI_*` from `integrations.env` (not literals)
- `claude/agents/ticketer.md`, `claude/agents/dev-qc.md` — de-hardcode tracker/dev-site/CI; provider/config driven
- `claude/skills/ship-feature/SKILL.md` — conditional ticket/dev-qc/CI-wait stages; de-hardcode org refs

---

## Task 2.1 — profile.env + config-ize `_common.sh`

**Files:** Create `profiles/clinical/profile.env`; Modify `bin/_common.sh`.

- [ ] **Step 1: Create `profiles/clinical/profile.env`**
```bash
# profiles/clinical/profile.env — clinical stack shape (sourced by bin/_common.sh).
# Each value overrides the harness default; clinical's values == today's behavior.
DB_URL_SCHEME="postgresql+asyncpg"          # SQLAlchemy async driver in DATABASE_URL
API_PATH="/api/v1"                          # API mount path (health etc. live under here)
UPLOAD_SUBDIR="backend/data/uploads"        # per-lane upload dir, relative to the lane clone
BACKEND_DIR="backend"                       # backend subdir in the repo
FRONTEND_DIR="frontend"                     # frontend subdir in the repo
DB_SERVICE="postgres"                       # docker-compose service name for the DB
COMPOSE_SERVICES="postgres redis adminer"   # services db-shared-up.sh brings up
BASE_BRANCH="main"                          # PR base branch
INTEGRATION_BRANCH="development"            # integration / auto-deploy branch
BRANCH_PREFIX="feat/"                       # feature-branch prefix
```

- [ ] **Step 2: In `bin/_common.sh`, source profile.env + set defaults** — insert right after the `source "$HARNESS_ROOT/config/lanes.env"` line (line 8):
```bash

# Active profile: stack-shape config lives in profiles/<PROFILE>/profile.env.
PROFILE="${PROFILE:-clinical}"
PROFILE_DIR="${PROFILE_DIR:-$HARNESS_ROOT/profiles/$PROFILE}"
# shellcheck disable=SC1091
[ -f "$PROFILE_DIR/profile.env" ] && source "$PROFILE_DIR/profile.env"
# Harness defaults (fallback when a profile omits a key) — clinical values:
DB_URL_SCHEME="${DB_URL_SCHEME:-postgresql+asyncpg}"
API_PATH="${API_PATH:-/api/v1}"
UPLOAD_SUBDIR="${UPLOAD_SUBDIR:-backend/data/uploads}"
BACKEND_DIR="${BACKEND_DIR:-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-frontend}"
DB_SERVICE="${DB_SERVICE:-postgres}"
COMPOSE_SERVICES="${COMPOSE_SERVICES:-postgres redis adminer}"
BASE_BRANCH="${BASE_BRANCH:-main}"
INTEGRATION_BRANCH="${INTEGRATION_BRANCH:-development}"
BRANCH_PREFIX="${BRANCH_PREFIX:-feat/}"
```

- [ ] **Step 3: Remove the now-duplicate PROFILE/PROFILE_DIR from the Phase-1 block** — in the `# --- Profile seam ---` block, delete these two lines (they moved up in Step 2):
```bash
PROFILE="${PROFILE:-clinical}"
PROFILE_DIR="${PROFILE_DIR:-$HARNESS_ROOT/profiles/$PROFILE}"
```
(Keep the comment + `harness_spawn` + `run_hook`.)

- [ ] **Step 4: Config-ize the three derivations** — replace these three lines:
```bash
lane_db_url()    { echo "postgresql+asyncpg://$PG_USER:$PG_PASS@$PG_HOST:$PG_PORT/$(lane_db "$1")"; }
```
→
```bash
lane_db_url()    { echo "${DB_URL_SCHEME}://$PG_USER:$PG_PASS@$PG_HOST:$PG_PORT/$(lane_db "$1")"; }
```
and
```bash
lane_api_base()  { echo "http://localhost:$(lane_api_port "$1")/api/v1"; }
```
→
```bash
lane_api_base()  { echo "http://localhost:$(lane_api_port "$1")${API_PATH}"; }
```
and
```bash
lane_upload_dir(){ echo "$(lane_dir "$1")/backend/data/uploads"; }
```
→
```bash
lane_upload_dir(){ echo "$(lane_dir "$1")/$UPLOAD_SUBDIR"; }
```

- [ ] **Step 5: Verify (behavior-preserving)** — the seam test must still print the identical DB URL + ports:
```bash
HARNESS_ROOT=/Users/ducnguyen/clinical/harness PROFILE_DIR=/Users/ducnguyen/clinical/harness/tests/fixtures/profile bash -c 'source "$HARNESS_ROOT/bin/_common.sh"; run_hook 3 echo' | head -1
bash -n /Users/ducnguyen/clinical/harness/bin/_common.sh && echo "syntax ok"
# clinical derivations unchanged:
HARNESS_ROOT=/Users/ducnguyen/clinical/harness bash -c 'source "$HARNESS_ROOT/bin/_common.sh"; echo "$(lane_db_url 3) | $(lane_api_base 3) | $(lane_upload_dir 3)"'
```
Expected: db url ends `…/edc_clinical_l3`, api base `http://localhost:8003/api/v1`, upload `…/lane3/backend/data/uploads` — identical to before.

- [ ] **Step 6: Commit** `feat(harness): profile.env — config-ize stack shape in _common.sh`.

## Task 2.2 — config-ize branch + DB-service literals in lifecycle scripts

**Files:** `bin/lane-bootstrap.sh`, `bin/lane-integrate.sh`, `bin/lane-reset.sh`, `bin/lane-push-dev.sh`, `bin/lane-ci-gate.sh`, `bin/db-shared-up.sh`.

- [ ] **Step 1:** Replace branch literals with config vars (exact, per file):
  - `lane-bootstrap.sh`: `git -C "$DIR" checkout development` → `checkout "$INTEGRATION_BRANCH"`; `reset --hard origin/development` → `origin/$INTEGRATION_BRANCH`.
  - `lane-integrate.sh`: `checkout development` → `"$INTEGRATION_BRANCH"`; `reset --hard origin/development` → `origin/$INTEGRATION_BRANCH`; the `!= "development"` guard → `!= "$INTEGRATION_BRANCH"`; the `--continue` `== "development"` check → `== "$INTEGRATION_BRANCH"`.
  - `lane-reset.sh`: `checkout development`/`-b development origin/development`/`reset --hard origin/development` → `$INTEGRATION_BRANCH`; the `!= "development" && != "main"` guard → `!= "$INTEGRATION_BRANCH" && != "$BASE_BRANCH"`.
  - `lane-push-dev.sh`: every `development` git ref → `$INTEGRATION_BRANCH` (the `rev-parse --abbrev-ref HEAD` guard, `checkout`, `merge-base ... origin/development development`, `reset --hard origin/development`, `push origin development`, and the `log -1 ... development` line).
- [ ] **Step 2:** Replace `postgres` service literal with `$DB_SERVICE` in the `docker compose ... exec -T postgres` calls in `lane-bootstrap.sh` (createdb), `lane-ci-gate.sh` (drop/createdb), `lane-reset.sh` (drop/createdb).
- [ ] **Step 3:** `db-shared-up.sh`: `up -d postgres redis adminer` → `up -d $COMPOSE_SERVICES`; `exec -T postgres pg_isready` and `exec ... postgres psql` → `$DB_SERVICE`.
- [ ] **Step 4: Verify** — `bash -n` all six; `grep -nE 'development|origin/development' bin/lane-*.sh` shows only the new `$INTEGRATION_BRANCH` form (no bare `development` git refs); re-run the seam test (still green).
- [ ] **Step 5: Commit** `refactor(harness): config-ize branch + db-service names in lifecycle scripts`.

## Task 2.3 — integrations.env + reader

**Files:** Create `profiles/clinical/integrations.env`, `profiles/_template/integrations.env`, `profiles/_template/profile.env`; Modify `bin/_common.sh`.

- [ ] **Step 1: Create `profiles/clinical/integrations.env`** (clinical = all on, values from today's hardcoding):
```bash
# profiles/clinical/integrations.env — optional org integrations (sourced by _common.sh).
TRACKER_ENABLED=1
TRACKER_PROVIDER="eastagile"
TRACKER_URL="https://tracker.eastagile.com/east-agile/projects/e1795ce0-5234-4ec8-9ced-275e7d010275/issues/"
TRACKER_PROJECT="Stack Clinical"
TRACKER_STATUS="Started"
TRACKER_ASSIGNEE="duc.nguyen"
TRACKER_MCP="playwright-ticketer"

DEV_QC_ENABLED=1
DEV_SITE_URL="https://dev.stackclinical.com"
DEV_QC_MCP="playwright-qa-dev"

CI_WAIT_ENABLED=1
CI_PROVIDER="github-status"
CI_REPO="EastAgile/stack-clinical"
CI_DEPLOY_CONTEXT="ci/circleci: deploy-dev"
```

- [ ] **Step 2: Create `profiles/_template/integrations.env`** (adopter stub — all off):
```bash
# Enable + fill these when your project has the integration; off = the stage is skipped.
TRACKER_ENABLED=0     # 1 + TRACKER_* to file tickets after a dev push
TRACKER_PROVIDER=""   # e.g. eastagile | jira | linear | github-issues  (generate the provider agent via /harness-adapt)
TRACKER_URL=""
TRACKER_PROJECT=""
TRACKER_STATUS=""
TRACKER_ASSIGNEE=""
TRACKER_MCP=""

DEV_QC_ENABLED=0      # 1 + DEV_SITE_URL to browser-QC a deployed dev site after push
DEV_SITE_URL=""
DEV_QC_MCP=""

CI_WAIT_ENABLED=0     # 1 + CI_REPO/CI_DEPLOY_CONTEXT to wait on a deploy status before dev-QC
CI_PROVIDER="github-status"
CI_REPO=""
CI_DEPLOY_CONTEXT=""
```

- [ ] **Step 3: Create `profiles/_template/profile.env`** (adopter stub — copy of clinical's keys with neutral placeholders + comments explaining each; defaults documented).

- [ ] **Step 4: In `bin/_common.sh`, source integrations.env + add reader** — after the profile.env source block (Task 2.1 Step 2), add:
```bash
# shellcheck disable=SC1091
[ -f "$PROFILE_DIR/integrations.env" ] && source "$PROFILE_DIR/integrations.env"
# Is an integration enabled?  harness_integration_enabled tracker|dev_qc|ci_wait
harness_integration_enabled() {
  case "$1" in
    tracker) [ "${TRACKER_ENABLED:-0}" = 1 ];;
    dev_qc)  [ "${DEV_QC_ENABLED:-0}" = 1 ];;
    ci_wait) [ "${CI_WAIT_ENABLED:-0}" = 1 ];;
    *) return 1;;
  esac
}
```

- [ ] **Step 5: Verify** — `bash -n bin/_common.sh`; `bash -c 'source _common.sh; harness_integration_enabled tracker && echo on; TRACKER_ENABLED=0 source ...; ...'` confirm on for clinical; PROFILE=_template path → off. Seam test still green.
- [ ] **Step 6: Commit** `feat(harness): integrations.env (optional tracker/dev-qc/ci-wait) + reader`.

## Task 2.4 — lane-agents-install.sh injects integration values

**Files:** `bin/lane-agents-install.sh`.

- [ ] **Step 1:** Replace the hardcoded site/tracker literals in the python `blocks` with `integrations.env` values (already in env via `_common.sh`): pass `DEV_SITE_URL`, `TRACKER_URL`, `TRACKER_PROJECT`, `TRACKER_ASSIGNEE`, `CI_REPO`, `CI_DEPLOY_CONTEXT` into the python env; use `os.environ` for the `site=` args and a new tracker-context line. The dev-qc block also embeds `CI_REPO` + `CI_DEPLOY_CONTEXT` so the agent polls the right deploy status; the ticketer block embeds project/assignee.
- [ ] **Step 2:** Only inject a block when the integration is enabled AND creds exist (skip the dev-qc/ticketer block entirely when `DEV_QC_ENABLED`/`TRACKER_ENABLED` = 0).
- [ ] **Step 3: Verify** — run `bin/lane-agents-install.sh 5`; `grep -n 'dev.stackclinical.com\|tracker.eastagile.com\|EastAgile/stack-clinical' ~/clinical/lane5/.claude/agents/*.md` shows they came from config (and would be absent/blank under `_template`). `git -C ~/clinical/lane5 check-ignore .claude/agents/` confirms gitignored.
- [ ] **Step 4: Commit** `refactor(harness): per-lane agent install injects integrations.env values`.

## Task 2.5 — De-hardcode agent templates + ship-feature skill

**Files:** `claude/agents/ticketer.md`, `claude/agents/dev-qc.md`, `claude/skills/ship-feature/SKILL.md`.

- [ ] **Step 1 — ticketer.md:** Replace the hardcoded tracker URL / "East Agile" / "Stack Clinical" / "Started" / "duc.nguyen" / `playwright-ticketer` with references to the injected block ("use the tracker URL, project, status, and assignee from the credentials/config block at the top of this prompt"). Keep the East-Agile-specific login/idempotency lore under a "Provider notes (eastagile)" heading that applies when `TRACKER_PROVIDER=eastagile`. The MCP server name comes from the injected `TRACKER_MCP`.
- [ ] **Step 2 — dev-qc.md:** Replace literal `https://dev.stackclinical.com` → "your lane's dev site (from the injected config block / `DEV_SITE_URL`)"; the CircleCI `gh api repos/EastAgile/stack-clinical/.../status … context=="ci/circleci: deploy-dev"` → use injected `CI_REPO` + `CI_DEPLOY_CONTEXT`; gate the whole deploy-wait on CI-wait being enabled (if no CI context given, skip the wait and QC immediately). `playwright-qa-dev` → injected `DEV_QC_MCP`. Keep SDTM fixtures as an example, clearly marked clinical-specific.
- [ ] **Step 3 — ship-feature SKILL.md:** Source `integrations.env` in Setup; make Stage 9 (ticket), Stage 11 (dev-qc), and the Stage-11 CI deploy-wait CONDITIONAL — "Only run if `harness_integration_enabled <x>`; otherwise skip the stage and mark its dashboard node N/A." De-hardcode the Stage-9 "East Agile, Stack Clinical → Started, SC-NN" and Stage-11 "dev.stackclinical.com" references to "the configured tracker / dev site". MCP-preflight list adapts to which integrations are on.
- [ ] **Step 4: Verify (review-based):** `grep -nE 'stackclinical|eastagile|EastAgile|Stack Clinical|circleci|duc\.nguyen' claude/agents/ticketer.md claude/agents/dev-qc.md claude/skills/ship-feature/SKILL.md` — remaining hits should only be inside clearly-labeled "provider notes (eastagile)" / clinical-example sections, not load-bearing instructions. Read each changed file once for coherence.
- [ ] **Step 5: Commit** `refactor(harness): de-hardcode ticketer/dev-qc/ship-feature behind integrations config`.

## Self-Review
- Spec coverage: profile.env ✓ (2.1), config literals ✓ (2.2), integrations.env + optional/pluggable ✓ (2.3), agent param ✓ (2.4/2.5), conditional stages ✓ (2.5). Dashboard config leaks → Phase 3 (noted).
- Behavior preservation: clinical profile.env/integrations.env reproduce today's values; all defaults match; integrations all ON → clinical pipeline unchanged.
- Verification: executable tasks (2.1–2.4) have command checks; markdown (2.5) is review + grep. The clinical seam/derivation tests guard against regressions.
