# 50 MHz board clock
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Asynchronous / human-speed inputs are re-synchronised inside the design (2-FF)
set_false_path -from [get_ports {KEY[*] SW[*] US_ECHO GSENSOR_SDO GSENSOR_SDI}]
# Outputs drive LEDs, buzzer, motor, displays and slow serial lines: no I/O timing needed
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] US_TRIG LED_ON LED_OBST LED_DROP BUZZER MOTOR GSENSOR_CS_N GSENSOR_SCLK GSENSOR_SDI}]
