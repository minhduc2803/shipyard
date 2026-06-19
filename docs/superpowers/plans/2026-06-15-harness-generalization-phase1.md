# Harness Generalization — Phase 1 (Stack-Adapter Seam) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a per-project "profile" seam so the lane lifecycle's stack-specific commands live in `profiles/clinical/hooks/`, and the `bin/` scripts become a generic engine — with clinical behavior **exactly preserved**.

**Architecture:** Add two helpers to `bin/_common.sh` — `run_hook <N> <name>` (exports a fixed env contract, then runs `profiles/$PROFILE/hooks/<name>.sh`) and `harness_spawn <name> <wd> <cmd…>` (the detached-stdio background-spawn pattern, exported to hooks). Move the clinical `uv`/`celery`/`pnpm`/`make`/`pytest`/`playwright` command lines verbatim into hooks. Thin `lane-up`, `lane-bootstrap`, `lane-ci-gate`, `lane-e2e`, `lane-integrate`, `lane-reset` to call `run_hook`. Datastore (DB create/drop) stays harness-side.

**Tech Stack:** Bash (the harness engine), the clinical stack commands (uv/uvicorn/celery, pnpm/Next standalone, Postgres-in-compose, Playwright). No new dependencies.

**Reference spec:** `docs/superpowers/specs/2026-06-15-harness-generalization-design.md` (§3 architecture, §4 hook contract, §8 migration).

**Hard constraints:**
- Clinical's 8 running lanes must not be disturbed. The lifecycle scripts are per-invocation, so editing them only takes effect on the next `lane-up`/`lane-bootstrap`. Do NOT run destructive verifications (Tasks 2–6) against a lane that has active work — use a free/scratch lane.
- Commit trailer for this work: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Branch: `harness-generalization` (already checked out).

---

## File Structure

**Created:**
- `profiles/clinical/hooks/bootstrap.sh` — install backend + frontend deps
- `profiles/clinical/hooks/migrate.sh` — apply DB migrations
- `profiles/clinical/hooks/seed.sh` — seed initial user/org
- `profiles/clinical/hooks/boot.sh` — build + start api/worker/fe via `harness_spawn`
- `profiles/clinical/hooks/health.sh` — API + FE readiness probe
- `profiles/clinical/hooks/ci-gate.sh` — openapi-check + pytest + build:check
- `profiles/clinical/hooks/e2e.sh` — Playwright e2e (LOCAL_EXEC contract)
- `tests/fixtures/profile/hooks/echo.sh` — seam unit-test fixture (permanent)

**Modified:**
- `bin/_common.sh` — add `PROFILE`/`PROFILE_DIR`, `harness_spawn`, `run_hook`
- `config/lanes.env` — add `PROFILE` selector
- `bin/lane-up.sh` — boot + health via hooks
- `bin/lane-bootstrap.sh` — deps/migrate/seed via hooks (createdb stays)
- `bin/lane-ci-gate.sh` — gates via hook (test-DB lifecycle stays)
- `bin/lane-e2e.sh` — e2e via hook
- `bin/lane-integrate.sh` — migrate via hook
- `bin/lane-reset.sh` — migrate/seed via hooks (dropdb/createdb stays)

**Contract reminder (env `run_hook` exports to every hook):**
`LANE LANE_DIR API_PORT FE_PORT DATABASE_URL REDIS_URL UPLOAD_DIR DB_NAME API_BASE FE_URL RUN_DIR LOG_DIR PROFILE PROFILE_DIR SOURCE_REPO HARNESS_ROOT WORKER_QUEUES COMPOSE_FILE PG_HOST PG_PORT PG_USER PG_PASS REDIS_HOST REDIS_PORT DB_PREFIX SEED_USER_EMAIL SEED_USER_PASSWORD` plus exported functions `harness_spawn`, `die`. (`API_BASE` = `http://localhost:<API_PORT>/api/v1`.) The `ci-gate` hook additionally receives `TEST_DATABASE_URL`.

---

## Task 1: Profile seam in `_common.sh` + config + unit test

