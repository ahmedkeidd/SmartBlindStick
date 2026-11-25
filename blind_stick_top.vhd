-------------------------------------------------------------------------------
-- blind_stick_top.vhd : Smart Blind Stick - top level for the Terasic DE10-Lite
-- (MAX 10 10M50DAF484C7G).
--
-- User controls (on-board):
--   SW5        ON/OFF (SW0 is broken on our board)  KEY0  recovery button (clears DROP)
--   SW2:SW1    obstacle distance  00=50 cm 01=100 cm 10=150 cm 11=200 cm
--   SW4:SW3    accelerometer axis that runs along the stick (00=X 01=Y 10=Z)
--   SW9:SW8    display page  00=state 01=distance 10=accel 11=ADXL345 DEVID
--   KEY1       global reset (active low)
-- External hardware:
--   HC-SR04 (TRIG/ECHO), 3 LEDs, active buzzer (NPN), vibration motor (NPN)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.stick_pkg.all;

entity blind_stick_top is
  generic (CLK_HZ : positive := 50_000_000;
           MSG_MS : positive := 2000);                 -- how long ON / OFF is displayed
  port (MAX10_CLK1_50 : in  std_logic;
        KEY           : in  std_logic_vector(1 downto 0);
        SW            : in  std_logic_vector(9 downto 0);
        LEDR          : out std_logic_vector(9 downto 0);
        HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : out std_logic_vector(7 downto 0);
        -- external parts on the GPIO header
        US_TRIG       : out std_logic;
        US_ECHO       : in  std_logic;                 -- through a 1k/2k divider !
        LED_OBST      : out std_logic;
        LED_DROP      : out std_logic;
        LED_ON        : out std_logic;
        BUZZER        : out std_logic;
        MOTOR         : out std_logic;
        -- on-board ADXL345 (SPI, 4-wire with automatic 3-wire fallback)
        GSENSOR_CS_N  : out std_logic;
        GSENSOR_SCLK  : out std_logic;
        GSENSOR_SDI   : inout std_logic;               -- MOSI, or SDIO in 3-wire mode
        GSENSOR_SDO   : in  std_logic);                -- ADXL345 -> FPGA (MISO)
end entity blind_stick_top;

architecture rtl of blind_stick_top is
  signal clk     : std_logic;
  signal rst_ff  : std_logic_vector(1 downto 0) := "00";
  signal rst_n   : std_logic;
  signal tick_ms : std_logic;

  signal sw_on, key_clear, key_unused : std_logic;
  signal state   : state_t;
  signal active, drop_en : std_logic;

  signal dist_cm    : integer range 0 to 511;
  signal thr_cm     : integer range 0 to 511;
  signal meas_valid, sensor_ok, obstacle : std_logic;

  signal ax, ay, az : signed(15 downto 0);
  signal acc_valid, dev_ok, wires3 : std_logic;
  signal devid      : std_logic_vector(7 downto 0);
  signal drop_event, upright, armed : std_logic;
  signal a_axis_abs : integer range 0 to 65535;

  signal blink, beep, drop_act : std_logic;
  signal seg         : std_logic_vector(41 downto 0);
