-------------------------------------------------------------------------------
-- tb_hcsr04.vhd : self-checking test of the HC-SR04 driver at the REAL 50 MHz clock.
-- Checks: trigger width, distances 10/100/250 cm, out-of-range (511), missing
-- sensor (sensor_ok = 0, no valid pulses), recovery, and enable = 0 stops triggering.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tb_hcsr04 is
  generic (CLK_HZ : positive := 50_000_000);
end entity tb_hcsr04;

architecture sim of tb_hcsr04 is
  constant CLK_PERIOD : time := 1 sec / CLK_HZ;
  signal clk, rst_n, enable : std_logic := '0';
  signal trig, echo         : std_logic;
  signal dist_cm            : integer range 0 to 511;
  signal meas_valid, sensor_ok : std_logic;
  signal target_cm          : integer := 10;
  signal connected          : std_logic := '1';
  signal done               : boolean := false;
  signal trig_pulses        : integer := 0;
  signal trig_min_w, trig_max_w : time := 0 ns;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done else clk;

  dut : entity work.hcsr04
    generic map (CLK_HZ => CLK_HZ, PERIOD_MS => 60)
    port map (clk => clk, rst_n => rst_n, enable => enable, trig => trig, echo => echo,
              dist_cm => dist_cm, meas_valid => meas_valid, sensor_ok => sensor_ok);

  sensor : entity work.hcsr04_model
    port map (trig => trig, echo => echo, dist_cm => target_cm, connected => connected);

  -- trigger-pulse width monitor
  process
    variable t0 : time;
  begin
    wait until rising_edge(trig);
    t0 := now;
    wait until falling_edge(trig);
    trig_pulses <= trig_pulses + 1;
    if trig_min_w = 0 ns or (now - t0) < trig_min_w then trig_min_w <= now - t0; end if;
    if (now - t0) > trig_max_w then trig_max_w <= now - t0; end if;
  end process;

  main : process
    procedure measure (constant want : integer; constant label_s : string) is
    begin
      wait until meas_valid = '1' for 150 ms;
      assert meas_valid = '1' report label_s & ": timeout, no measurement" severity failure;
      assert dist_cm = want
        report label_s & ": expected " & integer'image(want) & " cm, got " & integer'image(dist_cm)
        severity failure;
      report label_s & ": OK (" & integer'image(dist_cm) & " cm)" severity note;
    end procedure;
  begin
    rst_n <= '0'; enable <= '0';
    wait for 10 * CLK_PERIOD;
    rst_n <= '1';
    wait for 10 * CLK_PERIOD;
    enable <= '1';

    target_cm <= 10;  measure(10,  "10 cm");
    target_cm <= 100; measure(100, "100 cm");
    target_cm <= 250; measure(250, "250 cm");
    target_cm <= 500; measure(511, "out of range");
    assert sensor_ok = '1' report "sensor_ok should be 1 with a working sensor" severity failure;

    -- sensor unplugged: no valid readings, sensor_ok drops
    connected <= '0';
    wait for 200 ms;
    assert sensor_ok = '0' report "sensor_ok should drop when the sensor is missing" severity failure;
    connected <= '1';
    target_cm <= 33;
    wait until meas_valid = '1' for 150 ms;
    assert meas_valid = '1' and dist_cm = 33 and sensor_ok = '1'
      report "recovery after reconnect failed" severity failure;
    report "reconnect: OK" severity note;

    -- trigger width must be >= 10 us (datasheet) and sane
    assert trig_min_w >= 10 us and trig_max_w <= 20 us
      report "trigger pulse width out of range" severity failure;
    report "trigger width " & time'image(trig_min_w) & " .. " & time'image(trig_max_w) severity note;

    -- enable = 0 stops triggering
    enable <= '0';
    wait for 1 ms;
    wait until trig_pulses'event for 200 ms;
    assert not trig_pulses'event report "triggers continued while disabled" severity failure;

    report "tb_hcsr04: ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture sim;