**Files:**
- Modify: `bin/_common.sh` (insert after line 40, `lane_log_dir()`)
- Modify: `config/lanes.env` (insert after line 7, `ORIGIN_URL`)
- Create: `tests/fixtures/profile/hooks/echo.sh`

- [ ] **Step 1: Write the failing test fixture + test command**

Create `tests/fixtures/profile/hooks/echo.sh`:

```bash
#!/usr/bin/env bash
# Seam unit-test fixture: prove run_hook exports the contract + functions.
set -euo pipefail
echo "HOOK_OK lane=$LANE dir=$LANE_DIR api=$API_PORT fe=$FE_PORT db=$DATABASE_URL profile_dir=$PROFILE_DIR"
type harness_spawn >/dev/null 2>&1 && echo "SPAWN_FN_OK"
type die >/dev/null 2>&1 && echo "DIE_FN_OK"
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
chmod +x /Users/ducnguyen/clinical/harness/tests/fixtures/profile/hooks/echo.sh
HARNESS_ROOT=/Users/ducnguyen/clinical/harness \
PROFILE_DIR=/Users/ducnguyen/clinical/harness/tests/fixtures/profile \
bash -c 'source "$HARNESS_ROOT/bin/_common.sh"; run_hook 3 echo'
```
Expected: FAIL with `run_hook: command not found` (helper doesn't exist yet).

- [ ] **Step 3: Add the seam to `bin/_common.sh`**

Insert immediately after the `lane_log_dir()` line (line 40):

```bash

# --- Profile seam ---------------------------------------------------------
# The active profile supplies the stack-specific lifecycle hooks; the harness
# stays generic and calls them via run_hook with a documented env contract.
PROFILE="${PROFILE:-clinical}"
PROFILE_DIR="${PROFILE_DIR:-$HARNESS_ROOT/profiles/$PROFILE}"

# Background a long-lived service with FULLY detached stdio + record its pid/log
# where lane-down.sh / lane-status.sh look. The detachment MUST stay (it is the
# fix for the 2026-06-11 stage-4 stalls: an attached child holds the caller's
# stdout pipe open and `... | tail` never sees EOF). Use inside a boot hook:
#   harness_spawn <name> <workdir> <cmd> [args...]
harness_spawn() {
  local name="$1" wd="$2"; shift 2
  ( cd "$wd" || exit 1
    nohup "$@" >"$LOG_DIR/$name.log" 2>&1 </dev/null &
    echo $! >"$RUN_DIR/$name.pid"
  ) </dev/null >/dev/null 2>&1
}

# Run a profile hook for lane N with the stable env contract exported.
#   run_hook <N> <hook-name> [args...]
run_hook() {
  local n="$1" name="$2"; shift 2
  require_lane "$n"
  local hook="$PROFILE_DIR/hooks/$name.sh"
  [ -f "$hook" ] || die "profile '$PROFILE' ($PROFILE_DIR) has no hook '$name.sh'"
  export LANE="$n" LANE_DIR="$(lane_dir "$n")"
  export API_PORT="$(lane_api_port "$n")" FE_PORT="$(lane_fe_port "$n")"
  export DATABASE_URL="$(lane_db_url "$n")" REDIS_URL="$(lane_redis_url "$n")"
  export UPLOAD_DIR="$(lane_upload_dir "$n")" DB_NAME="$(lane_db "$n")"
  export API_BASE="$(lane_api_base "$n")" FE_URL="$(lane_fe_url "$n")"
  export RUN_DIR="$(lane_run_dir "$n")" LOG_DIR="$(lane_log_dir "$n")"
  export PROFILE PROFILE_DIR SOURCE_REPO HARNESS_ROOT
  export WORKER_QUEUES COMPOSE_FILE PG_HOST PG_PORT PG_USER PG_PASS \
         REDIS_HOST REDIS_PORT DB_PREFIX SEED_USER_EMAIL SEED_USER_PASSWORD
  export -f harness_spawn die
  bash "$hook" "$@"
}
```

- [ ] **Step 4: Add the `PROFILE` selector to `config/lanes.env`**

Insert after the `ORIGIN_URL` line (line 7):

```bash
PROFILE="${PROFILE:-clinical}"          # active profile: profiles/<PROFILE>/ (stack hooks + config)
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
HARNESS_ROOT=/Users/ducnguyen/clinical/harness \
PROFILE_DIR=/Users/ducnguyen/clinical/harness/tests/fixtures/profile \
bash -c 'source "$HARNESS_ROOT/bin/_common.sh"; run_hook 3 echo'
```
Expected (PASS): output contains
```
HOOK_OK lane=3 dir=/Users/ducnguyen/clinical/lane3 api=8003 fe=3003 db=postgresql+asyncpg://...edc_clinical_l3 profile_dir=/Users/ducnguyen/clinical/harness/tests/fixtures/profile
SPAWN_FN_OK
DIE_FN_OK
```
Also syntax-check the edited file:
```bash
bash -n /Users/ducnguyen/clinical/harness/bin/_common.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 6: Commit**

```bash
git -C /Users/ducnguyen/clinical/harness add bin/_common.sh config/lanes.env tests/fixtures/profile/hooks/echo.sh
git -C /Users/ducnguyen/clinical/harness commit -m "feat(harness): add profile seam (run_hook + harness_spawn) to the engine" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Bootstrap / migrate / seed hooks + thin `lane-bootstrap` & `lane-reset`

**Files:**
- Create: `profiles/clinical/hooks/bootstrap.sh`, `migrate.sh`, `seed.sh`
- Modify: `bin/lane-bootstrap.sh` (lines 40–44, 52–54, 56–59)
- Modify: `bin/lane-reset.sh` (lines 36–38)

- [ ] **Step 1: Create the three hooks (clinical commands, verbatim)**

`profiles/clinical/hooks/bootstrap.sh`:
```bash
#!/usr/bin/env bash
# Install backend (uv) + frontend (pnpm) deps for a clinical lane.
set -euo pipefail
echo "harness: backend deps (uv sync) ..."
( cd "$LANE_DIR/backend" && uv sync --extra dev )
echo "harness: frontend deps (pnpm install) ..."
( cd "$LANE_DIR/frontend" && pnpm install --frozen-lockfile )
```

`profiles/clinical/hooks/migrate.sh`:
```bash
#!/usr/bin/env bash
# Apply DB migrations to the lane DB. DATABASE_URL is exported by run_hook.
set -euo pipefail
( cd "$LANE_DIR/backend" && uv run python -m app.db.migrate upgrade )
```

`profiles/clinical/hooks/seed.sh`:
```bash
#!/usr/bin/env bash
# Seed the initial user/org. DATABASE_URL + SEED_USER_* exported by run_hook.
set -euo pipefail
( cd "$LANE_DIR/backend" && uv run bash scripts/init_user.sh )
```

- [ ] **Step 2: Make them executable + syntax-check**

Run:
```bash
chmod +x /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/{bootstrap,migrate,seed}.sh
for h in bootstrap migrate seed; do bash -n /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/$h.sh; done && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 3: Thin `bin/lane-bootstrap.sh`**

Replace the deps block (lines 40–44):
```bash
echo "harness: backend deps (uv sync) ..."
( cd "$DIR/backend" && uv sync --extra dev )

echo "harness: frontend deps (pnpm install) ..."
( cd "$DIR/frontend" && pnpm install --frozen-lockfile )
```
with:
```bash
echo "harness: installing deps (profile hook) ..."
run_hook "$N" bootstrap
```

Replace the migrate block (lines 52–54):
```bash
pstate migrating
echo "harness: migrating $(lane_db "$N") ..."
( cd "$DIR/backend" && DATABASE_URL="$(lane_db_url "$N")" uv run python -m app.db.migrate upgrade )
```
with:
```bash
pstate migrating
echo "harness: migrating $(lane_db "$N") (profile hook) ..."
run_hook "$N" migrate
```

Replace the seed block (lines 56–59):
```bash
pstate seeding-user
echo "harness: seeding user $SEED_USER_EMAIL ..."
( cd "$DIR/backend" && DATABASE_URL="$(lane_db_url "$N")" SEED_USER_PASSWORD="$SEED_USER_PASSWORD" \
    uv run bash scripts/init_user.sh )
```
with:
```bash
pstate seeding-user
echo "harness: seeding user $SEED_USER_EMAIL (profile hook) ..."
run_hook "$N" seed
```

(Leave the createdb block at lines 46–50 unchanged — datastore stays harness-side.)

- [ ] **Step 4: Thin `bin/lane-reset.sh`**

Replace the migrate+seed lines (36–38):
```bash
  ( cd "$DIR/backend" && DATABASE_URL="$(lane_db_url "$N")" uv run python -m app.db.migrate upgrade )
  ( cd "$DIR/backend" && DATABASE_URL="$(lane_db_url "$N")" SEED_USER_PASSWORD="$SEED_USER_PASSWORD" \
      uv run bash scripts/init_user.sh )
```
with:
```bash
  run_hook "$N" migrate
  run_hook "$N" seed
```
(Leave the dropdb/createdb at lines 34–35 unchanged.)

- [ ] **Step 5: Syntax-check both thinned scripts**

Run:
```bash
bash -n /Users/ducnguyen/clinical/harness/bin/lane-bootstrap.sh && bash -n /Users/ducnguyen/clinical/harness/bin/lane-reset.sh && echo "syntax ok"
```
Expected: `syntax ok`. (Full execution is verified in Task 6.)

- [ ] **Step 6: Commit**

```bash
git -C /Users/ducnguyen/clinical/harness add profiles/clinical/hooks/bootstrap.sh profiles/clinical/hooks/migrate.sh profiles/clinical/hooks/seed.sh bin/lane-bootstrap.sh bin/lane-reset.sh
git -C /Users/ducnguyen/clinical/harness commit -m "refactor(harness): bootstrap/migrate/seed via clinical profile hooks" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Boot + health hooks + thin `lane-up`

**Files:**
- Create: `profiles/clinical/hooks/boot.sh`, `health.sh`
- Modify: `bin/lane-up.sh` (replace whole file)

- [ ] **Step 1: Create `profiles/clinical/hooks/boot.sh`**

```bash
#!/usr/bin/env bash
# Boot the clinical stack for a lane: uvicorn API + Celery worker + Next
# standalone FE. Uses harness_spawn (detached) so callers never hang on a pipe.
# Arg: --no-build reuses the existing FE build. Env contract from run_hook.
set -euo pipefail
BUILD=1; [ "${1:-}" == "--no-build" ] && BUILD=0
BACKEND="$LANE_DIR/backend"; FRONTEND="$LANE_DIR/frontend"
export AWS_EC2_METADATA_DISABLED=true

echo "harness: starting API on :$API_PORT ..."
harness_spawn api "$BACKEND" uv run uvicorn app.main:app --host 0.0.0.0 --port "$API_PORT"

echo "harness: starting worker ..."
harness_spawn worker "$BACKEND" uv run celery -A app.workers.celery_app:celery worker \
  --loglevel=info --concurrency=2 -Q "$WORKER_QUEUES"

export NEXT_PUBLIC_API_BASE_URL="$API_BASE"
export NEXT_TELEMETRY_DISABLED=1
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
if [ "$BUILD" == 1 ]; then
  echo "harness: building FE (under build lock) ..."
  "$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$FRONTEND' && \
    NEXT_PUBLIC_API_BASE_URL='$NEXT_PUBLIC_API_BASE_URL' pnpm build && \
    rm -rf .next/standalone/.next/static && mkdir -p .next/standalone/.next && \
    cp -R .next/static .next/standalone/.next/static && \
    { [ -d public ] && { rm -rf .next/standalone/public; cp -R public .next/standalone/public; } || true; }"
fi
echo "harness: starting FE on :$FE_PORT ..."
export PORT="$FE_PORT" HOSTNAME=0.0.0.0
harness_spawn fe "$FRONTEND" node .next/standalone/server.js
```

- [ ] **Step 2: Create `profiles/clinical/hooks/health.sh`**

```bash
#!/usr/bin/env bash
# Readiness probe for a booted clinical lane. exit 0 only if API and FE are up.
# curl handles retry/backoff internally (no shell sleep); --max-time bounds each
# attempt so a wedged-but-listening server can't hang the probe forever.
set -euo pipefail
ok=0
echo "harness: waiting for API health ($API_BASE/health) ..."
curl -fsS --retry 60 --retry-delay 2 --retry-all-errors --retry-connrefused --max-time 5 \
  "$API_BASE/health" >/dev/null 2>&1 && echo "harness: API ok" || { echo "harness: API NOT healthy" >&2; ok=1; }
echo "harness: waiting for FE ($FE_URL/login) ..."
curl -fsS --retry 40 --retry-delay 2 --retry-all-errors --retry-connrefused --max-time 5 \
  "$FE_URL/login" >/dev/null 2>&1 && echo "harness: FE ok" || { echo "harness: FE NOT healthy" >&2; ok=1; }
exit "$ok"
```

- [ ] **Step 3: Replace `bin/lane-up.sh` entirely**

```bash
#!/usr/bin/env bash
# Boot a lane's stack via the active profile's boot + health hooks.
#   lane-up.sh <N> [--no-build]   # --no-build reuses the existing FE build
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
require_lane "${1:-}"
N="$1"; BUILD=1; [ "${2:-}" == "--no-build" ] && BUILD=0
DIR="$(lane_dir "$N")"
[ -d "$DIR/.git" ] || die "lane $N not bootstrapped (run: lane-bootstrap.sh $N)"

# Defensive: stop any existing stack first so a re-run (e.g. dashboard ▶ up on a
# live lane) can't double-start services / fight over the lane's ports.
"$HARNESS_ROOT/bin/lane-down.sh" "$N" >/dev/null 2>&1 || true

mkdir -p "$(lane_run_dir "$N")" "$(lane_log_dir "$N")" "$(lane_upload_dir "$N")"
API_PORT="$(lane_api_port "$N")"; FE_PORT="$(lane_fe_port "$N")"

# Ensure backend/.env exists (seeded from the source repo's real .env, with the
# per-lane DATABASE_URL/REDIS_URL/UPLOAD_DIR written INTO the file).
"$HARNESS_ROOT/bin/lane-env-seed.sh" "$N" || echo "harness: WARNING — .env seed failed; run bin/lane-env-seed.sh $N"

"$HARNESS_ROOT/bin/state.sh" "$N" set stage=booting status=running
hb_start "$N"; trap hb_stop EXIT   # build may wait on the build-lock + compile

echo "harness: booting lane $N stack (profile: $PROFILE) ..."
if [ "$BUILD" == 1 ]; then run_hook "$N" boot; else run_hook "$N" boot --no-build; fi

if run_hook "$N" health; then
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=live status=running notes="api=:$API_PORT fe=:$FE_PORT"
  echo "harness: lane $N live -> $(lane_fe_url "$N")"
else
  "$HARNESS_ROOT/bin/state.sh" "$N" set stage=boot-failed status=failed \
    notes="health check failed; see logs/lane$N"
  die "lane $N failed to become healthy"
fi
```

- [ ] **Step 4: Make hooks executable + syntax-check**

Run:
```bash
chmod +x /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/{boot,health}.sh
bash -n /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/boot.sh && \
bash -n /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/health.sh && \
bash -n /Users/ducnguyen/clinical/harness/bin/lane-up.sh && echo "syntax ok"
```
Expected: `syntax ok`. (Real boot verified in Task 6.)

- [ ] **Step 5: Commit**

```bash
git -C /Users/ducnguyen/clinical/harness add profiles/clinical/hooks/boot.sh profiles/clinical/hooks/health.sh bin/lane-up.sh
git -C /Users/ducnguyen/clinical/harness commit -m "refactor(harness): boot + health via clinical profile hooks" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: CI-gate hook + thin `lane-ci-gate`

**Files:**
- Create: `profiles/clinical/hooks/ci-gate.sh`
- Modify: `bin/lane-ci-gate.sh` (lines 17–27)

- [ ] **Step 1: Create `profiles/clinical/hooks/ci-gate.sh`**

```bash
#!/usr/bin/env bash
# Pre-push CI gates for a clinical lane: openapi-check + backend pytest +
# frontend build:check. The engine provides an isolated TEST_DATABASE_URL so
# pytest never touches the lane's working DB.
set -euo pipefail
echo "harness: [gate 1/3] openapi-check (contract drift) ..."
( cd "$LANE_DIR" && make openapi-check-host )
echo "harness: [gate 2/3] backend pytest ..."
( cd "$LANE_DIR/backend" && DATABASE_URL="$TEST_DATABASE_URL" REDIS_URL="$REDIS_URL" \
    uv run pytest app/tests --ignore=app/tests/integration -q )
echo "harness: [gate 3/3] frontend build:check (eslint + build) ..."
"$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$LANE_DIR/frontend' && pnpm build:check"
```

- [ ] **Step 2: Thin `bin/lane-ci-gate.sh`**

Replace the three-gate block (lines 17–27):
```bash
echo "harness: [gate 1/3] openapi-check (contract drift) ..."
( cd "$DIR" && make openapi-check-host )

echo "harness: [gate 2/3] backend pytest (fresh $TEST_DB) ..."
docker compose -f "$COMPOSE_FILE" exec -T postgres dropdb --if-exists -U "$PG_USER" "$TEST_DB" >/dev/null
docker compose -f "$COMPOSE_FILE" exec -T postgres createdb -U "$PG_USER" "$TEST_DB" >/dev/null
( cd "$DIR/backend" && DATABASE_URL="$TEST_DB_URL" REDIS_URL="$(lane_redis_url "$N")" \
    uv run pytest app/tests --ignore=app/tests/integration -q )

echo "harness: [gate 3/3] frontend build:check (eslint + build) ..."
"$HARNESS_ROOT/bin/with-lock.sh" build -- bash -c "cd '$DIR/frontend' && pnpm build:check"
```
with:
```bash
echo "harness: recreating isolated test DB $TEST_DB ..."
docker compose -f "$COMPOSE_FILE" exec -T postgres dropdb --if-exists -U "$PG_USER" "$TEST_DB" >/dev/null
docker compose -f "$COMPOSE_FILE" exec -T postgres createdb -U "$PG_USER" "$TEST_DB" >/dev/null

echo "harness: running CI gates (profile hook) ..."
export TEST_DATABASE_URL="$TEST_DB_URL"
run_hook "$N" ci-gate
```

- [ ] **Step 3: Make hook executable + syntax-check**

Run:
```bash
chmod +x /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/ci-gate.sh
bash -n /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/ci-gate.sh && \
bash -n /Users/ducnguyen/clinical/harness/bin/lane-ci-gate.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 4: Commit**

```bash
git -C /Users/ducnguyen/clinical/harness add profiles/clinical/hooks/ci-gate.sh bin/lane-ci-gate.sh
git -C /Users/ducnguyen/clinical/harness commit -m "refactor(harness): CI gates via clinical profile hook" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: e2e hook + thin `lane-e2e` & `lane-integrate`

**Files:**
- Create: `profiles/clinical/hooks/e2e.sh`
- Modify: `bin/lane-e2e.sh` (lines 14–31)
- Modify: `bin/lane-integrate.sh` (line 64)

- [ ] **Step 1: Create `profiles/clinical/hooks/e2e.sh`**

```bash
#!/usr/bin/env bash
# Playwright e2e for a clinical lane against its RUNNING integrated stack.
# The lane runs API/FE as HOST processes (no per-lane api container), so we drive
# the fixture in LOCAL_EXEC mode: seed on the host + talk to the lane DB directly.
# JWT_SECRET must match the running lane API (lane-up wrote it to backend/.env).
set -euo pipefail
LANE_JWT="$(grep -E '^JWT_SECRET=' "$LANE_DIR/backend/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ -n "$LANE_JWT" ] || { echo "e2e: JWT_SECRET not found in $LANE_DIR/backend/.env (stack booted?)" >&2; exit 1; }
"$HARNESS_ROOT/bin/with-lock.sh" e2e -- bash -c "cd '$LANE_DIR/frontend' && \
  E2E_NO_WEBSERVER=1 \
  E2E_LOCAL_EXEC=1 \
  E2E_API_BASE_URL='$API_BASE' \
  E2E_FRONTEND_URL='$FE_URL' \
  E2E_DB_HOST='$PG_HOST' E2E_DB_PORT='$PG_PORT' E2E_DB_USER='$PG_USER' \
  E2E_DB_PASSWORD='$PG_PASS' E2E_DB_NAME='$DB_NAME' \
  E2E_JWT_SECRET='$LANE_JWT' \
  DATABASE_URL='$DATABASE_URL' \
  pnpm exec playwright test --reporter=line"