begin
  clk <= MAX10_CLK1_50;

  -- reset: KEY1 (active low) synchronised; also asserted for 2 clocks at power-up
  process (clk)
  begin
    if rising_edge(clk) then
      rst_ff <= rst_ff(0) & KEY(1);
    end if;
  end process;
  rst_n <= rst_ff(1);

  u_tick : entity work.tick_gen
    generic map (DIV => CLK_HZ / 1000)
    port map (clk => clk, rst_n => rst_n, tick => tick_ms);

  -- inputs -------------------------------------------------------------------
  u_sw : entity work.debounce
    generic map (STABLE_MS => 20, ACTIVE_LOW => false)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, d_in => SW(5),
              q => sw_on, press => key_unused);

  u_key : entity work.debounce
    generic map (STABLE_MS => 20, ACTIVE_LOW => true)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, d_in => KEY(0),
              q => open, press => key_clear);

  with SW(2 downto 1) select
    thr_cm <= 50  when "00",
              100 when "01",
              150 when "10",
              200 when others;

  -- obstacle path ---------------------------------------------------------------
  active  <= '1' when (state = S_ON_MSG or state = S_NORMAL or state = S_ALERT or state = S_DROP)
             else '0';
  drop_en <= '1' when (state = S_NORMAL or state = S_ALERT or state = S_DROP) else '0';

  u_us : entity work.hcsr04
    generic map (CLK_HZ => CLK_HZ, PERIOD_MS => 60)
    port map (clk => clk, rst_n => rst_n, enable => active, trig => US_TRIG,
              echo => US_ECHO, dist_cm => dist_cm, meas_valid => meas_valid,
              sensor_ok => sensor_ok);

  u_obs : entity work.obstacle_filter
    generic map (N_NEAR => 2, N_FAR => 3, HYST_CM => 5)
    port map (clk => clk, rst_n => rst_n, enable => active, meas_valid => meas_valid,
              dist_cm => dist_cm, thr_cm => thr_cm, obstacle => obstacle);

  -- drop path -------------------------------------------------------------------
  u_acc : entity work.adxl345_ctrl
    generic map (CLK_HZ => CLK_HZ, SPI_HZ => 1_000_000, POLL_MS => 10)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms,
              cs_n => GSENSOR_CS_N, sclk => GSENSOR_SCLK, sdi => GSENSOR_SDI,
              sdo => GSENSOR_SDO, wires3 => wires3, ax => ax, ay => ay, az => az,
              sample_valid => acc_valid, dev_ok => dev_ok, devid => devid);

  u_drop : entity work.drop_detect
    port map (clk => clk, rst_n => rst_n, enable => drop_en, sample_valid => acc_valid,
              ax => ax, ay => ay, az => az, axis_sel => SW(4 downto 3),
              drop_event => drop_event, upright => upright, armed => armed,
              a_axis_abs => a_axis_abs);

  -- control ---------------------------------------------------------------------
  u_fsm : entity work.stick_fsm
    generic map (MSG_MS => MSG_MS)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, sw_on => sw_on,
              obstacle => obstacle, drop_event => drop_event, upright => upright,
              key_clear => key_clear, state => state);

  -- warning patterns (digital timing logic) --------------------------------------
  drop_act <= '1' when state = S_DROP else '0';

  u_blink : entity work.pattern_gen                       -- 2 Hz blink
    generic map (PATTERN => x"CCCC", STEP_MS => 125)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms,
              enable => drop_act, q => blink);

  u_beep : entity work.pattern_gen                        -- triple beep, 1 s pause
    generic map (PATTERN => x"A800", STEP_MS => 100)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms,
              enable => drop_act, q => beep);

  -- outputs ---------------------------------------------------------------------
  MOTOR    <= '1' when state = S_ALERT else '0';
  LED_OBST <= '1' when state = S_ALERT else '0';
  BUZZER   <= beep;
  LED_DROP <= blink;
  LED_ON   <= active;

  u_disp : entity work.display_ctrl
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, state => state,
              page => SW(9 downto 8), dist_cm => dist_cm, a_axis_abs => a_axis_abs,
              axis_sel => SW(4 downto 3), devid => devid, wires3 => wires3, seg => seg);

  HEX0 <= '1' & seg(6 downto 0);        -- bit 7 = decimal point, off
  HEX1 <= '1' & seg(13 downto 7);
  HEX2 <= '1' & seg(20 downto 14);
  HEX3 <= '1' & seg(27 downto 21);
  HEX4 <= '1' & seg(34 downto 28);
  HEX5 <= '1' & seg(41 downto 35);

  -- on-board debug LEDs
  LEDR(0) <= sw_on;
  LEDR(1) <= '1' when state = S_NORMAL else '0';
  LEDR(2) <= '1' when state = S_ALERT  else '0';
  LEDR(3) <= '1' when state = S_DROP   else '0';
  LEDR(4) <= '1' when state = S_ON_MSG else '0';
  LEDR(5) <= sensor_ok;                 -- HC-SR04 is answering
  LEDR(6) <= dev_ok;                    -- ADXL345 answered DEVID = 0xE5
  LEDR(7) <= armed;                     -- drop detector armed
  LEDR(8) <= upright;                   -- recovery condition satisfied
  LEDR(9) <= obstacle;                  -- filtered obstacle flag
end architecture rtl;
