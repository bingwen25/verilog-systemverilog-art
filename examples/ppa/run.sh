#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build logs

iverilog_bin=${IVERILOG:-}
vvp_bin=${VVP:-}
if [[ -z "$iverilog_bin" ]]; then
  if command -v iverilog >/dev/null 2>&1; then
    iverilog_bin=$(command -v iverilog)
  elif [[ -x ../build/iverilog-root/usr/bin/iverilog ]]; then
    iverilog_bin=../build/iverilog-root/usr/bin/iverilog
  elif [[ -x tools/iverilog/root/usr/bin/iverilog ]]; then
    iverilog_bin=tools/iverilog/root/usr/bin/iverilog
  else
    echo 'ERROR: set IVERILOG and VVP or provide Icarus Verilog.' >&2
    exit 127
  fi
fi
if [[ -z "$vvp_bin" ]]; then
  if command -v vvp >/dev/null 2>&1; then
    vvp_bin=$(command -v vvp)
  elif [[ -x tools/iverilog/root/usr/bin/vvp ]]; then
    vvp_bin=tools/iverilog/root/usr/bin/vvp
  else
    vvp_bin="$(dirname "$iverilog_bin")/vvp"
  fi
fi

ivl_args=()
if [[ -n ${IVERILOG_BACKEND:-} ]]; then
  ivl_args+=("-B${IVERILOG_BACKEND%/}/")
elif [[ "$iverilog_bin" == */* ]]; then
  backend="$(dirname "$iverilog_bin")/../lib/x86_64-linux-gnu/ivl"
  if [[ -d "$backend" ]]; then
    ivl_args+=("-B${backend%/}/")
  elif [[ -d tools/iverilog/root/usr/lib/x86_64-linux-gnu/ivl ]]; then
    ivl_args+=("-Btools/iverilog/root/usr/lib/x86_64-linux-gnu/ivl/")
  fi
elif [[ -d tools/iverilog/root/usr/lib/x86_64-linux-gnu/ivl ]]; then
  ivl_args+=("-Btools/iverilog/root/usr/lib/x86_64-linux-gnu/ivl/")
fi

printf 'Icarus: %s\n' "$iverilog_bin" > logs/tool-versions.log
"$iverilog_bin" "${ivl_args[@]}" -V >> logs/tool-versions.log 2>&1 || true
printf 'VVP: %s\n' "$vvp_bin" >> logs/tool-versions.log
"$vvp_bin" -V >> logs/tool-versions.log 2>&1 || true

"$iverilog_bin" "${ivl_args[@]}" -g2012 -Wall -s tb_add4 \
  -o build/tb_add4.vvp add4_baseline.sv add4_pipeline.sv tb_add4.sv \
  > logs/iverilog.log 2>&1
"$vvp_bin" build/tb_add4.vvp >> logs/iverilog.log 2>&1

yosys_bin=${YOSYS:-}
if [[ -z "$yosys_bin" ]]; then
  if command -v yosys >/dev/null 2>&1; then
    yosys_bin=$(command -v yosys)
  elif command -v yowasp-yosys >/dev/null 2>&1; then
    yosys_bin=$(command -v yowasp-yosys)
  else
    echo 'ERROR: install Yosys (apt), pip install yowasp-yosys, or set YOSYS.' >&2
    exit 127
  fi
fi

"$yosys_bin" --version > logs/yosys-version.log 2>&1
"$yosys_bin" -p "read_verilog -sv add4_baseline.sv; synth -noabc -top add4_baseline; stat" \
  > logs/yosys-baseline.log 2>&1
"$yosys_bin" -p "read_verilog -sv add4_pipeline.sv; synth -noabc -top add4_pipeline; stat" \
  > logs/yosys-pipeline.log 2>&1
printf '%s\n' \
  'iverilog -g2012 -Wall -s tb_add4 -o build/tb_add4.vvp add4_baseline.sv add4_pipeline.sv tb_add4.sv' \
  'vvp build/tb_add4.vvp' \
  'yosys -p "read_verilog -sv add4_baseline.sv; synth -noabc -top add4_baseline; stat"' \
  'yosys -p "read_verilog -sv add4_pipeline.sv; synth -noabc -top add4_pipeline; stat"' \
  > logs/commands.log

echo 'PASS: simulation and generic synthesis completed. See logs/.'
