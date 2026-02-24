#!/usr/bin/env bash
set -euo pipefail

if command -v lua >/dev/null 2>&1; then
  LUA_BIN="$(command -v lua)"
elif command -v lua5.4 >/dev/null 2>&1; then
  LUA_BIN="$(command -v lua5.4)"
elif command -v luajit >/dev/null 2>&1; then
  LUA_BIN="$(command -v luajit)"
else
  echo "No Lua runtime found. Install lua5.4 (Ubuntu: sudo apt-get install -y lua5.4)." >&2
  exit 1
fi

echo "Using Lua runtime: $LUA_BIN"

# Syntax-check all lua sources in the repository.
while IFS= read -r file; do
  "$LUA_BIN" -e "assert(loadfile('$file'))"
done < <(rg --files -g '*.lua')

echo "Lua syntax check passed."
