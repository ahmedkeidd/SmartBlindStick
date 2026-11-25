-------------------------------------------------------------------------------
-- tb_blind_stick_top.vhd : SYSTEM test of the complete Smart Blind Stick.
-- Real HC-SR04 and ADXL345 behavioural models are wired to the top level, and the
-- display words, LEDs, buzzer and motor are checked against spec tasks 1-12.
--
-- CLK_HZ = 1 MHz by default so a ~17 s scenario simulates in seconds.
-- Every time constant in the design scales with CLK_HZ; the unit tests tb_hcsr04 /
-- tb_adxl345 prove the 50 MHz values separately.
--
-- Acceleration units: 256 LSB = 1 g. Axis X (SW4:3 = 00) runs along the stick:
--   held upright  -> ax ~ 250 ;  lying flat -> ax ~ 5 ;  free fall -> all ~ 0
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.stick_pkg.all;

entity tb_blind_stick_top is
  generic (CLK_HZ : positive := 1_000_000);
end entity tb_blind_stick_top;

architecture sim of tb_blind_stick_top is
  constant CLK_PERIOD : time := 1 sec / CLK_HZ;

  signal clk  : std_logic := '0';
  signal done : boolean := false;

  signal KEY  : std_logic_vector(1 downto 0) := "11";           -- KEY1 = reset_n, KEY0 = recover
  signal SW   : std_logic_vector(9 downto 0) := "0000000010";   -- SW1 = 1 -> 100 cm threshold
  signal LEDR : std_logic_vector(9 downto 0);
  signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(7 downto 0);
  signal US_TRIG, US_ECHO : std_logic;
  signal LED_OBST, LED_DROP, LED_ON, BUZZER, MOTOR : std_logic;
  signal GS_CS, GS_SCLK, GS_SDI, GS_SDO : std_logic;

  signal target_cm : integer := 300;                            -- what the HC-SR04 "sees"
  signal ax, ay, az : integer := 0;                             -- what the ADXL345 "feels"

  signal hexbus : std_logic_vector(41 downto 0);
  signal beep_cnt, blink_cnt : integer := 0;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done else clk;

  dut : entity work.blind_stick_top
    generic map (CLK_HZ => CLK_HZ, MSG_MS => 2000)
    port map (MAX10_CLK1_50 => clk, KEY => KEY, SW => SW, LEDR => LEDR,
              HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2, HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5,
              US_TRIG => US_TRIG, US_ECHO => US_ECHO, LED_OBST => LED_OBST, LED_DROP => LED_DROP,
              LED_ON => LED_ON, BUZZER => BUZZER, MOTOR => MOTOR,
              GSENSOR_CS_N => GS_CS, GSENSOR_SCLK => GS_SCLK, GSENSOR_SDI => GS_SDI,
              GSENSOR_SDO => GS_SDO);

  sonar : entity work.hcsr04_model
    port map (trig => US_TRIG, echo => US_ECHO, dist_cm => target_cm);

  accel : entity work.adxl345_model
    port map (cs_n => GS_CS, sclk => GS_SCLK, mosi => GS_SDI, miso => GS_SDO,
              ax => ax, ay => ay, az => az, devid_val => x"E5",
              reg_data_format => open, reg_bw_rate => open, reg_power_ctl => open,
              burst_reads => open);

  hexbus <= HEX5(6 downto 0) & HEX4(6 downto 0) & HEX3(6 downto 0) &
            HEX2(6 downto 0) & HEX1(6 downto 0) & HEX0(6 downto 0);

  -- count buzzer beeps and LED blinks (rising edges)
  process (BUZZER)   begin if rising_edge(BUZZER)   then beep_cnt  <= beep_cnt  + 1; end if; end process;
  process (LED_DROP) begin if rising_edge(LED_DROP) then blink_cnt <= blink_cnt + 1; end if; end process;

  -- outputs must never be unknown once running
  process
  begin
    wait for 5 ms;
    while not done loop
      assert not (Is_X(MOTOR) or Is_X(BUZZER) or Is_X(LED_ON) or Is_X(LED_OBST) or Is_X(LED_DROP))
        report "unknown (X) value on an output" severity failure;
      wait for 1 ms;
    end loop;
    wait;
  end process;

  main : process
    variable t0, t1 : time;
    variable b0, l0 : integer;

    procedure wait_word (constant w : disp_t; constant nm : string; constant tmo : time) is
    begin
      if hexbus /= pack(w) then
        wait until hexbus = pack(w) for tmo;
      end if;
      assert hexbus = pack(w) report "TIMEOUT: display never showed " & nm severity failure;
      report "t=" & time'image(now) & "  display -> " & nm severity note;
    end procedure;

    procedure hold_word (constant w : disp_t; constant nm : string; constant dur : time) is
      variable t_end : time := now + dur;
    begin
      while now < t_end loop
        assert hexbus = pack(w) report "display left '" & nm & "' unexpectedly" severity failure;
        wait on hexbus for t_end - now;
      end loop;
    end procedure;

    procedure press_recover is
    begin
      KEY(0) <= '0'; wait for 60 ms; KEY(0) <= '1';
    end procedure;

    procedure check (c : boolean; msg : string) is
    begin
      assert c report "FAIL: " & msg severity failure;
      report "ok: " & msg severity note;
    end procedure;
  begin
    -- stick held upright, nothing in front, power-up reset pulse -----------------------
    ax <= 250; ay <= 10; az <= 40; target_cm <= 300;
    KEY <= "01"; wait for 20 us; KEY <= "11";

    -- 1. OFF at power-up (task 3: display blank, all functions disabled) -----------------
    wait for 100 ms;
    check(hexbus = pack(BLANK_DISP), "OFF: display blank");
    check(LED_ON = '0' and MOTOR = '0' and BUZZER = '0' and LED_OBST = '0' and LED_DROP = '0',
          "OFF: every output is off");

    -- 2. switch ON (task 2): "ON" for 2 s, then normal operation -----------------------
    SW(5) <= '1';
    wait_word(WORD_ON, "ON", 100 ms);   t0 := now;
    check(LED_ON = '1', "ON: power LED lit");
    wait_word(WORD_SAFE, "SAFE (normal operation)", 2500 ms);   t1 := now;
    check((t1 - t0) > 1990 ms and (t1 - t0) < 2010 ms, "ON message lasted 2.00 s");
    wait for 300 ms;
    check(LEDR(7) = '1', "drop detector armed after the stick was seen upright");
    check(LEDR(5) = '1' and LEDR(6) = '1', "HC-SR04 and ADXL345 both detected");

    -- 3. obstacle ahead (task 5): ALERT + vibration + warning LED ------------------------
    target_cm <= 40;
    wait_word(WORD_ALERT, "ALErt", 600 ms);
    check(MOTOR = '1' and LED_OBST = '1', "ALERT: vibration motor + obstacle LED on");
    check(BUZZER = '0' and LED_DROP = '0', "ALERT: buzzer and drop LED stay off");

    -- 4. obstacle removed -> back to normal ----------------------------------------------
    target_cm <= 300;
    wait_word(WORD_SAFE, "SAFE", 800 ms);
    check(MOTOR = '0' and LED_OBST = '0', "obstacle gone: motor + LED off");

    -- 5. selectable distance threshold (SW2:1 = 00 -> 50 cm) -----------------------------
    SW(2 downto 1) <= "00";
    target_cm <= 80;
    hold_word(WORD_SAFE, "SAFE (80 cm is outside a 50 cm threshold)", 400 ms);
    target_cm <= 30;
    wait_word(WORD_ALERT, "ALErt (30 cm < 50 cm)", 600 ms);
    SW(2 downto 1) <= "01";                                   -- back to 100 cm
    target_cm <= 300;
    wait_word(WORD_SAFE, "SAFE", 800 ms);

    -- 6. hysteresis at the threshold (100 cm, band 100..104) ------------------------------
    target_cm <= 40;  wait_word(WORD_ALERT, "ALErt", 600 ms);
    target_cm <= 102; hold_word(WORD_ALERT, "ALErt held inside hysteresis band", 400 ms);
    target_cm <= 110; wait_word(WORD_SAFE, "SAFE (110 cm released)", 800 ms);

    -- 7. a single glitch reading must NOT raise an alert ----------------------------------
    wait until falling_edge(US_TRIG);  target_cm <= 40;
    wait until falling_edge(US_TRIG);  target_cm <= 300;
    hold_word(WORD_SAFE, "SAFE (single near reading rejected)", 500 ms);

    -- 8. stick dropped WHILE an obstacle is present: DROP outranks ALERT (tasks 6-8) ------
    target_cm <= 40;  wait_word(WORD_ALERT, "ALErt", 600 ms);
    ax <= 0; ay <= 0; az <= 0;                                -- free fall
    wait_word(WORD_DROP, "drOP", 300 ms);
    check(MOTOR = '0' and LED_OBST = '0', "DROP overrides ALERT outputs");
    b0 := beep_cnt;  l0 := blink_cnt;
    ax <= 5; ay <= 10; az <= 255;                             -- stick comes to rest, lying flat
    hold_word(WORD_DROP, "drOP stays until recovery", 3300 ms);
    check((beep_cnt - b0) >= 5 and (beep_cnt - b0) <= 8,
          "buzzer plays a repeating beep PATTERN (" & integer'image(beep_cnt - b0) & " beeps in 3.3 s)");
    check((blink_cnt - l0) >= 5 and (blink_cnt - l0) <= 8,
          "warning LED blinks continuously (" & integer'image(blink_cnt - l0) & " blinks in 3.3 s)");

    -- 9. recovery button alone is NOT enough while the stick is still lying down ----------
    target_cm <= 300;
    press_recover;
    hold_word(WORD_DROP, "drOP (button ignored while stick lies on the floor)", 300 ms);

    -- 10. stick picked up: condition satisfied, alarm waits for the user's button ----------
    ax <= 240; ay <= 10; az <= 40;
    wait for 400 ms;
    check(LEDR(8) = '1', "recovery condition true after pick-up");
    hold_word(WORD_DROP, "drOP (waiting for the button)", 300 ms);
    press_recover;
    wait_word(WORD_SAFE, "SAFE (recovered)", 300 ms);
    wait for 5 * CLK_PERIOD;
    check(BUZZER = '0' and LED_DROP = '0', "after recovery buzzer and LED are silent");

    -- 11. second drop path: stick laid down without free fall (lying > 0.5 s) -------------
    wait for 300 ms;
    check(LEDR(7) = '1', "re-armed after recovery");
    ax <= 5; ay <= 10; az <= 255;
    wait_word(WORD_DROP, "drOP (lying path)", 900 ms);
    ax <= 240; ay <= 10; az <= 40;
    wait for 400 ms;
    press_recover;
    wait_word(WORD_SAFE, "SAFE (recovered again)", 300 ms);

    -- 12. switch OFF while dropped: OFF outranks everything (task 3) --------------------------
    wait for 300 ms;
    ax <= 0; ay <= 0; az <= 0;
    wait_word(WORD_DROP, "drOP", 300 ms);
    SW(5) <= '0';
    wait_word(WORD_OFF, "OFF", 100 ms);   t0 := now;
    wait for 5 * CLK_PERIOD;
    check(BUZZER = '0' and LED_DROP = '0' and MOTOR = '0' and LED_ON = '0',
          "OFF message: all warning/actuation outputs disabled");
    wait_word(BLANK_DISP, "blank", 2500 ms);   t1 := now;
    check((t1 - t0) > 1990 ms and (t1 - t0) < 2010 ms, "OFF message lasted 2.00 s");

    -- 13. while OFF, obstacles and drops are ignored -------------------------------------------
    target_cm <= 40; ax <= 0; ay <= 0; az <= 0;
    hold_word(BLANK_DISP, "blank while OFF", 600 ms);
    check(MOTOR = '0' and BUZZER = '0' and LED_OBST = '0' and LED_DROP = '0' and LED_ON = '0',
          "OFF: obstacle + free fall do nothing");

    -- 14. switch ON again: obstacle still there -> goes straight to ALERT after the ON message --
    ax <= 250; ay <= 10; az <= 40;
    SW(5) <= '1';
    wait_word(WORD_ON, "ON", 100 ms);
    wait_word(WORD_ALERT, "ALErt (obstacle present at start-up)", 2500 ms);

    report "tb_blind_stick_top: ALL SYSTEM TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture sim;
