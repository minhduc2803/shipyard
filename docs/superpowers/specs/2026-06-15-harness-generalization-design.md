# Harness Generalization — Design Spec

**Date:** 2026-06-15
**Repo:** `~/clinical/harness` (the parallel feature harness)
**Status:** Approved design → ready for implementation planning

## 1. Goal

Make the harness **installable against any project**, not just `stack-clinical`.
Today the tool is a generic substrate (isolation, locking, state, dashboard,
MCP/asset wiring) wrapped around a thick layer of clinical-specific assumptions
baked into the lane lifecycle scripts, the QC/ticketer agents, and the
dashboard. We lift every project-specific assumption behind a per-project
**profile**, ship `clinical` as the reference profile (behavior-preserving),
and make adapting the harness to a new project a **Claude-assisted** step.

## 2. Scope & non-goals

**In scope (generalize all layers):**
- Stack lifecycle (boot/build/test/migrate/seed/health/e2e/auth) → profile hooks.
- Org integrations (tracker, dev-site QC, CI-deploy-wait) → optional + provider-configurable.
- Workflow visualization (dashboard pipeline map + stage list) → data-driven from `workflow.json`.
- Claude-assisted onboarding (`_template` profile + `/harness-adapt` skill + `harness-doctor` validator + docs rewrite).

**Non-goals (explicit):**
- **Simultaneous multi-project.** One harness instance serves one project at a
  time (selected by `PROFILE=`). Running two projects = two harness clones with
  deconflicted ports/Redis/dashboard (already possible; not a feature we build).
- **Profile-in-project location.** We chose Approach **A**: profiles live inside
  the harness (`harness/profiles/<name>/`). The clinical app repo is never touched.
- **Pre-building non-East-Agile tracker providers** (Jira/Linear/GitHub Issues).
  We define the provider contract and ship `eastagile` as the reference; other
  providers are generated on demand by `/harness-adapt`.

## 3. Architecture — the profile

```
harness/
  bin/                    # the ENGINE — generic, profile-agnostic (stays)
  dashboard/              # renders whatever workflow.json declares
  profiles/
    clinical/             # the reference profile (lifted from today's hardcoding)
      profile.env         # 1. declarative config (overrides lanes.env defaults)
      hooks/              # 2. stack lifecycle — small scripts
        bootstrap.sh  migrate.sh  seed.sh  boot.sh  health.sh
        ci-gate.sh  e2e.sh  auth-seed.cjs
      integrations.env    # 3. tracker / dev-qc / ci-wait toggles + providers
      workflow.json       # 4. stage list + pipeline graph
    _template/            # stub profile an adopter copies; every hook commented
config/lanes.env          # selects the active profile:  PROFILE=clinical
```

**Active profile** selected by `PROFILE=<name>` in `config/lanes.env` (default `clinical`).

**Seam principle:** the harness owns everything generic — isolation,
port/path/DB allocation, locking, state, process supervision, git, the poll/PR
plumbing — and calls a profile hook *only* for steps that depend on the
target's stack.

## 4. Hook contract

**Exported env (harness → hook), stable & documented:**
`LANE`, `LANE_DIR`, `API_PORT`, `FE_PORT`, `DATABASE_URL`, `REDIS_URL`,
`UPLOAD_DIR`, `API_BASE`, `FE_URL`, `PROFILE_DIR`, `SOURCE_REPO`, `HARNESS_ROOT`.

**Hooks (`profiles/<name>/hooks/`):**

| Hook | Responsibility | Lifted from |
|---|---|---|
| `bootstrap.sh` | install deps in `LANE_DIR` | lane-bootstrap (`uv sync`, `pnpm install`) |
| `migrate.sh` | run migrations against `DATABASE_URL` | lane-bootstrap / lane-reset |
| `seed.sh` | create seed user/org | lane-bootstrap / lane-reset |
| `boot.sh` | build + start services via `harness_spawn` | lane-up |
| `health.sh` | readiness probe (exit 0 when ready) | lane-up health checks |
| `ci-gate.sh` | lint / test / contract checks | lane-ci-gate |
| `e2e.sh` | run the e2e suite | lane-e2e |
| `auth-seed.cjs` | plant a browser session for QC login | lane-qa-login.cjs |

**Helpers (harness-provided):**
- `harness_spawn <name> "<cmd>"` — background a command + record its pid/log
  exactly where `lane-down.sh`/`lane-status.sh` already look. Process lifecycle
  stays harness-side.
- `run_hook <name> [args]` — engine-side invoker that exports the env contract,
  logs, and checks exit status.

