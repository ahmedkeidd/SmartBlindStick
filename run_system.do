# ModelSim script: full SYSTEM simulation of the Smart Blind Stick.
# Run from the sim/ folder:   do run_system.do
# (CLK_HZ is 1 MHz in the testbench so the ~15.4 s scenario simulates in minutes, not hours;
#  every time constant in the design scales with CLK_HZ.)
quit -sim
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work

# ---- design (compile order matters: package first) ----
foreach f {stick_pkg tick_gen debounce hcsr04 obstacle_filter spi_master pattern_gen
           bin2bcd_seq adxl345_ctrl drop_detect display_ctrl stick_fsm blind_stick_top} {
  vcom -93 -work work ../rtl/$f.vhd
}
# ---- simulation-only models + testbench ----
vcom -93 -work work hcsr04_model.vhd
vcom -93 -work work adxl345_model.vhd
vcom -93 -work work tb_blind_stick_top.vhd

# -t ps : 1 us clock period and 58 us/cm echo resolution need at least ps resolution
vsim -t ps -voptargs=+acc -gCLK_HZ=1000000 work.tb_blind_stick_top

# ---- waves ----
add wave -divider {INPUTS (switches / keys)}
add wave -label SW5_ON      /tb_blind_stick_top/SW(5)
add wave -label SW2_1_thr   {/tb_blind_stick_top/SW(2 downto 1)}
add wave -label KEY0_recover /tb_blind_stick_top/KEY(0)
add wave -label KEY1_reset   /tb_blind_stick_top/KEY(1)
add wave -divider {WORLD (testbench stimulus)}
add wave -radix unsigned -label obstacle_cm /tb_blind_stick_top/target_cm
add wave -radix decimal  -label accel_x     /tb_blind_stick_top/ax
add wave -radix decimal  -label accel_y     /tb_blind_stick_top/ay
add wave -radix decimal  -label accel_z     /tb_blind_stick_top/az
add wave -divider {FSM}
add wave -label STATE /tb_blind_stick_top/dut/state
add wave -divider {OUTPUTS}
add wave -label LED_ON   /tb_blind_stick_top/LED_ON
add wave -label LED_OBST /tb_blind_stick_top/LED_OBST
add wave -label LED_DROP /tb_blind_stick_top/LED_DROP
add wave -label BUZZER   /tb_blind_stick_top/BUZZER
add wave -label MOTOR    /tb_blind_stick_top/MOTOR
add wave -radix hex -label {7seg HEX5..HEX0 (42b)} /tb_blind_stick_top/hexbus
add wave -divider {SENSOR BUSES}
add wave -label US_TRIG /tb_blind_stick_top/US_TRIG
add wave -label US_ECHO /tb_blind_stick_top/US_ECHO
add wave -radix unsigned -label dist_cm /tb_blind_stick_top/dut/dist_cm
add wave -label obstacle /tb_blind_stick_top/dut/obstacle
add wave -label upright  /tb_blind_stick_top/dut/upright
add wave -label armed    /tb_blind_stick_top/dut/armed
add wave -label GS_CS_N  /tb_blind_stick_top/GS_CS
add wave -label GS_SCLK  /tb_blind_stick_top/GS_SCLK

configure wave -timelineunits ms
# For the demo video: the scenario ends by itself (self-checking, 'ALL SYSTEM TESTS PASSED').
# Use "run 6 sec" instead if you only need the first part (ON -> SAFE -> ALERT -> SAFE).
run -all
wave zoom full
