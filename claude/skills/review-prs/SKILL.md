---
name: review-prs
description: "Autonomous PR-review loop for ONE harness lane. Invoke inside a lane clone as `/review-prs`. Frontloads scope questions once, then polls the repo's open PRs on an interval and, for any that need our input — brand-new PRs, PRs with new commits since we last reviewed, or PRs with new discussion aimed at us — spawns a pr-reviewer agent to post substantive feedback (or a draft). Maintains a per-lane cursor so it never re-reviews unchanged PRs, and writes lane state + a review history the watch dashboard renders. Use when the user wants to continuously review/comment on open pull requests."
---

# Review PRs (harness lane PR-review loop)

You run an autonomous **PR-review loop** for one lane. After a short frontloaded Q&A you poll the repo's open PRs on an interval and leave useful review feedback on the ones that need our input, tracking everything in lane state so the dashboard shows progress + history. You only comment (or draft) — never merge, push, or close.

## Setup — every run

```bash
HARNESS="@@HARNESS_ROOT@@"   # populated to the real harness path when the harness is installed
N="$(cat .harness-lane 2>/dev/null)"   # lane number, read from the clone (your cwd)
export GH_TOKEN="$(gh auth token)"      # dodge keyring 401s
```
- If `.harness-lane` is missing you are NOT in a lane clone — STOP and tell the user to assign/bootstrap a lane first.
- The lane's git origin is the repo under review (`gh` auto-detects it from the clone). This loop does NOT touch the lane's own branch or stack — it's read+comment against GitHub. Running it in a lane that's also mid-`/ship-feature` is fine in principle but confusing on the dashboard; prefer a dedicated lane.
- **State is the dashboard's source of truth** — update it through `"$HARNESS/bin/state.sh" "$N" set ...` (also the heartbeat). Mark this lane as a review lane: `state.sh "$N" set mode=pr-review feature_title="PR review loop"`.

## Context recovery — after conversation compaction

The review loop runs indefinitely and will outlive the context window. When context
is compacted, re-derive these before continuing the loop:

```bash
HARNESS="@@HARNESS_ROOT@@"   # populated to the real harness path when the harness is installed
N="$(cat .harness-lane 2>/dev/null)"
```

Then recover your Stage-0 configuration:
- **Lane state**: `"$HARNESS/bin/state.sh" "$N" get` — check `mode` is `pr-review`, read `notes` for last poll summary.
- **Stage-0 answers are NOT stored in files — they were shell env vars.** If you can't remember the human's choices for `LANE_PR_INCLUDE_OWN`, `LANE_PR_INCLUDE_DRAFTS`, poll interval, post/draft mode, or verdict style, **use these defaults** rather than re-asking: `LANE_PR_INCLUDE_OWN=0` (exclude own), `LANE_PR_INCLUDE_DRAFTS=0` (skip drafts), 5-min interval, post mode, neutral `--comment` reviews. If the human set non-default values, they'll correct you.

Resume the poll loop from step 1.

## Hard rules

- **Posting PR comments is outward-facing.** Only post substantive feedback; never spam, never duplicate feedback you already gave (the pr-reviewer agent enforces idempotency by reading the existing thread). Reviews are **short and action-first** — lead with what must change, and keep agreed/already-resolved points to a one-line acknowledgement (the pr-reviewer agent owns the exact style). Honor the Stage-0 `post` vs `draft` choice.
- **Never** merge, push, close, re-open, or change labels/assignees. Reviewing only.
- **One pr-reviewer per PR**, sequentially — keep each review focused and the dashboard legible.
- Keep the cursor honest: `mark` a PR only AFTER its review/response is posted (so a crash mid-review re-surfaces it next poll, never silently skips).
- Heartbeat on every poll iteration so the dashboard doesn't flag the lane stalled.

## Stage 0 — Intake & frontloaded Q&A  *(the only interactive stage)*

