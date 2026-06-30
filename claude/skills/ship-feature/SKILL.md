---
name: ship-feature
description: "Autonomous end-to-end feature pipeline for ONE harness lane. Invoke inside a lane clone with a requirement: `/ship-feature <requirement>`. Frontloads ALL clarifying questions once, then runs unattended: implement (TDD) → pre-push CI gates → e2e on feature branch → integrate onto development → dev CI gates → e2e on dev → code review → local QC → senior GO/NO-GO gate → push development → push branch+open PR → QC dev → file ticket → report, then keeps watching the PR for new review comments and routes worth-fixing feedback back through the same gated loop until the PR is merged/closed. The PR is only published after all local gates pass — it's finalized when reviewers see it. Writes lane state at every step for the watch dashboard. Use when the user wants to build/ship/implement a feature in a parallel harness lane."
---

# Ship Feature (harness lane pipeline)

You are running the autonomous feature pipeline for **one lane** of the parallel feature harness. The human's only interactive touchpoint is **Stage 0 (frontloaded Q&A)**; after that you run to completion or to a `blocked` escalation, reporting progress through the lane's state file (which the watch dashboard renders).

## Setup — do this first, every run

```bash
LANE_DIR="$(pwd)"                            # the lane clone IS your cwd — resolved at runtime, never a hardcoded path
HARNESS="@@HARNESS_ROOT@@"                    # populated to the real harness path when the harness is installed
N="$(cat .harness-lane 2>/dev/null)"         # lane number, read from the clone
```
- If `.harness-lane` is missing, you are NOT inside a lane clone. STOP and tell the user to assign one first: run `"$HARNESS/bin/lane-assign.sh" "<feature>"` — it picks a free lane, boots it, and prints the `cd <lane> && claude` command. Then re-invoke `/ship-feature` from that lane. (If no lane is bootstrapped yet: `"$HARNESS/bin/lane-bootstrap.sh" <n>`.)
- **Paths auto-resolve — never hardcode.** Your lane clone is the current directory (`$LANE_DIR`); the harness path (`$HARNESS`) is baked in when the harness is installed. Use these everywhere — including the **clone path you hand to subagents** — so the pipeline is correct no matter where the project lives.
- All state updates go through `"$HARNESS/bin/state.sh" "$N" set key=value ...` — **call it at the start of every stage** (this is also the heartbeat). Always set `feature_title` early so the dashboard is readable.
- **Integration toggles.** Check which integrations are enabled by **executing** `"$HARNESS/bin/lane-env.sh" "$N" --check tracker|dev_qc|ci_wait` (exit 0 = on). **Do NOT `source "$HARNESS/bin/_common.sh"` yourself** — the Bash tool runs zsh, where sourcing it silently mis-resolves to the `_template` profile and every integration reads OFF (the `bin/*` scripts are immune — they execute it under their bash shebang). **SKIP the stages for disabled integrations** — Stage 10 (Ticket) only runs if `lane-env.sh "$N" --check tracker`, Stage 12 (QC on dev) only if `--check dev_qc`, and the deploy-wait inside dev-QC only if `--check ci_wait`. (When all three are enabled, the full pipeline runs.)
- **Heartbeat during long stages.** Implementing (Stage 1) and CI/deploy waits (Stages 11-12) can run many minutes between stage transitions — bump the heartbeat with `"$HARNESS/bin/state.sh" "$N" set` after each commit and on each poll iteration, so the dashboard doesn't false-flag a working lane as STALLED. (The long helper scripts — ci-gate/e2e/up — heartbeat themselves.)
- Helper scripts live in `"$HARNESS/bin/"`. Use them; don't reinvent their logic.
- **NEVER merge or rebase branches manually.** Always use `lane-integrate.sh` for integration (it fetches latest `origin/development` and resets before merging — never merge into a stale local branch). Always use `lane-push-dev.sh` for pushing development (it re-checks and re-merges if `origin/development` moved since your integrate). Manual git merges bypass these safety checks and risk pushing stale code.

## Context recovery — after conversation compaction

Long pipelines outlive the context window. When context is compacted (summarized),
re-derive these critical values before continuing:

```bash
LANE_DIR="$(pwd)"                           # lane clone = cwd (runtime)
HARNESS="@@HARNESS_ROOT@@"                   # baked at install
N="$(cat .harness-lane 2>/dev/null)"
eval "$("$HARNESS/bin/lane-env.sh" "$N")"   # re-establish lane env (API_BASE, FE_URL, DB vars) + integration toggles — never `source _common.sh` (breaks under zsh)
```

