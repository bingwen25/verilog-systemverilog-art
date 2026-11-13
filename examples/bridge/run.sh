#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../build ../logs

iverilog_bin=${IVERILOG:-iverilog}
vvp_bin=${VVP:-vvp}
if ! command -v "$iverilog_bin" >/dev/null 2>&1 || ! command -v "$vvp_bin" >/dev/null 2>&1; then
  printf '%s\n' 'ERROR: iverilog and vvp are required; install Icarus Verilog or set IVERILOG and VVP.' | tee ../logs/bridge-iverilog.log >&2
  exit 127
fi

iverilog_args=()
if [[ -n ${IVERILOG_BACKEND:-} ]]; then
  iverilog_args+=("-B${IVERILOG_BACKEND%/}/")
elif [[ "$iverilog_bin" == */* ]]; then
  extracted_backend="$(dirname "$iverilog_bin")/../lib/x86_64-linux-gnu/ivl"
  if [[ -d "$extracted_backend" ]]; then
    iverilog_args+=("-B${extracted_backend%/}/")
  fi
fi

"$iverilog_bin" "${iverilog_args[@]}" -g2012 -Wall -s tb_axi4lite_csr \
  -o ../build/tb_axi4lite_csr.vvp axi4lite_csr.sv tb_axi4lite_csr.sv
"$vvp_bin" ../build/tb_axi4lite_csr.vvp