```

- [ ] **Step 2: Thin `bin/lane-e2e.sh`**

Replace lines 14–31 (the comment block + JWT extraction + with-lock e2e run):
```bash
# The lane runs its API/frontend as HOST processes against the shared Postgres
# (there is no per-lane api container), so the e2e fixture's default user-seeding
# path (`docker exec backend-test-api-test-1 manage_user.py`) can't work here.
# Drive it in LOCAL_EXEC mode: seed on the host (`uv run manage_user.py` with the
# lane DATABASE_URL) and talk to the lane DB directly via psql. JWT_SECRET must
# match the running lane API (lane-up writes it to the lane's backend/.env).
LANE_JWT="$(grep -E '^JWT_SECRET=' "$DIR/backend/.env" 2>/dev/null | head -1 | cut -d= -f2-)"
[ -n "$LANE_JWT" ] || die "lane $N: JWT_SECRET not found in $DIR/backend/.env (stack booted?)"
"$HARNESS_ROOT/bin/with-lock.sh" e2e -- bash -c "cd '$DIR/frontend' && \
  E2E_NO_WEBSERVER=1 \
  E2E_LOCAL_EXEC=1 \
  E2E_API_BASE_URL='$(lane_api_base "$N")' \
  E2E_FRONTEND_URL='$(lane_fe_url "$N")' \
  E2E_DB_HOST='$PG_HOST' E2E_DB_PORT='$PG_PORT' E2E_DB_USER='$PG_USER' \
  E2E_DB_PASSWORD='$PG_PASS' E2E_DB_NAME='$(lane_db "$N")' \
  E2E_JWT_SECRET='$LANE_JWT' \
  DATABASE_URL='$(lane_db_url "$N")' \
  pnpm exec playwright test --reporter=line"