Then check your current position:
- **Lane state**: `"$HARNESS/bin/state.sh" "$N" get` — shows current stage, status, feature_title, branch, gate_decision, pr_url, ticket_url, notes.
- **Git branch**: `git rev-parse --abbrev-ref HEAD` — which branch you're on.
- **Integration toggles**: `"$HARNESS/bin/lane-env.sh" "$N" --check dev_qc && echo ON || echo OFF` (same for `tracker`, `ci_wait`) — do NOT skip or run integration stages from memory; always re-check.
- **Feature slug**: from the state's `branch` field (`development+feat/X` → `feat/X`).

Resume from the stage shown in lane state. If state says `stage=X status=running`, you were mid-stage X when context compacted — re-run that stage from the top (all harness scripts are idempotent).
- **MCP preflight (fail fast):** confirm this session actually loaded the lane's required playwright MCPs (their `browser_*` tools must be available). The required list **adapts to the enabled integrations**: `playwright` + `playwright-qa-local` are ALWAYS required; the dev-QC MCP (`@@DEV_QC_MCP@@`) is required ONLY if `"$HARNESS/bin/lane-env.sh" "$N" --check dev_qc`; the tracker MCP (`@@TRACKER_MCP@@`) ONLY if `"$HARNESS/bin/lane-env.sh" "$N" --check tracker`. (When all integrations are on, all four are required.) If any required MCP is missing, do NOT start the pipeline and do NOT let Stage 12 discover it later: run `"$HARNESS/bin/lane-mcp-sync.sh" "$N"`, then STOP and tell the human to restart this Claude session (project MCPs load only at session start). Catching this at Stage 0 costs a minute; catching it at Stage 12 strands a shipped feature.

## Hard rules