**Contract rule:** a hook returns exit 0 = success; all isolation/ports/paths
arrive via env; the hook only runs stack commands.

**Datastore provisioning** (create/drop the lane's DB, pick the Redis index)
stays **harness-side**, driven by profile config (`PG_*`, `REDIS_*`,
`COMPOSE_SERVICES`, `DB_PREFIX`). This assumes the shared-Postgres+Redis model.
Making the datastore engine itself pluggable (a different DB, or no Redis) is a
documented future extension (§12), not initial scope.

## 5. Config surface (`profile.env`)

Keys lifted from `_common.sh` / `lanes.env` / inline literals:
- **Topology:** `API_BASE_PORT`, `FE_BASE_PORT`, `DB_PREFIX`, `PG_*`, `REDIS_*`,
  `COMPOSE_FILE`, `COMPOSE_SERVICES` (e.g. `postgres redis adminer`), `WORKER_QUEUES`.
- **Stack shape:** `DB_URL_SCHEME` (e.g. `postgresql+asyncpg`), `API_PATH`
  (e.g. `/api/v1`), `UPLOAD_SUBDIR`, `BACKEND_DIR`, `FRONTEND_DIR`.
- **Repo / branch:** `SOURCE_REPO`, `ORIGIN_URL`, `BASE_BRANCH` (main),
  `INTEGRATION_BRANCH` (development), `BRANCH_PREFIX` (feat/).
- **Health:** `HEALTH_PATH`, `FE_READY_PATH`.

`lanes.env` keeps these as global **defaults** (fallback); `profile.env`
overrides. Nothing breaks if a key is absent — the default applies.

## 6. Integration toggles (`integrations.env`)

Each integration: `*_ENABLED=0|1` + provider config.

**clinical (enabled):**
```
TRACKER_ENABLED=1   TRACKER_PROVIDER=eastagile
   TRACKER_URL=…/projects/<uuid>/issues/   TRACKER_PROJECT="Stack Clinical"
   TRACKER_STATUS=Started   TRACKER_ASSIGNEE=duc.nguyen   TRACKER_MCP=playwright-ticketer
DEV_QC_ENABLED=1    DEV_SITE_URL=https://dev.stackclinical.com   DEV_QC_MCP=playwright-qa-dev
CI_WAIT_ENABLED=1   CI_PROVIDER=github-status
   CI_DEPLOY_CONTEXT="ci/circleci: deploy-dev"   CI_REPO=EastAgile/stack-clinical
```

**`_template` (fresh adopter — all off):**
```
TRACKER_ENABLED=0   DEV_QC_ENABLED=0   CI_WAIT_ENABLED=0
```
→ GitHub-only adopter gets `implement → ci-gate → PR → integrate → local-QC →
senior-gate → push-dev → done`, integration stages cleanly skipped.

**Pluggability without over-building:** the integration *point* is generic
(toggle + provider + config + which MCP/agent to spawn). Ship `eastagile` as the
reference tracker provider; define the contract for others; generate new
providers on demand via `/harness-adapt`. CI-wait keys on a GitHub commit-status
context (`CI_DEPLOY_CONTEXT`), covering CircleCI / GH-Actions / others.

## 7. Workflow externalization (`workflow.json`)

Schema: `stages[]` of `{id, label, phase, evidence?, integration?}` + `fix_bus`.
The dashboard renders the subway-map **from this file**: group by `phase`, check
each `evidence` field against lane state, and hide/grey any stage whose
`integration` is disabled. ship-feature references stage **IDs**; conditional
stages key off the integration toggles. Replaces the dashboard's hardcoded
`STAGE_ORDER` / `NODES` / `PHASES` / `TKT` + the "stage 5/11" literals.

## 8. Clinical migration & no-regression validation

- **Extract, don't rewrite:** command lines move out of `lane-up.sh` /
  `lane-bootstrap.sh` / `lane-ci-gate.sh` / `lane-e2e.sh` / `lane-integrate.sh` /
  `lane-reset.sh` into `profiles/clinical/hooks/*.sh` **verbatim**; scripts call
  `run_hook <name>` in the same order with the same env.
- **Lift literals to config** with `lanes.env` fallback. clinical's
  `workflow.json` encodes today's exact stages → dashboard renders identically.
- **Validation without disturbing running lanes:** harness scripts are
  per-invocation (editing them doesn't touch the 8 running lanes' live
  processes). Verify the new hook path on **one** scratch/free lane
  (bootstrap → up → health → ci-gate → e2e). Verify the data-driven dashboard on
  a **second port** against the same state before restarting the main one.
  Remaining lanes adopt the new path on their next reboot — no forced disruption.

## 9. Claude-assisted onboarding

- **`profiles/_template/`** — every hook present but stubbed + commented with the
  env-var contract; `profile.env` / `integrations.env` / `workflow.json` with
  placeholders and a GitHub-only default (all integrations off).
- **`profiles/clinical/`** — the worked reference an adopter reads beside the template.
- **`/harness-adapt` skill** — inspects the adopter's repo (package manager,
  framework, build/test/migrate commands, compose services, branches), drafts
  `profile.env` + hooks + workflow, asks the human to confirm what it can't infer
  (seed command, health path, e2e contract, which integrations), writes the
  profile, and dry-run bootstraps lane 1 to validate.