```
with:
```bash
echo "harness: running e2e (profile hook) ..."
run_hook "$N" e2e
```

- [ ] **Step 3: Thin `bin/lane-integrate.sh`**

Replace the migrate line (64):
```bash
( cd "$DIR/backend" && DATABASE_URL="$(lane_db_url "$N")" uv run python -m app.db.migrate upgrade )
```
with:
```bash
run_hook "$N" migrate
```

- [ ] **Step 4: Make hook executable + syntax-check**

Run:
```bash
chmod +x /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/e2e.sh
bash -n /Users/ducnguyen/clinical/harness/profiles/clinical/hooks/e2e.sh && \
bash -n /Users/ducnguyen/clinical/harness/bin/lane-e2e.sh && \
bash -n /Users/ducnguyen/clinical/harness/bin/lane-integrate.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/ducnguyen/clinical/harness add profiles/clinical/hooks/e2e.sh bin/lane-e2e.sh bin/lane-integrate.sh
git -C /Users/ducnguyen/clinical/harness commit -m "refactor(harness): e2e + integrate-migrate via clinical profile hooks" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: End-to-end verification on a scratch lane

**Goal:** Prove the thinned engine + clinical hooks reproduce real behavior. **Use a FREE lane** (not one with active work). Pick a number `S` not listed by `bin/lane-status.sh`. If all 9 are busy, coordinate with the user to free one or defer this task until a lane is idle.

