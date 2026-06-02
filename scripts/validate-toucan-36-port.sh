#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

require_absent_path() {
  [[ ! -e "$1" ]] || fail "unexpected option-2 artifact remains: $1"
}

require_file build.yaml
require_file config/west.yml
require_file boards/shields/toucan/toucan.zmk.yml
require_file boards/shields/toucan/toucan.dtsi
require_file config/toucan.keymap
require_file config/toucan.json

grep -q 'toucan_left rgbled_adapter nice_view_gem' build.yaml || fail "build.yaml does not build stock toucan_left with display"
grep -q 'toucan_right rgbled_adapter' build.yaml || fail "build.yaml does not build stock toucan_right"
! grep -q 'toucan_36' build.yaml || fail "build.yaml still references toucan_36"
grep -q 'name: zmk-helpers' config/west.yml || fail "config/west.yml missing zmk-helpers"

require_absent_path boards/shields/toucan_36
require_absent_path config/toucan_36.keymap
require_absent_path config/toucan_36.json

json_positions="$(grep -c '"x":' config/toucan.json)"
[[ "$json_positions" -eq 42 ]] || fail "config/toucan.json has $json_positions positions, expected stock 42"

dtsi_positions="$(grep -c 'key_physical_attrs' boards/shields/toucan/toucan.dtsi)"
[[ "$dtsi_positions" -eq 42 ]] || fail "toucan.dtsi has $dtsi_positions physical positions, expected stock 42"

python3 - <<'PY'
from pathlib import Path
import re
import sys

keymap = Path("config/toucan.keymap").read_text()
layers = re.findall(r'^\s*(\w+_layer)\s*\{[^{}]*?bindings = <(.*?)^\s*>;', keymap, re.S | re.M)
expected = ["base_layer", "symbols_layer", "navigation_layer", "numpad_layer", "func_layer"]
found = [name for name, _ in layers]
if found != expected:
    print(f"FAIL: layer order/names are {found}, expected {expected}", file=sys.stderr)
    sys.exit(1)

def binding_tokens(body: str) -> list[str]:
    tokens = []
    for raw in body.splitlines():
        line = raw.split("//", 1)[0].strip()
        if line:
            parts = line.split()
            for index, token in enumerate(parts):
                if token.startswith("&"):
                    tokens.append(" ".join(parts[index:index + 4]))
    return tokens

def binding_count(body: str) -> int:
    return sum(1 for token in binding_tokens(body) if token.startswith("&"))

for name, body in layers:
    count = binding_count(body)
    if count != 42:
        print(f"FAIL: {name} has {count} bindings, expected 42", file=sys.stderr)
        sys.exit(1)

base_body = dict(layers)["base_layer"]
base_bindings = [token.split()[0] for token in binding_tokens(base_body)]
for position in [0, 11, 12, 23, 24, 35]:
    if base_bindings[position] != "&none":
        print(f"FAIL: base position {position} should be &none for Toucan 36", file=sys.stderr)
        sys.exit(1)

compact = " ".join(
    " ".join(line.split("//", 1)[0].split())
    for line in base_body.splitlines()
)
expected_thumb = "&kp ESC &mo SYMB &lt NUMP TAB &kp LSHFT &mo NAV &kp SPACE"
if expected_thumb not in compact:
    print("FAIL: base layer thumb row does not match selected mapping", file=sys.stderr)
    sys.exit(1)

required = [
    "#define LT0 1",
    "#define RT4 10",
    "#define NUMP 3",
    "#define FUNC 4",
    "#define LM0 13",
    "#define RM4 22",
    "#define LB0 25",
    "#define RB4 34",
    "#define LH2 36",
    "#define RH2 41",
    "td_comma_semi: tap_dance_comma_semi",
    "td_dot_colon: tap_dance_dot_colon",
]
for needle in required:
    if needle not in keymap:
        print(f"FAIL: missing {needle}", file=sys.stderr)
        sys.exit(1)
PY

printf 'PASS: stock toucan shield Toucan 36 port validation passed\n'
