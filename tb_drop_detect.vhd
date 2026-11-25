-------------------------------------------------------------------------------
-- tb_drop_detect.vhd : sample-driven self-check of the drop / recovery logic.
-- 256 LSB = 1 g. Axis along the stick = X unless axis_sel says otherwise.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_drop_detect is
end entity tb_drop_detect;

architecture sim of tb_drop_detect is
  constant CLK_PERIOD : time := 20 ns;
  signal clk, rst_n, enable, sample_valid : std_logic := '0';
  signal ax, ay, az   : signed(15 downto 0) := (others => '0');
  signal axis_sel     : std_logic_vector(1 downto 0) := "00";
  signal drop_event, upright, armed : std_logic;
  signal a_abs        : integer range 0 to 65535;
  signal drop_cnt     : integer := 0;
  signal done         : boolean := false;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done else clk;

  dut : entity work.drop_detect
    port map (clk => clk, rst_n => rst_n, enable => enable, sample_valid => sample_valid,
              ax => ax, ay => ay, az => az, axis_sel => axis_sel,
              drop_event => drop_event, upright => upright, armed => armed, a_axis_abs => a_abs);

  process (clk)
  begin
    if rising_edge(clk) then
      if drop_event = '1' then drop_cnt <= drop_cnt + 1; end if;
    end if;
  end process;

  main : process
    procedure feed (x, y, z : integer; n : integer) is
    begin
      for i in 1 to n loop
        ax <= to_signed(x, 16); ay <= to_signed(y, 16); az <= to_signed(z, 16);
        sample_valid <= '1';
        wait for CLK_PERIOD;
        sample_valid <= '0';
        wait for 3 * CLK_PERIOD;
      end loop;
    end procedure;

    procedure check (c : boolean; msg : string) is
    begin
      assert c report "FAIL: " & msg severity failure;
      report "ok: " & msg severity note;
    end procedure;
  begin
    rst_n <= '0'; enable <= '0';
    wait for 5 * CLK_PERIOD;
    rst_n <= '1';
    wait for 2 * CLK_PERIOD;

    -- 1. disabled: nothing is armed even with an upright stick
    feed(250, 0, 30, 30);
    check(armed = '0' and upright = '0', "disabled -> not armed, not upright");

    -- 2. enable: needs 20 consecutive upright samples to arm
    enable <= '1';
    feed(250, 0, 30, 19);
    check(armed = '0' and upright = '0', "19 upright samples -> not armed yet");
    feed(250, 0, 30, 1);
    check(armed = '1' and upright = '1', "20 upright samples -> armed + upright");
    check(a_abs = 250, "a_axis_abs reports |ax| = 250");

    -- 3. free-fall: 3 weightless samples
    feed(2, -3, 4, 2);
    check(drop_cnt = 0, "2 free-fall samples -> no drop yet");
    feed(2, -3, 4, 1);
    check(drop_cnt = 1 and armed = '0', "3rd free-fall sample -> exactly 1 drop, disarmed");
    feed(2, -3, 4, 5);
    check(drop_cnt = 1, "no re-trigger while disarmed");

    -- 4. lying on the floor while disarmed -> no new drop, not upright
    feed(4, 1, 255, 80);
    check(drop_cnt = 1 and upright = '0', "lying + disarmed -> no event, recovery condition false");

    -- 5. pick up -> upright, re-armed
    feed(240, 5, 40, 20);
    check(upright = '1' and armed = '1', "picked up -> recovery condition true, re-armed");

    -- 6. lying: 50 consecutive samples needed
    feed(5, 0, 255, 49);
    check(drop_cnt = 1, "49 lying samples -> no drop");
    feed(5, 0, 255, 1);
    check(drop_cnt = 2 and armed = '0', "50th lying sample -> drop (lying path)");

    -- 7. a single upright blip resets the lying counter
    feed(240, 5, 40, 20);                               -- re-arm
    feed(5, 0, 255, 30);
    feed(240, 5, 40, 1);
    feed(5, 0, 255, 30);
    check(drop_cnt = 2, "lying counter is reset by an upright blip");

    -- 8. hysteresis band (|a| between 90 and 154): neither lying nor upright
    feed(120, 100, 100, 100);
    check(drop_cnt = 2 and upright = '0', "hysteresis band holds state");

    -- 9. axis select = Y
    enable <= '0'; wait for 4 * CLK_PERIOD; enable <= '1';
    axis_sel <= "01";
    feed(255, 250, 3, 20);                              -- Y upright (X is big but irrelevant)
    check(armed = '1' and a_abs = 250, "axis Y selected: armed from |ay|");
    feed(255, 3, 3, 50);
    check(drop_cnt = 3, "axis Y selected: lying on Y -> drop");

    -- 10. axis select = Z
    enable <= '0'; wait for 4 * CLK_PERIOD; enable <= '1';
    axis_sel <= "10";
    feed(3, 3, 250, 20);
    check(armed = '1' and a_abs = 250, "axis Z selected: armed from |az|");

    -- 11. disabling clears everything
    enable <= '0';
    feed(3, 3, 250, 2);
    check(armed = '0' and upright = '0', "enable = 0 clears armed/upright");

    report "tb_drop_detect: ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture sim;