- [ ] **Step 1: Pick a free lane number**

Run:
```bash
/Users/ducnguyen/clinical/harness/bin/lane-status.sh
```
Choose an `S` (1–9) that is absent or idle. Export it for the steps below:
```bash
export S=<free-number>
```

- [ ] **Step 2: Bootstrap the scratch lane (exercises bootstrap/migrate/seed hooks)**

Run:
```bash
/Users/ducnguyen/clinical/harness/bin/lane-bootstrap.sh "$S"
```
Expected: completes through "lane $S bootstrapped at ..." with the new log lines `installing deps (profile hook)`, `migrating ... (profile hook)`, `seeding user ... (profile hook)`. No errors.

- [ ] **Step 3: Boot the scratch lane (exercises boot + health hooks + harness_spawn)**

Run:
```bash
/Users/ducnguyen/clinical/harness/bin/lane-up.sh "$S"
```
Expected: ends with `lane $S live -> http://localhost:300$S`. Confirm pids + state:
```bash
ls /Users/ducnguyen/clinical/harness/run/lane$S/   # api.pid worker.pid fe.pid
/Users/ducnguyen/clinical/harness/bin/state.sh "$S" get stage   # -> live
curl -fsS "http://localhost:800$S/api/v1/health" >/dev/null && echo "API OK"
```
Expected: three pid files, `live`, `API OK`. **This is the critical check** — it proves `harness_spawn`'s detachment still works (the command returns; nothing hangs).

