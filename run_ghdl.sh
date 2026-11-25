#!/usr/bin/env bash
# Free, command-line verification with GHDL (no ModelSim needed).  Usage:  ./run_ghdl.sh [clock|drop|system|units|all]
# Exits non-zero on the first failing testbench.
set -euo pipefail
cd "$(dirname "$0")"
W=build; mkdir -p "$W"
S="--std=93 --workdir=$W"
RTL="stick_pkg tick_gen debounce hcsr04 obstacle_filter spi_master pattern_gen bin2bcd_seq adxl345_ctrl drop_detect display_ctrl stick_fsm blind_stick_top"
run() { # <tb> <stop-time>
  echo "=== $1 ==="; ghdl -e $S "$1"
  if ghdl -r $S "$1" --stop-time="$2" > "$W/$1.log" 2>&1; then
    grep -E "PASSED" "$W/$1.log" || { echo "!! $1 ended without a PASSED message"; exit 1; }
  else
    tail -5 "$W/$1.log"; echo "!! $1 FAILED"; exit 1
  fi
}
build_design() { for f in $RTL; do ghdl -a $S rtl/$f.vhd; done
                 ghdl -a $S sim/hcsr04_model.vhd sim/adxl345_model.vhd sim/tb_*.vhd; }
case "${1:-all}" in
  clock)  ghdl -a $S homework/digital_clock.vhd homework/tb_digital_clock.vhd; run tb_digital_clock 10us ;;
  drop)   build_design; run tb_drop_detect 10sec ;;
  system) build_design; run tb_blind_stick_top 40sec ;;
  units)  build_design; run tb_drop_detect 10sec; run tb_hcsr04 40sec; run tb_adxl345 40sec ;;
  all)    "$0" clock; "$0" units; "$0" system ;;
esac
echo "ALL REQUESTED GHDL RUNS PASSED"
