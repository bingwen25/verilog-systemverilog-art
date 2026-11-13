#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build logs
iverilog_bin=${IVERILOG:-iverilog}
vvp_bin=${VVP:-vvp}
args=()
if [[ -n ${IVERILOG_BACKEND:-} ]]; then
  args+=("-B${IVERILOG_BACKEND%/}/")
elif [[ "$iverilog_bin" == */* ]]; then
  backend="$(dirname "$iverilog_bin")/../lib/x86_64-linux-gnu/ivl"
  if [[ -d "$backend" ]]; then args+=("-B${backend%/}/"); fi
fi
"$iverilog_bin" "${args[@]}" -g2012 -Wall -s part_select_tb -o build/part_select.vvp part_select_tb.sv
"$vvp_bin" build/part_select.vvp