- **Push `development` ONLY after the senior-gate-reviewer returns `VERDICT: GO`.** Nothing else authorizes a `development` push. (This is the one harness exception to "the user pushes development" — see the user's memory.)
- **The fix-loop:** any failure in stages 2b–8 (e2e on feature, integrate, dev-gates, e2e on dev, review, QC, gate, push dev) → fix on the **feature branch**, and re-run **from Stage 2**. Never skip a gate. **Every re-entry runs the FULL remaining pipeline through Stage 12** — after any `development` push (Stage 8) and push/update of the feature branch (Stage 9), the parallel ticket kick-off (10), the async CI watch (11), and the background dev-qc spawn (12) all happen.
  - **EXCEPTION — test-only re-entry (browser-QC fast-path).** If the re-entry's change is ENTIRELY test files — `git diff --name-only` since the last browser-QC'd commit matches only the profile's `TEST_PATHS` (read from `profiles/$PROFILE/profile.env`) — the app's runtime behavior/UI is unchanged from the last QC'd pass. Run this EXACT stage set, nothing else:
    - **Always run:** Stage 2 (CI gate — the profile's lint/test/contract checks, on the feature branch), Stage 3 (integrate), Stage 4 (dev CI gate — runs the changed tests on the merged tree), Stage 7 (senior gate), Stage 8 (push dev), Stage 9 (PR update), and the Stage 10/11 tail (ticket update + CI watch).
    - **Run only if e2e spec files are among the changed tests:** Stage 2b (e2e on feature) and Stage 5 (e2e on dev). No e2e specs changed → skip both.
    - **Always SKIP** (runtime UI unchanged): Stage 5c (QC plan), Stage 6 (qc-local), Stage 12 (dev-qc). Record `QC skipped: test-only change` in the notes.
    - If the diff contains ANY non-test file → this fast-path does NOT apply; take the full path above. The first pass (not a re-entry) always runs full QC.
- **Run long helpers so they can't be killed mid-flight or hang your turn.** `lane-ci-gate.sh`, `lane-integrate.sh`, `lane-up.sh`, `lane-e2e.sh`, `lane-push-dev.sh` legitimately run 3–20+ minutes (builds, tests, Playwright, lock waits — locks time out after 30 min with a clear error). NEVER invoke them with the default Bash timeout (2 min kills them mid-flight and strands the lane half-done): use `run_in_background: true` and poll the output file until done, or set `timeout: 600000` for the shorter gates. If a helper does die mid-run (state says one thing, `lane-status.sh`/ports say another), don't panic: every helper is idempotent — re-run the step (e.g. re-run `lane-up.sh <N> --no-build` to revive a stack whose merge already landed).
- **Waiting + polling NEVER use a foreground `sleep`** (the Bash tool blocks it) or `ScheduleWakeup` (that's a `/loop`-only primitive — `/ship-feature` is not a `/loop` session, so it won't sustain your watch). To pace a poll loop or wait out a timer, **background the wait**: run `sleep <secs>` with `run_in_background: true` — the harness re-invokes you when it exits, and re-invokes you the moment a backgrounded Agent (Stage 10 ticketer / Stage 12 dev-qc) or helper finishes, so you never busy-poll for background work. **If you ever can't sustain a wait/loop in this session, set lane state with an honest `notes=` and STOP — never narrate a watch or loop you are not actually running.**
- **e2e: actively poll — never wait on the completion re-invoke alone.** A hung suite never fires it, stranding the lane at `stage=e2e`. When running `lane-e2e.sh` (Stages 2b/5): start it `run_in_background: true` AND background a `sleep 90` beside it. Each wake — finished → parse PASS/FAIL; still running → read the e2e log tail, bump the heartbeat, and re-background `sleep 90`, UNLESS it's erroring or has run past ~22 min, in which case kill the e2e task and treat it as FAIL → re-enter Stage 2. (`lane-e2e.sh` self-bounds too: it hard-times-out the Playwright run at `E2E_TIMEOUT` (default 1200s) and exits FAIL, so a hang still surfaces even if a poll is missed.)
- **No retry cap — the phase clock is the signal.** A failing gate/QC/CI/e2e just re-enters the loop (fix on the feature branch, re-run from Stage 2); there is NO automatic block after N attempts. The dashboard shows how long the lane has sat in its current phase (`stage_since`), so the human can spot a stuck or endlessly-looping lane and step in. Reserve `status=blocked` for GENUINE blockers you cannot resolve (an ambiguous merge conflict, a hard/unrecoverable error).
- **Commit only on the feature branch.** Never commit on `development`/`main`. Stage only intended files (this repo collects stray `*.png`/QA artifacts — never `git add .`).
- Keep the lane's state truthful: on any stop, set an accurate `stage`/`status`/`notes`.
- **Quality bar (applies to every code change, including fix-loop re-entries).** Tests are sharp and meaningful — each pins a real behavior/edge case (happy + negative + boundary), none trivial, redundant, or coverage-padding. Comments are minimal — only the non-obvious *why*, matching the surrounding density; never narrate the *what*. Investigate before fixing (root cause, not symptom). Prefer reusing/extending existing code over duplicating it.
- **One driver per MCP browser server.** Each MCP server owns ONE browser; two agents driving the SAME server interleave clicks in one tab. Ownership map: `playwright-qa-local` → the qc-local agent (Stage 6); `playwright` → the main session for ad-hoc checks only (never while qc-local runs); `@@TRACKER_MCP@@` → the ticketer agent; `@@DEV_QC_MCP@@` → the dev-qc agent. Parallel agents on DIFFERENT servers are safe by design; a second concurrent driver on the SAME server is never OK.
- **Cross-lane etiquette (locks + siblings).** Lanes share one machine and one dev site. Waiting on a cross-lane serializer (the build/e2e/integration locks inside the helpers, or any `lane-lock.sh` lock) is NORMAL — helpers heartbeat while they wait, so you won't look stalled. NEVER free a lock by killing another lane's session or processes, deleting `harness/locks/*`, or shrinking `LOCK_MAX_HOLD`; a dead holder's lock auto-expires on its own. If a lock wait times out: re-try with a longer timeout, or set `status=blocked` with a note and report. Touch ONLY your own lane's clone, state, and locks you hold. On the shared dev site, use ONLY your lane's QA account (`<lane>/.harness-qa.env`) and never touch data another lane's account created.

## Stages

### 0 — Intake & frontloaded Q&A  *(the only interactive part)*
Do NOT jump to code. Understand the requirement first.

- **Restate + quick scan.** Restate the requirement. Do a fast targeted scan of the relevant code (use the `Explore` agent for breadth; the **brainstorming** skill if the requirement is fuzzy) so your questions are grounded in what actually exists.
- **Frontloaded Q&A.** Ask the human **every** clarifying question in ONE batch: acceptance criteria, scope / non-goals, UI/UX specifics, data shapes, edge cases, which existing flows it touches. Then **open a clean per-feature state slot** so this run can't write into a previous feature's state even if the human didn't click *clear* first: `"$HARNESS/bin/state.sh" "$N" init` — this preserves prior features' files (they stay browsable in the dashboard) and resets `.active`→`_pending`, so the dashboard map reflects THIS run, not the last one. Then mark intake on the fresh slot: `"$HARNESS/bin/state.sh" "$N" set feature_title="<short title>" stage=intake status=running`. Announce "Questions answered — going autonomous now." After this, don't ask the human anything unless you hit a `blocked` escalation.

### 0b — Investigate & plan  *(autonomous)*
- `state.sh "$N" set stage=plan` — now design a real plan and have it independently challenged before you implement.
- **Investigate (autonomous, thorough).** Read the actual code paths, models, existing tests, and conventions the feature touches — `Explore`/`general-purpose` subagents for breadth, then read the key files yourself for depth. Pin down: integration points, data/migration needs, API/contract impact, reuse opportunities, and risks. Use **systematic-debugging** if the feature is a fix (root-cause first, no symptom patches).
- **Plan.** Produce a concrete implementation plan (the **writing-plans** skill): approach, files to change, the test strategy (which behaviors/edge cases each test will pin), migration/contract impact, and how each acceptance criterion is met.
- **Debate the plan (adversarial review).** Spawn a SEPARATE sub-agent (Agent tool — `Plan` or `general-purpose`) to critique the plan + investigation: missed requirements, wrong assumptions, a simpler approach, unhandled edge cases, acceptance-criteria gaps. Apply the worthwhile critiques (use **receiving-code-review** judgment — verify each point, don't blindly accept or reject). Iterate once or twice until the plan holds up.
- Write the Q&A answers **and the agreed plan** to the lane spec file `docs/superpowers/specs/lane<N>-<slug>.md` (gitignored) — the acceptance contract the senior gate checks against.

### 1 — Implement (TDD, to the plan)
- Choose a **single-segment slug** for the feature — lowercase, hyphens, NO slashes. The slug keys the branch, the state file (`state/laneN/<slug>.json`), AND the proof dir (`proof/<slug>/`); they must match or the dashboard can't join them. Cut the feature branch from **main** (clean PR diff): `git fetch origin && git checkout -b feat/<slug> origin/main`.
- Activate per-feature state tracking and **capture the canonical slug**: `SLUG="$("$HARNESS/bin/state.sh" "$N" activate feat/<slug>)"`. `activate` sanitizes the slug (drops `feat/`, turns `/` and spaces into `-`), sets the `.active` pointer, renames the Stage-0 `_pending.json` to `<slug>.json`, and **echoes the canonical `<slug>`**. Use that `$SLUG` for the proof paths and every agent handoff so state ↔ proof stay joined.
- Implement the agreed plan with the **test-driven-development** skill: failing test → minimal code → green → commit. Frequent small commits.
- **Tests must be sharp and meaningful.** Each test pins a real behavior or edge case from the plan / acceptance criteria — cover the happy path, the negative/error path, and boundaries. NO trivial or redundant tests: don't assert constants or framework internals, don't re-test the same path twice, don't pad for coverage. A few precise tests that would actually catch a regression beat many shallow ones.
- **Comment only when it earns its place.** Match the surrounding code's comment density. Comment the non-obvious *why* (intent, invariants, gotchas, links to context) — never narrate the *what* the code already says. Delete redundant/boilerplate/restating comments rather than adding them.
- If your stack generates an API contract/client and the API changed, regenerate it so the contract-check gate passes (stacks without a contract gate skip this).
- `state.sh "$N" set stage=implementing branch=feat/<slug>`

### 2 — Pre-push CI gates (on the feature branch)
- `"$HARNESS/bin/lane-ci-gate.sh" "$N"` — runs the profile's CI gate (lint / test / contract checks) against an isolated per-lane test DB.
- On failure: read the output, fix on the feature branch, commit, re-run. Loop until green.

### 2b — E2E on the feature branch
`lane-e2e.sh` doesn't run migrations itself — it tests the already-running stack. To exercise the feature's code and any new schema, boot the lane stack with the feature branch first:

- `state.sh "$N" set stage=e2e-feature status=running`
- `MOCK_AGENT=true RATE_LIMIT_ENABLED=false "$HARNESS/bin/lane-up.sh" "$N"` — applies the feature branch's own migrations and reboots the stack. This is the same boot step that integration runs, just on the feature branch alone before the dev merge. Idempotent; safe to re-run.
- `"$HARNESS/bin/lane-e2e.sh" "$N"` — Playwright e2e under the e2e lock against the now-booted stack.
- On failure: fix on the feature branch, commit, re-run from Stage 2. Catching e2e failures here saves the cost of a full integration cycle.
- On success: `state.sh "$N" set stage=e2e-feature-passed status=running`

> **Test-only fast-path:** on a fix-loop re-entry whose change is ENTIRELY test files (see the fix-loop EXCEPTION rule), SKIP Stage 2b — unless e2e spec files are among the changed tests, in which case run just the boot + e2e (no QC skip).

### 3 — Integrate onto development  *(local; test stack)*
- `MOCK_AGENT=true RATE_LIMIT_ENABLED=false "$HARNESS/bin/lane-integrate.sh" "$N" feat/<slug>` — fetches the **latest `origin/development`**, resets to it, then merges the feature branch and reboots the lane stack in CI-mode at `http://localhost:300<N>`. The script always integrates against the freshest remote — never a stale local copy.
- **Merge conflict (exit 4) is normal work, NOT a blocker.** The conflicted merge is left in place. Resolve every conflict thoughtfully — keep `development`'s behavior for code unrelated to this feature, preserve the feature's intent where they overlap — then `git add` ONLY the conflicted files, `git commit --no-edit`, and finish with `"$HARNESS/bin/lane-integrate.sh" "$N" --continue feat/<slug>` (it runs the remaining migrate + boot steps). Escalate `status=blocked` ONLY when a conflict is genuinely ambiguous and you cannot tell which behavior is correct.

### 4 — CI gates on the development-merged branch
- `state.sh "$N" set stage=dev-gate status=running`
- `"$HARNESS/bin/lane-ci-gate.sh" "$N"` — runs the full gate suite again on the development-merged branch. Catches integration regressions: conflicting test IDs, contract drift from a concurrent merge, migration ordering issues.
- On failure: read the output, fix on the **feature branch** (never commit on development), re-run from Stage 2.

### 5 — E2E on the development-merged stack
- `state.sh "$N" set stage=e2e status=running`, then `"$HARNESS/bin/lane-e2e.sh" "$N"` — Playwright e2e under the e2e lock (it sets `stage=e2e-passed` on success). Failure → fix on the feature branch → re-run from Stage 2.
- **If e2e fails with widespread "Loading" timeouts or connection errors:** the frontend build is likely stale (API URL not baked in). Rebuild: `MOCK_AGENT=true RATE_LIMIT_ENABLED=false "$HARNESS/bin/lane-up.sh" "$N"` (the boot hook clears `.next/` and rebuilds with the correct `NEXT_PUBLIC_API_BASE_URL`), then re-run e2e. This can happen after integration changes routes or merges new frontend code.

### 5b — PR code review  *(no open PR yet — use local diff)*
- Run the **`code-review` skill at effort `high`** on the feature diff vs `origin/main` — this is the deterministic code-review gate, not an ad-hoc read. The PR isn't open yet, so point it at the local diff: `git diff origin/main...feat/<slug>` (and `git log origin/main..feat/<slug>` for commits). ONLY if the `code-review` skill is unavailable, fall back to a manual review of that diff (correctness, security, tests, migration/contract safety). The Stage-6 `qc-local` report covers the user-flow review for the senior gate.
- Apply the fixes worth making on the feature branch; if you change code, re-run **from Stage 2**.
- `state.sh "$N" set stage=review`

### 5c — QC plan  *(bound the test scope before any browser QC)*
- Author a **QC Plan** the browser-QC agents (Stages 6 and 12) will execute against — so QC covers everything that matters and nothing that doesn't (no missed scenarios, no wandering into unrelated areas). Derive it from the acceptance points (lane spec) + the real change surface (`git diff origin/main...feat/<slug>` and `--stat`). Three parts:
  - **In-scope scenarios** (numbered): each acceptance point with positive AND negative cases; adjacent flows sharing routes/components/data with the change; required **state coverage** (reload on each stateful screen touched, one logout→re-login, back/forth nav); and the required **UI/UX layout checks** for every form/screen the feature touches (narrow AND short viewport, expandables open so content exceeds the viewport, fixed chrome not clipped, every control labelled, section headers more prominent than field labels).
  - **Out-of-scope** (explicit): areas NOT to test because the change cannot affect them — this is what stops QC from over-testing.
  - **Smoke set**: login + main nav + ≥3 unaffected major areas.
- Append it to the lane spec under a `## QC Plan` heading (`docs/superpowers/specs/lane<N>-<slug>.md`) — the same file the senior gate reads. You are the **single writer** of this section; the QC agents only *propose* additions in their reports and you fold them in (Stage 6). This keeps the plan race-free yet living.
- `state.sh "$N" set stage=qc-plan status=running`

### 6 — Browser QC via the qc-local agent
- **Test-only fast-path:** on a fix-loop re-entry whose change is ENTIRELY test files (see the fix-loop rule), SKIP this stage — the app's runtime UI is unchanged — and record `QC skipped: test-only change`. Otherwise run it:
- `state.sh "$N" set stage=qc status=running`, then launch the **qc-local** agent (Agent tool, `subagent_type: qc-local` — FOREGROUND; it gates the pipeline). Give it: lane N + clone path, the feature slug (`feat/<slug>` → `<slug>`), the feature title, the acceptance points (lane spec), and the **QC Plan** (lane spec, Stage 5c) as the authoritative scope to execute against. It owns the whole local browser QC: `playwright-qa-local`, the lane seed account, the planned feature + smoke + reload/re-login coverage, the UI/UX layout pass, upload fixtures (if configured), and proof to `proof/<feature-slug>/qc-local/<NN>-<what>.png` (the dashboard gallery path). Do NOT drive the browser yourself at this stage.
- Parse its last line: `LOCAL-QC: PASS` → continue. `LOCAL-QC: FAIL — <reasons>` → fix on the feature branch → re-run from Stage 2. Keep its report — it is the feature user-flow review for the senior gate.
- **Fold back discoveries:** if its report lists scenarios it found that weren't in the plan (its "Scenarios discovered during QC" section), add them to the `## QC Plan` in-scope list in the lane spec — so the senior gate, any re-entry, and Stage-12 dev-QC all run the updated scope.

### 7 — Senior GO/NO-GO gate  *(authorizes the dev push)*
- Launch the **senior-gate-reviewer** agent (Agent tool, `subagent_type: senior-gate-reviewer`). Give it: lane N + clone path, the requirement + Stage-0 answers (the lane spec file), the feature branch, the Stage-5b code-review findings + resolutions and the Stage-6 `qc-local` report (the user-flow review), and confirmation that gates/e2e/review/QC passed. The agent can inspect the local diff with `git diff origin/main...feat/<slug>` — no open PR is required.
- Parse its final line:
  - `VERDICT: GO` → proceed to Stage 8.
  - `VERDICT: NO-GO — <fixes>` → fix on the feature branch, re-run **from Stage 2**. No attempt cap — the loop re-enters; the dashboard's time-on-phase surfaces a lane stuck cycling so the human can step in. Set `status=blocked` only for a genuine blocker you can't resolve.
- `state.sh "$N" set stage=gate gate_decision=GO` (or NO-GO)

### 8 — Push development  *(GATED — only on GO)*
- `"$HARNESS/bin/lane-push-dev.sh" "$N" feat/<slug>` — under the integration lock:
  - `origin/development` unchanged since integrate → pushes your already-validated merge **as-is** (the exact tested commit);
  - it **MOVED** → the local merge is **discarded**, `development` is hard-reset to the latest origin, and `feat/<slug>` is **re-merged fresh** (history stays clean: latest dev + one merge commit), then pushed.
- Exit 3 = the fresh re-merge conflicts with the newer development (local dev is left reset to origin, old merge gone) → re-run from Stage 3 (conflicts resolve inline there) → re-run Stage 4 → re-QC → re-gate → push again.
- **Note — a clean re-merge can change what ships.** When `origin/development` MOVED and the fresh re-merge is *clean* (no exit 3), the pushed commit differs from the exact tree the senior gate validated, yet it auto-deploys to dev as-is. A clean git merge does NOT prove integration-safety: collisions that aren't textual conflicts still slip through — duplicate migration identifiers, duplicate fixture/test IDs, API/schema-contract drift, lockfile divergence — in whatever form your stack expresses them. Your safety nets are the senior gate's merge-safety check and the Stage-12 dev-QC (which runs on the *deployed* tree). If a re-merge pulled in substantial unrelated development work, treat the result as not-yet-validated and consider re-running from Stage 4 before relying on the deploy.
- `state.sh "$N" set stage=pushed-development`

### 9 — Push feature branch + open/update PR  *(post-gate; finalized before reviewers see it)*
- `git push -u origin feat/<slug>` — first push of the feature branch to remote. All gates have passed before this point.
- Open or update the PR targeting **main**: `gh pr create --base main --fill` (or `gh pr edit` if a prior run already created it). Capture the URL.
- `state.sh "$N" set stage=pr-open pr_url="<url>"` — the dashboard shows the PR link from here.

### 10 — Ticket  *(parallel — kick off right after Stage 9; NON-blocking)*
- **Only if `"$HARNESS/bin/lane-env.sh" "$N" --check tracker`** — otherwise skip this stage entirely (no ticket; leave `ticket_url` empty and note 'tracker integration off').
- Immediately after the PR is open, launch the **ticketer** agent **in the background** (Agent tool, `subagent_type: ticketer`, `run_in_background: true`). Give it: lane N + clone path, the feature slug, title, PR URL, and a one-paragraph summary of what shipped. It creates or updates **one** ticket in the configured tracker (project/status/assignee from its injected Tracker target line; idempotent — update, never duplicate) and writes the copy-paste HTML task report to `proof/<feature-slug>/ticket/REPORT.html` (the dashboard shows it as the 🎫 link).
- **Do NOT wait for it** — proceed straight to Stages 11–14 while it runs (the dev-qc agent from Stage 12 is running in parallel too). When its result arrives, parse the last line `TICKET: <url>` and record the evidence: `state.sh "$N" set ticket_url="<url>"` — the map shows the ticket node ⚠ until `ticket_url` is set. `TICKET: FAIL — <reason>` → do NOT swallow it: leave `ticket_url` empty (⚠ stays) and note it.
- If it died without a result, re-run it (idempotent). Don't let the lane finish with the ticket ⚠ unexplained.

### 11 — Async CI watch  *(non-blocking)*
- Check the PR's CI and `development`'s CI with `gh`. If red, drop into the fix-loop (Stage 2). Otherwise continue — never idle waiting for green. Record `ci_status`.

### 12 — QC on dev  *(parallel — background dev-qc agent; runs concurrently with other lanes' dev-QC)*
- **Only if `"$HARNESS/bin/lane-env.sh" "$N" --check dev_qc`** — otherwise skip (no dev-QC; set `qc_dev=` empty / note 'dev-QC off').
- Immediately after Stage 9's PR open (alongside the Stage-10 ticket kick-off), spawn the **dev-qc** agent in the background (Agent tool, `subagent_type: dev-qc`, `run_in_background: true`). Give it: lane N + clone path, the feature slug (`feat/<slug>` → `<slug>`), the feature title, the acceptance points, and the **QC Plan** (lane spec, Stage 5c) as the scope to execute against — the same plan qc-local used, including any scenarios folded in since.
- The agent owns the WHOLE dev-QC lifecycle: the deploy-wait for the CURRENT `origin/development` HEAD (only when CI-wait is enabled), browser QC of the configured dev site via the dev-QC MCP (`@@DEV_QC_MCP@@`) logged in as the lane's OWN dev-QC account (configured in `<lane>/.harness-qa.env`; the agent never needs to know the email/password), proof screenshots to `proof/<feature-slug>/qc-dev/<NN>-<what>.png`, and the `qc_dev` state field (`running|passed|failed`). It does NOT touch `stage`/`status` — the main session owns those. No cross-lane lock: lanes dev-QC in parallel on their own accounts; mid-run deploys are handled by the agent (cumulative merges + reload-and-retry).
- **Do NOT wait for it** — proceed to Stages 13/14; dev QC must never block the report or PR-watching. Handle its verdict when it arrives:
  - `DEV-QC: PASS` → nothing to do (it already set `qc_dev=passed`); fold any "Scenarios discovered during QC" from its report into the `## QC Plan`.
  - `DEV-QC: FAIL — <reasons>` → treat exactly like a QC failure: fix on the feature branch, re-enter from Stage 2 (the re-entry's push spawns a FRESH dev-qc run).
  - Agent died with no verdict → re-spawn it (idempotent: it re-checks the deploy and re-runs).
- Never QC the dev site inline in the main session, and never drive the dev-QC MCP (`@@DEV_QC_MCP@@`) yourself while a dev-qc agent is out.

### 13 — Report
- Post a concise final report (PR URL, dev-deploy status, ticket URL, what shipped). If the background dev-qc or ticketer agents haven't reported yet, say so ("dev-QC running in background — verdict lands during the watch loop") rather than waiting for them.
- `state.sh "$N" set stage=reported status=running`
- Do **NOT** reset the lane. Cleanup is the human's call, from the dashboard (**clear** tidies the status fields; **reset** wipes to clean development) — they may still be manually testing.

### 14 — Watch the PR for review feedback + base conflicts  *(post-ship loop)*
- `state.sh "$N" set stage=watching-pr notes="watching PR for comments + main conflicts"`
- Loop every ~5 minutes, paced by a **backgrounded** wait so the turn isn't pinned (see the waiting-primitive rule above): run `sleep 300` with `run_in_background: true` — the harness re-invokes you when it elapses, and sooner if a Stage-10/12 background agent finishes. Each iteration:
  - **Collect background agents first** (their results arrive between polls): the Stage-10 ticketer (`TICKET: <url>` → record `ticket_url`; re-run if it died) and the Stage-12 dev-qc verdict — `DEV-QC: PASS` → nothing; `DEV-QC: FAIL — <reasons>` → handle like a worth-fixing comment: fix on the feature branch, re-enter from Stage 2 through Stage 12; died without a verdict → re-spawn it.
  - Run `"$HARNESS/bin/lane-pr-comments.sh" "$N"` — prints `PR_STATE:`, `PR_MERGEABLE:`, + any comments newer than the lane's cursor (issue comments, inline review comments, review verdicts), and bumps the heartbeat.
  - `PR_STATE: MERGED` or `CLOSED` → `state.sh "$N" set stage=done status=passed notes="PR merged/closed; lane ready for cleanup"` → STOP (leave the lane for the human to clear/reset from the dashboard).
  - `PR_MERGEABLE: CONFLICTING` → the feature branch conflicts with `origin/main` (the PR base). Resolve it as real work:
    - `git checkout feat/<slug> && git fetch origin && git merge origin/main`
    - Resolve every conflict thoughtfully — read both sides; keep `main`'s behavior for code unrelated to this feature, preserve the feature's intent where they overlap; when genuinely ambiguous, STOP and escalate (`status=blocked`, note the files) rather than guess. Commit the merge.
    - Re-enter the pipeline **from Stage 2 and run it through Stage 12** (gates → e2e on feature → integrate → dev-gates → e2e + QC → reviews → senior gate → push development → push/update PR → ticket update (parallel) + CI watch → **dev-QC**), then return here and keep watching.
    - (`PR_MERGEABLE: UNKNOWN` is GitHub still computing — ignore it; it resolves by the next poll. `BLOCKED`/`BEHIND` etc. in the parenthesized status are not conflicts — ignore.)
  - If a poll surfaces BOTH new comments worth fixing AND a conflict, handle them in ONE cycle: merge `origin/main` first, apply the comment fixes on top, then a single re-entry from Stage 2.
  - For each new comment, triage AND **always reply on its thread** (every comment gets a response — no silent handling, so reviewers see it was considered):
    - **Worth fixing** (reviewer-requested change, real bug, test/doc gap): this is a NEW CHANGE — apply it on the feature branch and re-enter the pipeline **from Stage 2 through Stage 12** (gates → e2e on feature → integrate → dev-gates → e2e → review → QC → senior gate → push development → push/update PR → ticket update (parallel) + CI watch → **dev-QC**). The full process applies; no shortcuts because "it's just review feedback", and dev-QC is never skipped after the re-entry's development push. **After the fix is pushed, reply to the comment** confirming resolution — what changed + the commit/PR ref — by writing the reply to a file and posting `gh pr comment <pr_url> --body-file <path>` referencing the comment. **Never inline `--body "..."`** — bodies carry backticks/`file:line`/`$(...)` that bash reads as command substitution inside double quotes, which corrupts the comment and trips an approval prompt. (Use `gh pr comment`/`gh pr review`; avoid raw `gh api` for replies — those are the pre-authorized commands.) Then come back here and keep watching.
    - **Question / discussion**: answer it via `gh pr comment <pr_url> --body-file <path>` (same file-not-inline rule) — no code change.
    - **Not worth fixing** (out of scope, working as intended, deferred): **reply with the reasoning** so the reviewer knows why it wasn't actioned (don't just skip it), and note it in `notes`.
    - **Sign every reply** with a distinct attribution so humans and other agents (the pr-reviewer, other lanes) can tell which automated agent wrote it — and so you recognise your own threads on the next poll (you DO reply to / resolve your own comments; the signature is how they're told apart, not a reason to skip them). End each posted body, on its own line, with: `— 🤖 ship-feature pipeline · lane <N>`. (Post via `gh pr comment`/`gh pr review --body-file`, never inline.) Keep replies concise and specific; never leave a worth-fixing or not-fixing decision without a reply on the thread.
  - Nothing new → background another `sleep 300` (`run_in_background: true`) and end the turn; you'll be re-invoked for the next poll. A PR can sit for days — that's fine. (If you genuinely can't background the wait, hand off honestly per the waiting-primitive rule — set state with a note that the watch needs a re-trigger — rather than faking it.)
- The human can stop the watch at any time; set `stage=done status=passed` on the way out.

## Escalation
Whenever you STOP early (an ambiguous merge conflict, an unexpected/unrecoverable failure), set `status=blocked` (or `failed`) with a one-line `notes=` explaining what the human must decide — the dashboard surfaces it. Then summarize for the human and wait.
