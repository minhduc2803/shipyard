#!/usr/bin/env bash
# Copy the harness's version-controlled Claude assets into ~/.claude so every lane
# session picks them up, populating install-time placeholders as it goes (render()
# below). Everything installed here lives IN this repo (harness/claude/) — nothing
# depends on the source repo — so the harness is self-contained and portable: clone
# the repo, run this, done. Re-runnable — and you MUST re-run it after editing a
# source skill/agent, because these are COPIES (not symlinks) and won't auto-update.
#
# Bundled skills:  /ship-feature, /review-prs, /harness-adapt
# Bundled agents:  senior-gate-reviewer, qc-local, dev-qc, ticketer, pr-reviewer
#
# Also auto-installs the superpowers plugin at the tail (the skills lean on it:
# brainstorming/writing-plans/test-driven-development/systematic-debugging/
# receiving-code-review). code-review is a BUILT-IN Claude Code skill — no install.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"
SRC="$HARNESS_ROOT/claude"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents"

# Install = COPY + populate the install-time placeholder (not symlink), so the
# project-agnostic source templates become concrete only once installed. The one
# token is @@HARNESS_ROOT@@ -> this harness checkout (the single source of truth
# for the harness path). Lane paths stay runtime — the skills use $(pwd); nothing
# bakes a project path into the source. Re-run this after editing a source
# skill/agent to refresh the installed copies.
# Populate install-time placeholders from harness + active-profile config, so the
# version-controlled templates carry NO project literal. @@HARNESS_ROOT@@ = this
# checkout; @@DEV_QC_MCP@@/@@TRACKER_MCP@@ = the profile's scoped MCP server names
# (DEV_QC_MCP/TRACKER_MCP from integrations.env; empty when that integration is off).
render() {
  sed -e "s|@@HARNESS_ROOT@@|$HARNESS_ROOT|g" \
      -e "s|@@DEV_QC_MCP@@|${DEV_QC_MCP:-}|g" \
      -e "s|@@TRACKER_MCP@@|${TRACKER_MCP:-}|g" "$1"
}

for s in "$SRC"/skills/*/SKILL.md; do
  [ -f "$s" ] || continue
  name="$(basename "$(dirname "$s")")"
  mkdir -p "$HOME/.claude/skills/$name"
  dest="$HOME/.claude/skills/$name/SKILL.md"
  rm -f "$dest"                # MUST drop any prior symlink first, else the redirect writes THROUGH it into the source
  render "$s" > "$dest"
  echo "harness: installed harness skill /$name"
done
for a in "$SRC"/agents/*.md; do
  [ -f "$a" ] || continue
  dest="$HOME/.claude/agents/$(basename "$a")"
  rm -f "$dest"               # drop prior symlink before writing the rendered copy
  render "$a" > "$dest"
  echo "harness: installed harness agent $(basename "$a")"
done
echo "harness: installed $(ls "$SRC"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ') skills + $(ls "$SRC"/agents/*.md 2>/dev/null | wc -l | tr -d ' ') agents into ~/.claude (paths populated at install; self-contained)"

# Recommended plugin: superpowers (brainstorming, writing-plans, test-driven-
# development, systematic-debugging, receiving-code-review) — the ship-feature /
# review-prs skills lean on it. Auto-install (idempotent, non-interactive) if the
# `claude` CLI is present; the pipeline still runs without it, just with less
# specialized help. NOTE: `code-review` is a BUILT-IN Claude Code skill — nothing
# to install for that one.
if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -qi 'superpowers'; then
    echo "harness: superpowers plugin already installed ✓"
  else
    echo "harness: installing the superpowers plugin (recommended) …"
    claude plugin install superpowers@claude-plugins-official 2>&1 | sed 's/^/  /' \
      || echo "harness: WARNING — superpowers auto-install failed; install it yourself: claude plugin install superpowers@claude-plugins-official (optional — pipeline still runs)"
  fi
else
  echo "harness: NOTE — 'claude' CLI not on PATH; for the full experience install the superpowers plugin: claude plugin install superpowers@claude-plugins-official"
fi
