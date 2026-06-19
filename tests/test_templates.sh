#!/usr/bin/env bash
# Source skills/agents must stay PROJECT-AGNOSTIC: no hardcoded home/project path
# in the templates. The harness path is the @@HARNESS_ROOT@@ placeholder, baked
# in only at install time; lane paths are resolved at runtime ($(pwd)).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SK="$REPO/claude/skills"; AG="$REPO/claude/agents"

# 1) no hardcoded project path anywhere in the source templates
hits="$(grep -rnE '\$HOME/clinical|~/clinical' "$SK" "$AG" || true)"
assert_eq "" "$hits" "no hardcoded ~/clinical or \$HOME/clinical in skill/agent sources"

# 1b) no project literal — the word "clinical" or the profile's configured MCP
#     server names — except the profiles/clinical reference path harness-adapt
#     legitimately cites. (Design success criterion: no clinical literal in skills.)
clin="$(grep -rniE 'clinical|east[ -]?agile|playwright-qa-dev|playwright-ticketer' "$SK" "$AG" | grep -v 'profiles/clinical' || true)"
assert_eq "" "$clin" "no clinical / East-Agile / configured-MCP literal in sources (profiles/clinical refs allowed)"

# 1c) no APP-TOOLCHAIN tool name in the pipeline skill or the agents. These files
#     are copied verbatim into every adopter's project, so naming clinical's stack
#     tools (pytest / pnpm / openapi-check / build:check / uv / …) misleads an
#     adopter on a different stack. harness-adapt is EXEMPT — enumerating a repo's
#     lockfiles/tools to infer the stack is exactly that skill's job.
tool="$(grep -rniE 'pytest|pnpm|openapi-check|build:check|poetry|\balembic\b|\byarn\b|\buv\b' "$SK" "$AG" | grep -v '/harness-adapt/' || true)"
assert_eq "" "$tool" "no app-toolchain tool name in pipeline skill/agents (harness-adapt exempt)"

# 2) every HARNESS= assignment in the sources uses the placeholder (never a literal)
bad="$(grep -rn 'HARNESS=' "$SK" "$AG" | grep -v '@@HARNESS_ROOT@@' || true)"
assert_eq "" "$bad" "every HARNESS= in sources uses the @@HARNESS_ROOT@@ placeholder"

# 3) the placeholder is actually present, so install has something to populate
assert_ne "" "$(grep -rl '@@HARNESS_ROOT@@' "$SK" "$AG" || true)" "@@HARNESS_ROOT@@ placeholder present in sources"

# 4) the installer's substitution leaves no token behind and bakes the real path
rendered="$(sed "s|@@HARNESS_ROOT@@|/tmp/some/harness|g" "$SK/ship-feature/SKILL.md")"
case "$rendered" in *@@HARNESS_ROOT@@*) tok=remained;; *) tok=gone;; esac
assert_eq "gone" "$tok" "render leaves no @@HARNESS_ROOT@@ token behind"
case "$rendered" in *'HARNESS="/tmp/some/harness"'*) baked=yes;; *) baked=no;; esac
assert_eq "yes" "$baked" "render bakes the real harness path into HARNESS="

# 5) stack/provider lore is parameterized: agents read it via profile-cat.sh, and
#    the clinical reference profile actually provides those notes.
assert_ne "" "$(grep -rl 'profile-cat.sh' "$SK" "$AG" || true)" "agents read stack lore via profile-cat.sh"
[ -s "$REPO/profiles/clinical/review-checks.md" ] && r=ok || r=missing
assert_eq "ok" "$r" "profiles/clinical/review-checks.md provides clinical's review checks"
[ -s "$REPO/profiles/clinical/tracker-notes.md" ] && t=ok || t=missing
assert_eq "ok" "$t" "profiles/clinical/tracker-notes.md provides clinical's provider notes"

finish
