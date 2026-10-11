#!/usr/bin/env bash
# Runs every automated check for TOASTER.
# Needs: luau (CLI), python3; optional: luau-lsp + Roblox definitions, stylua, rojo.
set -euo pipefail
cd "$(dirname "$0")/.."

LUAU="${LUAU:-luau}"
echo "== unit tests"
"$LUAU" tests/run.luau

echo "== headless gameplay simulation"
python3 tests/harness/build.py >/dev/null
"$LUAU" tests/harness/simulate.luau | tail -n 4

if command -v stylua >/dev/null; then
	echo "== formatting"
	stylua --check src tests/run.luau tests/harness/RobloxMock.luau tests/harness/simulate.luau && echo "ok"
fi

if command -v luau-lsp >/dev/null && [ -n "${ROBLOX_DEFS:-}" ]; then
	echo "== type check"
	rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts >/dev/null
	luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox="$ROBLOX_DEFS" src
fi

if command -v rojo >/dev/null; then
	echo "== place file"
	rojo build default.project.json -o build/Toaster.rbxlx
fi