- **`harness-doctor`** — validates a profile is complete (hooks executable,
  required config present, MCP servers registered) before first run; also Claude's
  dry-run check.
- **SETUP / README rewrite** — profile-oriented ("clone harness → `/harness-adapt`
  → go"), clinical as the example rather than the assumption.

## 10. Affected components (from the coupling audit)

- **Engine `bin/`:** `lane-up`, `lane-bootstrap`, `lane-ci-gate`, `lane-e2e`,
  `lane-integrate`, `lane-reset`, `lane-push-dev`, `_common.sh`, `db-shared-up`
  (service names), `lane-qa-login(.cjs)` → thinned to orchestration + `run_hook`.
- **New:** `run_hook` + `harness_spawn` (in `_common.sh`), profile resolver.
- **Dashboard (Node.js+React):** data-driven workflow renderer; read repo / dev-site /
  tracker from profile config; credential model driven by `integrations.env`.
- **Skills:** ship-feature (stage IDs + conditional integration stages);
  review-prs (already generic — paths only).
- **Agents:** `ticketer` / `dev-qc` → provider-parameterized + optional;
  `qc-local` / `senior-gate-reviewer` / `pr-reviewer` → de-clinical the
  stack-specific lore (migration runner, openapi paths) via profile config.
- **New profile dirs:** `profiles/clinical/`, `profiles/_template/`.
- **Docs:** SETUP / README / USAGE profile-oriented.

## 11. Phased implementation (each phase keeps clinical green)

1. **Phase 1 — Stack adapter seam.** `profiles/` scaffold + profile resolver +
   `run_hook` + `harness_spawn`; extract clinical lifecycle into
   `profiles/clinical/hooks`; thin the `bin/` lifecycle scripts. Validate on a
   scratch lane. *(Correctness-critical foundation.)*
2. **Phase 2 — Config + integration toggles.** Lift remaining literals to
   `profile.env`; add `integrations.env`; make ship-feature's tracker / dev-qc /
   ci-wait stages conditional; parameterize the `ticketer` / `dev-qc` agents.
3. **Phase 3 — Data-driven workflow.** `workflow.json` + dashboard renderer
   *(biggest UI work / regression risk)*. Verify on a scratch dashboard port.
4. **Phase 4 — Onboarding.** `_template`, `/harness-adapt`, `harness-doctor`,
   docs rewrite.

## 12. Risks & mitigations

- **Dashboard renderer regression** → scratch-port verify; clinical
  `workflow.json` reproduces today's map exactly.
- **Running lanes** → per-invocation scripts; test on one lane; no forced reboots.
- **e2e contract tightness** (the `E2E_*` two-way contract) → keep clinical's
  `e2e.sh` verbatim; document the contract for adopters.
- **MCP server-name coupling** → profile declares the MCP names; `harness-doctor`
  checks they're registered.
- **Datastore assumption** → initial scope assumes shared Postgres + Redis via
  the source repo's compose; per-lane DB create/drop is harness-side. A future
  `provision.sh` / `deprovision.sh` hook pair would make the datastore engine
  pluggable (different DB, no Redis) — out of initial scope.
- **Secrets** → never commit `config/secrets.env` or per-lane creds (gitignored);
  profiles hold NO secrets (those stay in `config/secrets.env`).

## 13. Success criteria

- clinical runs unchanged through the full pipeline after migration (behavior-preserving).
- A fresh GitHub-only project can be onboarded via `/harness-adapt` and run
  `implement → ci-gate → PR → integrate → local-QC → senior-gate → push-dev → done`
  with no tracker / dev-qc / ci-wait.
- No clinical/East-Agile literal remains in `bin/`, `dashboard/`, or skills —
  only in `profiles/clinical/` + `config/`.
