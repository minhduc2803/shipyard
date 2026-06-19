#!/usr/bin/env bash
# Give a lane the same MCP servers as the source project (SOURCE_REPO).
# Root cause this fixes: the playwright/* MCPs are registered LOCAL-scope for
# the source project in ~/.claude.json, so lane sessions get none.
#
# What it does (per lane):
#   1. Reads the source project's mcpServers from ~/.claude.json (read-only).
#   2. Rewrites any absolute path under the source repo -> the lane's path
#      (per-lane Chromium profiles; shared profiles would SingletonLock-collide).
#   3. Seeds the lane's .playwright-mcp/profiles/* by copying the source
#      profiles once (preserves tracker/dev-site logins), dropping Singleton*.
#   4. Writes <lane>/.mcp.json (project-scope MCP config, read at session start).
#   5. Writes lane-scoped permission allow-rules into
#      <lane>/.claude/settings.local.json: enableAllProjectMcpServers + an
#      `mcp__<server>` allow rule for every synced server's tools, the GitHub PR
#      flow (comment/review/create/edit/view/diff/list/api/auth), and git push —
#      so autonomous lane sessions don't stop for approvals (never merge/close).
#      Plus a NARROW auto-mode `allow` rule (a separate classifier layer) so the
#      ticketer / pr-reviewer sub-agents can do their ONE configured external write
#      (file a ticket / post a review) unattended — the ticket rule only when
#      TRACKER_ENABLED=1. Not mode:bypassPermissions (the classifier flags that).
#   6. Excludes .mcp.json from git via .git/info/exclude.
# Re-runnable. New/changed servers re-sync; existing lane profiles are kept.
#   lane-mcp-sync.sh <N> | --all
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