- [ ] **Step 4: Run the CI gate (exercises ci-gate hook + TEST_DATABASE_URL)**

Run:
```bash
/Users/ducnguyen/clinical/harness/bin/lane-ci-gate.sh "$S"
```
Expected: `lane $S — pre-push CI gates GREEN.` (gates 1/3, 2/3, 3/3 all pass).

- [ ] **Step 5: (Optional) e2e** — only if you have a feature/dev tree that supports it

Run:
```bash
MOCK_AGENT=true RATE_LIMIT_ENABLED=false /Users/ducnguyen/clinical/harness/bin/lane-up.sh "$S"
/Users/ducnguyen/clinical/harness/bin/lane-e2e.sh "$S"
```
Expected: `lane $S — e2e passed.`

- [ ] **Step 6: Tear down the scratch lane**

Run:
```bash
/Users/ducnguyen/clinical/harness/bin/lane-down.sh "$S"
```
If the lane was created solely for this test, remove it: `bin/lane-remove.sh "$S"` (confirm it holds no work first).

- [ ] **Step 7: Final commit (verification notes, if any) + branch summary**

```bash
git -C /Users/ducnguyen/clinical/harness log --oneline harness-generalization -8
```
Expected: the six Phase-1 commits present, working tree clean. Phase 1 done — clinical runs through the profile seam with behavior preserved.