Ask the human, in one batch:
- **Scope**: all open PRs, or only others' PRs (exclude your own), or a label/author filter? (default: exclude your own — `LANE_PR_INCLUDE_OWN=1` to include; `LANE_PR_INCLUDE_DRAFTS=1` for drafts.)
- **Poll interval** (default 5 min).
- **Post or draft**: publish reviews directly, or save drafts for your approval? (default: post.)
- **Verdict style**: neutral `--comment` reviews (default), or may the reviewer use approve / request-changes?
- **Review depth / focus**: anything to emphasize (security, tests, a subsystem)?
Then announce "Going autonomous — watching open PRs." Activate per-feature state tracking: `"$HARNESS/bin/state.sh" "$N" activate "pr-review"`. Then set `state.sh "$N" set mode=pr-review feature_title="PR review loop" stage=polling status=running`.

## The loop

Repeat until the human stops it:

1. `state.sh "$N" set stage=polling` (heartbeat). Run the poll:
   `LANE_PR_INCLUDE_OWN=<0|1> LANE_PR_INCLUDE_DRAFTS=<0|1> "$HARNESS/bin/lane-pr-poll.sh" "$N" list`
   It prints `PR_POLL: <open> open · <k> need review · <r> ready to merge · <a> awaiting your decision` then one line per PR: `CLASS  #PR  HEAD_SHA  AUTHOR  REVIEW  CI  MERGE_ACTION  TITLE`. `MERGE_ACTION` is `ready` (mergeable now), `awaiting` (our review done + CI green, needs the human to approve/merge), or `-`. The poll also **auto-writes a `needs_action` field to lane state** from these — the dashboard shows a "🙋 needs you" badge so the human knows a PR is theirs to merge. **You never merge** — just keep it surfaced. Don't set `needs_action` yourself; the poll owns it.
2. For each PR classed `NEW`, `UPDATED`, or `TOUCHED` (skip `UPTODATE`):
   - `state.sh "$N" set stage="reviewing #<pr>"`.
   - Spawn the **pr-reviewer** agent (Agent tool, `subagent_type: pr-reviewer`). Give it: lane N + clone path, the PR number, its classification, and the mode (`post`/`draft`) + verdict style from Stage 0.
   - Parse its last line `PR-REVIEW: #<pr> <ACTION> — <summary>`.
   - Record it: `"$HARNESS/bin/lane-pr-poll.sh" "$N" log <pr> <action> "<summary>"` then `"$HARNESS/bin/lane-pr-poll.sh" "$N" mark <pr>` (snapshot its current state so it won't re-surface until it changes again). On `ERROR`, log it but do NOT mark (so it retries next poll).
3. After the batch: `state.sh "$N" set stage=idle notes="watching <open> open PRs; reviewed <k> this cycle; last poll <time>"`.
4. Wait the interval **in the background** so the turn isn't pinned: run `sleep 300` (or your chosen interval) with `run_in_background: true` — the harness re-invokes you when it exits — then go to 1. Do NOT foreground-`sleep` (the Bash tool blocks it) or use `ScheduleWakeup` (a `/loop`-only primitive — this is not a `/loop` session). If you can't background the wait, set lane state with an honest note and STOP rather than narrating a poll loop you aren't running. **Heartbeat each iteration** even when nothing changed.

## Stop / escalate

- The human can stop the loop anytime; on the way out set `state.sh "$N" set stage=stopped status=idle notes="review loop stopped"`.
- If `gh` auth fails or the repo is unreachable, set `status=blocked notes="<reason>"` and STOP — don't spin.

## Dashboard

The watch dashboard renders review lanes specially (mode `pr-review`): the panel shows the recent review history (PR #, action, when, summary — each event from `lane-pr-poll.sh log`) instead of the ship-feature pipeline map, plus the current `stage` (`polling` / `reviewing #N` / `idle`) and `notes`. Keep `stage`/`notes` current so the human can watch progress at a glance.