sync_lane() {
  local N="$1" DIR
  DIR="$(lane_dir "$N")"
  [ -d "$DIR/.git" ] || die "lane $N not bootstrapped"

  # Converge proof onto .playwright-mcp/proof (symlink the clone-root proof/) so QC
  # shots + the ticket report can't strand in the wrong root; migrates any existing
  # real proof/ dir into the canonical root first. Fixes the dashboard 🎫/gallery
  # for lanes that wrote proof before this was in place.
  ensure_proof_link "$DIR"

  SOURCE_REPO="$SOURCE_REPO" LANE_DIR="$DIR" HARNESS_ROOT="$HARNESS_ROOT" TRACKER_ENABLED="${TRACKER_ENABLED:-0}" python3 <<'PY'
import json, os, sys

src_repo = os.environ["SOURCE_REPO"]
lane_dir = os.environ["LANE_DIR"]
cfg = json.load(open(os.path.expanduser("~/.claude.json")))
servers = (cfg.get("projects", {}).get(src_repo, {}) or {}).get("mcpServers") or {}
if not servers:
    sys.exit(f"no mcpServers found for source project {src_repo} in ~/.claude.json")

def relocate(v):
    if isinstance(v, str):
        return v.replace(src_repo, lane_dir)
    if isinstance(v, list):
        return [relocate(x) for x in v]
    if isinstance(v, dict):
        return {k: relocate(x) for k, x in v.items()}
    return v

out = {"mcpServers": relocate(servers)}

# Route npx/node servers through the spawn-time Node resolver. A Claude session
# spawns stdio MCPs with its inherited PATH, where nvm may resolve node to an
# ancient version (v12 broke @playwright/mcp) — and npx's `#!/usr/bin/env node`
# shebang re-resolves node from PATH even when npx is called by absolute path.
# The wrapper picks the newest Node >= 18 at exec time, so .mcp.json survives
# node upgrades (a version-pinned absolute path would go stale).
wrapper = os.path.join(os.environ["HARNESS_ROOT"], "bin", "mcp-node-exec.sh")
for name, srv in out["mcpServers"].items():
    cmd = srv.get("command")
    if not isinstance(cmd, str):
        continue
    base = os.path.basename(cmd)
    if base in ("npx", "node") or base == "mcp-node-exec.sh":
        args = srv.get("args") or []
        if base == "mcp-node-exec.sh":          # re-sync of an already-wrapped config
            base, args = (args[0], args[1:]) if args else ("npx", [])
        srv["command"] = wrapper
        srv["args"] = [base] + args
        env = {k: v for k, v in (srv.get("env") or {}).items() if k != "PATH"}
        if env:
            srv["env"] = env       # wrapper owns PATH; keep any other vars
        else:
            srv.pop("env", None)

# Pin the output dir so relative screenshot filenames (proof/<feature>/...)
# always land in <lane>/.playwright-mcp — where the dashboard's proof gallery
# looks — instead of resolving against whatever cwd the server was spawned with.
for name, srv in out["mcpServers"].items():
    args = srv.get("args") or []
    if any(isinstance(a, str) and a.startswith("@playwright/mcp") for a in args) \
       and "--output-dir" not in args:
        srv["args"] = args + ["--output-dir", os.path.join(lane_dir, ".playwright-mcp")]

path = os.path.join(lane_dir, ".mcp.json")
json.dump(out, open(path, "w"), indent=2)
print(f"  wrote {path} ({', '.join(sorted(out['mcpServers']))})")

# auto-enable project-scope servers (no approval prompt)
sdir = os.path.join(lane_dir, ".claude")
os.makedirs(sdir, exist_ok=True)
spath = os.path.join(sdir, "settings.local.json")
settings = {}
if os.path.exists(spath):
    try: settings = json.load(open(spath))
    except Exception: settings = {}
settings["enableAllProjectMcpServers"] = True
# Lane-scoped permission allow-rules so THIS lane's autonomous sessions run the
# harness workflows without manual approvals. Scoped to the lane (never global
# ~/.claude); guardrails stay ON (deny rules + dangerous-command gating still
# apply) — we only allow the specific tool families lanes actually use.
perms = settings.setdefault("permissions", {})
allow = perms.setdefault("allow", [])
rules = []
# (a) Every MCP server we just synced -> allow ALL its tools. The server-scoped
#     rule `mcp__<name>` covers every tool call; enableAllProjectMcpServers only
#     LOADS the servers, it does NOT auto-approve their tool CALLS (that gap is
#     why playwright/* still prompted).
rules += [f"mcp__{name}" for name in sorted(out["mcpServers"])]
# (b) GitHub PR flow: post (comment/review), open/update (create/edit), read
#     (view/diff/list/checks/status), plus api + auth token — the setup line
#     `export GH_TOKEN="$(gh auth token)"` is a command-substitution that itself
#     needs approval. NEVER merge/close — the human merges.
rules += [
    "Bash(gh pr comment:*)", "Bash(gh pr review:*)",
    "Bash(gh pr create:*)", "Bash(gh pr edit:*)",
    "Bash(gh pr view:*)", "Bash(gh pr diff:*)", "Bash(gh pr list:*)",
    "Bash(gh pr checks:*)", "Bash(gh pr status:*)",
    "Bash(gh api:*)", "Bash(gh auth token)", "Bash(gh auth token:*)",
]
# (c) Push the feature branch (PRs come from lane branches). Read-only git is
#     already auto-allowed; push is the call that prompts.
rules += ["Bash(git push:*)"]
for rule in rules:
    if rule not in allow:
        allow.append(rule)

# Auto-mode classifier (a SEPARATE layer from permissions.allow above): a NARROW
# allow-rule so the harness's own ticketer / pr-reviewer sub-agents can do their one
# CONFIGURED external write unattended. The classifier's "External System Writes" is a
# soft_deny (it would ASK) — and a background agent can't be asked, so it HARD-blocks;
# mcp__ allow-rules don't help because the gate judges the SPAWN's intent, not the
# child's tool calls. This is the user pre-authorizing exactly the configured pipeline
# write (same spirit as the gh-pr rules above), scoped to those two agents + actions.
# NOT mode:bypassPermissions — that's the classifier's own "Create Unsafe Agents" /
# "Auto-Mode Bypass" pattern and far too broad.
am_allow = settings.setdefault("autoMode", {}).setdefault("allow", [])
am_rules = [
    "Harness PR review feedback: the parallel-feature-harness `pr-reviewer` sub-agent "
    "posting review comments / a review on ONE open PR for the user-invoked `/review-prs` "
    "loop — the explicit configured purpose of that command, not unrequested publishing. "
    "Excludes merging, closing, or resolving/deleting others' items.",
]
if os.environ.get("TRACKER_ENABLED") == "1":
    am_rules.append(
        "Harness tracker ticket: the parallel-feature-harness `ticketer` sub-agent creating "
        "or updating exactly ONE issue/ticket in the configured tracker for the feature shipped "
        "by the user-invoked `/ship-feature` (TRACKER_ENABLED=1) — the explicit configured "
        "purpose of that pipeline step, not unrequested publishing. Excludes deleting/closing/"
        "resolving any ticket and any write beyond that one ticket."
    )
for rule in am_rules:
    if rule not in am_allow:
        am_allow.append(rule)

json.dump(settings, open(spath, "w"), indent=2)
print(f"  enabled project MCP servers + lane workflow + auto-mode allow rules in {spath}")
PY

  # Seed per-lane Chromium profiles from the source ones (keeps logins).
  local sprof="$SOURCE_REPO/.playwright-mcp/profiles" lprof="$DIR/.playwright-mcp/profiles"
  if [ -d "$sprof" ]; then
    mkdir -p "$lprof"
    local p name
    for p in "$sprof"/*/; do
      [ -d "$p" ] || continue
      name="$(basename "$p")"
      if [ ! -d "$lprof/$name" ]; then
        echo "  seeding profile '$name' (copies login session) ..."
        cp -R "$p" "$lprof/$name"
        rm -f "$lprof/$name"/Singleton* 2>/dev/null || true
      fi
    done
  fi

  grep -qxF ".mcp.json" "$DIR/.git/info/exclude" 2>/dev/null || echo ".mcp.json" >> "$DIR/.git/info/exclude"
  echo "harness: lane $N MCP sync done (restart the lane's Claude session to load)."
}

if [ "${1:-}" == "--all" ]; then
  for n in $(discover_lanes); do echo "— lane $n:"; sync_lane "$n"; done
else
  require_lane "${1:-}"
  sync_lane "$1"
fi
