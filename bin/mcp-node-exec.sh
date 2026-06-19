#!/usr/bin/env bash
# Spawn-time Node resolver for stdio MCP servers (the `command` in .mcp.json).
#
# Why this exists: Claude spawns stdio MCPs with the session's inherited PATH,
# where nvm may resolve `node` to an ancient version (v12 broke @playwright/mcp:
# "Unexpected token '.'"). Pinning an absolute npx path is NOT enough — npx's
# `#!/usr/bin/env node` shebang re-resolves `node` from PATH — and a pinned
# version dir (e.g. .../v22.22.2/bin) goes stale on the next nvm upgrade.
# So: resolve the newest installed Node >= MIN at EXEC time, force it onto
# PATH, then exec. .mcp.json never goes stale across node upgrades.
#
#   mcp-node-exec.sh npx|node <args...>
set -euo pipefail
MIN_NODE="${MCP_MIN_NODE:-18}"
BIN="${1:?usage: mcp-node-exec.sh npx|node <args...>}"; shift
case "$BIN" in npx|node) ;; *) echo "mcp-node-exec: refusing to exec '$BIN' (only npx|node)" >&2; exit 1;; esac

best_dir="" best_ver=""
for d in "$HOME"/.nvm/versions/node/*/bin /opt/homebrew/bin /usr/local/bin; do
  [ -x "$d/node" ] && [ -x "$d/$BIN" ] || continue
  v="$("$d/node" --version 2>/dev/null || true)"; v="${v#v}"
  major="${v%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] && [ "$major" -ge "$MIN_NODE" ] || continue
  if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$v" | sort -V | tail -1)" = "$v" ]; then
    best_ver="$v" best_dir="$d"
  fi
done

[ -n "$best_dir" ] || {
  echo "mcp-node-exec: no Node >= v$MIN_NODE found (looked in ~/.nvm/versions/node/*/bin, /opt/homebrew/bin, /usr/local/bin). Install one: nvm install 22" >&2
  exit 1
}

export PATH="$best_dir:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec "$best_dir/$BIN" "$@"