---

## Self-Review

**1. Spec coverage (Phase 1 scope):**
- `profiles/` scaffold + profile resolver → Task 1 (`PROFILE`/`PROFILE_DIR`). ✓
- `run_hook` + `harness_spawn` → Task 1. ✓
- Extract clinical lifecycle into hooks → Tasks 2–5 (bootstrap/migrate/seed/boot/health/ci-gate/e2e). ✓
- Thin the `bin/` lifecycle scripts → Tasks 2–5 (lane-up/bootstrap/ci-gate/e2e/integrate/reset). ✓
- Validate on a scratch lane → Task 6. ✓
- Deferred to later phases (correctly NOT here): `auth-seed.cjs` (QC/integrations — Phase 2/3), `profile.env`/`integrations.env`/`workflow.json` (Phase 2/3), `db-shared-up` service-name config (Phase 2), `_template`/`/harness-adapt` (Phase 4). ✓

**2. Placeholder scan:** No TBD/TODO; every hook + edit shows full code; verification commands have expected output. ✓

**3. Type/name consistency:** `run_hook <N> <name>` signature used identically in all call sites; hook filenames (`bootstrap/migrate/seed/boot/health/ci-gate/e2e`) match `run_hook` args; pid/log names (`api/worker/fe`) match `lane-down.sh`'s `for svc in fe worker api`; `harness_spawn` uses exported `RUN_DIR`/`LOG_DIR`; `API_BASE`/`FE_URL`/`DB_NAME`/`TEST_DATABASE_URL` consumed only where `run_hook` (or the ci-gate engine) exports them. ✓

**Behavior-change note (intentional, minor):** the boot-failed state's `notes` field changes from `api_ok=.. fe_ok=..` to a generic "health check failed; see logs"; the gating logic (both must be healthy) is unchanged.
