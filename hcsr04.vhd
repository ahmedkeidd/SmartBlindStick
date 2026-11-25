-------------------------------------------------------------------------------
-- hcsr04.vhd : HC-SR04 ultrasonic driver -> distance in whole centimetres.
--
--  * 12 us trigger pulse, then times the ECHO pulse width.
--  * 58 us of echo = 1 cm (round trip). The width is counted directly in
--    centimetres (no divider needed).
--  * ECHO must be level-shifted to 3.3 V (1k/2k divider) before reaching the FPGA.
--  * One measurement every PERIOD_MS (datasheet: >= 60 ms between triggers).
--  * dist_cm = 511 means "nothing within range" (echo longer than ~450 cm).
--  * sensor_ok = '0' when the sensor never answered (unplugged / wiring fault).
--
-- All timing is derived from CLK_HZ (must be a multiple of 1 MHz) so the same
-- code simulates quickly with CLK_HZ = 1 MHz and runs on the board at 50 MHz.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity hcsr04 is
  generic (CLK_HZ    : positive := 50_000_000;
           PERIOD_MS : positive := 60);
  port (clk        : in  std_logic;
        rst_n      : in  std_logic;
        enable     : in  std_logic;
        trig       : out std_logic;
        echo       : in  std_logic;
        dist_cm    : out integer range 0 to 511;
        meas_valid : out std_logic;               -- 1-clk pulse: dist_cm holds a fresh reading
        sensor_ok  : out std_logic);
end entity hcsr04;

architecture rtl of hcsr04 is
  constant CLK_MHZ     : positive := CLK_HZ / 1_000_000;
  constant TRIG_CYC    : positive := 12 * CLK_MHZ;                 -- 12 us
  constant CYC_PER_CM  : positive := 58 * CLK_MHZ;                 -- 58 us
  constant PERIOD_CYC  : positive := PERIOD_MS * (CLK_HZ / 1000);
  constant RISE_TO_CYC : positive := 3 * (CLK_HZ / 1000);          -- 3 ms: echo must start by then
  constant MAX_CM      : positive := 450;

  type st_t is (ST_IDLE, ST_TRIG, ST_RISE, ST_COUNT, ST_WAIT);
  signal st      : st_t := ST_IDLE;
  signal e1, e2  : std_logic := '0';                               -- echo synchroniser
  signal per_cnt : integer range 0 to PERIOD_CYC := 0;
  signal cyc_cnt : integer range 0 to CYC_PER_CM := 0;
  signal cm_cnt  : integer range 0 to 511 := 0;
  signal trig_r  : std_logic := '0';
  signal valid_r : std_logic := '0';
  signal ok_r    : std_logic := '0';
  signal dist_r  : integer range 0 to 511 := 511;
begin
  assert CLK_HZ >= 1_000_000 and (CLK_HZ mod 1_000_000) = 0
    report "hcsr04: CLK_HZ must be a multiple of 1 MHz" severity failure;

  process (clk)
  begin
    if rising_edge(clk) then
      e1      <= echo;
      e2      <= e1;
      valid_r <= '0';

      if rst_n = '0' then
        st <= ST_IDLE; trig_r <= '0'; per_cnt <= 0; cyc_cnt <= 0; cm_cnt <= 0;
        ok_r <= '0'; dist_r <= 511;
      elsif enable = '0' then
        st <= ST_IDLE; trig_r <= '0'; per_cnt <= 0; cyc_cnt <= 0; cm_cnt <= 0;
      else
        if per_cnt < PERIOD_CYC then
          per_cnt <= per_cnt + 1;
        end if;

        case st is
          when ST_IDLE =>                         -- first measurement right after enable
            trig_r  <= '1';
            per_cnt <= 0;
            st      <= ST_TRIG;

          when ST_TRIG =>
            if per_cnt = TRIG_CYC - 1 then
              trig_r <= '0';
              st     <= ST_RISE;
            end if;

          when ST_RISE =>                         -- wait for echo to start
            if e2 = '1' then
              cyc_cnt <= 0;
              cm_cnt  <= 0;
              st      <= ST_COUNT;
            elsif per_cnt >= TRIG_CYC + RISE_TO_CYC then
              ok_r <= '0';                        -- no echo at all: sensor fault
              st   <= ST_WAIT;
            end if;

          when ST_COUNT =>                        -- echo high: count centimetres
            if e2 = '0' then
              dist_r  <= cm_cnt;
              valid_r <= '1';
              ok_r    <= '1';
              st      <= ST_WAIT;
            elsif cyc_cnt = CYC_PER_CM - 1 then
              cyc_cnt <= 0;
              if cm_cnt = MAX_CM then             -- out of range => "nothing there"
                dist_r  <= 511;
                valid_r <= '1';
                ok_r    <= '1';
                st      <= ST_WAIT;
              else
                cm_cnt <= cm_cnt + 1;
              end if;
            else
              cyc_cnt <= cyc_cnt + 1;
            end if;

          when ST_WAIT =>                         -- pad the cycle out to PERIOD_MS
            if per_cnt >= PERIOD_CYC - 1 then
              trig_r  <= '1';
              per_cnt <= 0;
              st      <= ST_TRIG;
            end if;
        end case;
      end if;
    end if;
  end process;

  trig       <= trig_r;
  dist_cm    <= dist_r;
  meas_valid <= valid_r;
  sensor_ok  <= ok_r;
end architecture rtl;
