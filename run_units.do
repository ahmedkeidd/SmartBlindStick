# ModelSim script: UNIT tests at the real 50 MHz clock (HC-SR04 timing, ADXL345 SPI, drop logic)
# Run from sim/ :  do run_units.do      (hcsr04 + adxl345 take a few minutes each)
quit -sim
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
foreach f {stick_pkg tick_gen debounce hcsr04 obstacle_filter spi_master pattern_gen
           bin2bcd_seq adxl345_ctrl drop_detect display_ctrl stick_fsm blind_stick_top} {
  vcom -93 -work work ../rtl/$f.vhd
}
vcom -93 -work work hcsr04_model.vhd adxl345_model.vhd tb_hcsr04.vhd tb_adxl345.vhd tb_drop_detect.vhd
foreach tb {tb_drop_detect tb_hcsr04 tb_adxl345} {
  vsim -t ps work.$tb
  run -all
  quit -sim
}
