
-- ======================================================================
-- FILE: rtl/stick_pkg.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- stick_pkg.vhd
-- Shared types, state enumeration and 7-segment encodings for the Smart Blind Stick.
--
-- Segment bit order inside one digit (seg_t):
--   seg(0)=a  seg(1)=b  seg(2)=c  seg(3)=d  seg(4)=e  seg(5)=f  seg(6)=g
-- DE10-Lite HEX displays are ACTIVE-LOW: '0' lights a segment.
-- Display index 0 = HEX0 (rightmost) ... index 5 = HEX5 (leftmost).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package stick_pkg is

  -- Operating states (spec task 8) plus an OFF-message state (task 3a)
  type state_t is (S_OFF, S_OFF_MSG, S_ON_MSG, S_NORMAL, S_ALERT, S_DROP);

  subtype seg_t is std_logic_vector(6 downto 0);
  type disp_t is array (0 to 5) of seg_t;

  constant SEG_BLANK : seg_t := "1111111";
  -- Digits / letters. Written active-HIGH (g f e d c b a) then inverted.
  constant SEG_0 : seg_t := not seg_t'("0111111");
  constant SEG_1 : seg_t := not seg_t'("0000110");
  constant SEG_2 : seg_t := not seg_t'("1011011");
  constant SEG_3 : seg_t := not seg_t'("1001111");
  constant SEG_4 : seg_t := not seg_t'("1100110");
  constant SEG_5 : seg_t := not seg_t'("1101101");
  constant SEG_6 : seg_t := not seg_t'("1111101");
  constant SEG_7 : seg_t := not seg_t'("0000111");
  constant SEG_8 : seg_t := not seg_t'("1111111");
  constant SEG_9 : seg_t := not seg_t'("1101111");
  constant SEG_A : seg_t := not seg_t'("1110111");
  constant SEG_b : seg_t := not seg_t'("1111100");
  constant SEG_C : seg_t := not seg_t'("0111001");
  constant SEG_d : seg_t := not seg_t'("1011110");
  constant SEG_E : seg_t := not seg_t'("1111001");
  constant SEG_F : seg_t := not seg_t'("1110001");
  constant SEG_L : seg_t := not seg_t'("0111000");
  constant SEG_n : seg_t := not seg_t'("1010100");
  constant SEG_O : seg_t := not seg_t'("0111111");
  constant SEG_P : seg_t := not seg_t'("1110011");
  constant SEG_r : seg_t := not seg_t'("1010000");
  constant SEG_S : seg_t := not seg_t'("1101101");
  constant SEG_tl : seg_t := not seg_t'("1111000");

  constant BLANK_DISP : disp_t := (others => SEG_BLANK);

  -- Status words (spec tasks 2, 3, 5, 7, 11)
  constant WORD_ON    : disp_t := (3 => SEG_O, 2 => SEG_n, others => SEG_BLANK);            -- "  On  "
  constant WORD_OFF   : disp_t := (4 => SEG_O, 3 => SEG_F, 2 => SEG_F, others => SEG_BLANK); -- " OFF  "
  constant WORD_SAFE  : disp_t := (4 => SEG_S, 3 => SEG_A, 2 => SEG_F, 1 => SEG_E,
                                   others => SEG_BLANK);                                    -- " SAFE "
  constant WORD_ALERT : disp_t := (5 => SEG_A, 4 => SEG_L, 3 => SEG_E, 2 => SEG_r, 1 => SEG_tl,
                                   others => SEG_BLANK);                                    -- "ALErt "
  constant WORD_DROP  : disp_t := (4 => SEG_d, 3 => SEG_r, 2 => SEG_O, 1 => SEG_P,
                                   others => SEG_BLANK);                                    -- " drOP "

  function seg_hex (v : natural) return seg_t;                  -- 0..15 -> hex digit
  function pack    (d : disp_t) return std_logic_vector;        -- 6 digits -> 42 bits (HEX5 on top)

end package stick_pkg;

package body stick_pkg is

  function seg_hex (v : natural) return seg_t is
  begin
    case v is
      when 0  => return SEG_0;
      when 1  => return SEG_1;
      when 2  => return SEG_2;
      when 3  => return SEG_3;
      when 4  => return SEG_4;
      when 5  => return SEG_5;
      when 6  => return SEG_6;
      when 7  => return SEG_7;
      when 8  => return SEG_8;
      when 9  => return SEG_9;
      when 10 => return SEG_A;
      when 11 => return SEG_b;
      when 12 => return SEG_C;
      when 13 => return SEG_d;
      when 14 => return SEG_E;
      when 15 => return SEG_F;
      when others => return SEG_BLANK;
    end case;
  end function;

  function pack (d : disp_t) return std_logic_vector is
    variable r : std_logic_vector(41 downto 0);
  begin
    for i in 0 to 5 loop
      r(7 * i + 6 downto 7 * i) := d(i);
    end loop;
    return r;
  end function;

end package body stick_pkg;

-- ======================================================================
-- FILE: rtl/tick_gen.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- tick_gen.vhd : free-running prescaler. 'tick' is a 1-clock pulse every DIV clocks.
-- Synchronous, active-low reset.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity tick_gen is
  generic (DIV : positive := 50_000);            -- 50 MHz / 50_000 = 1 kHz (1 ms)
  port (clk   : in  std_logic;
        rst_n : in  std_logic;
        tick  : out std_logic);
end entity tick_gen;

architecture rtl of tick_gen is
  signal cnt : integer range 0 to DIV - 1 := 0;
  signal t   : std_logic := '0';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      t <= '0';
      if rst_n = '0' then
        cnt <= 0;
      elsif cnt = DIV - 1 then
        cnt <= 0;
        t   <= '1';
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;
  tick <= t;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/debounce.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- debounce.vhd : 2-FF synchroniser + time-based debouncer + press pulse.
--   q     : debounced level, polarity-normalised ('1' = asserted/pressed/ON)
--   press : 1-clock pulse when q goes '0' -> '1'
-- ACTIVE_LOW => the raw input is '0' when asserted (DE10-Lite KEYs).
-- An input change must persist STABLE_MS milliseconds before q follows it.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity debounce is
  generic (STABLE_MS  : positive := 20;
           ACTIVE_LOW : boolean  := false);
  port (clk     : in  std_logic;
        rst_n   : in  std_logic;
        tick_ms : in  std_logic;
        d_in    : in  std_logic;
        q       : out std_logic;
        press   : out std_logic);
end entity debounce;

architecture rtl of debounce is
  function idle_level (act_low : boolean) return std_logic is
  begin
    if act_low then return '1'; else return '0'; end if;
  end function;

  constant IDLE : std_logic := idle_level(ACTIVE_LOW);
  signal s1, s2 : std_logic := IDLE;
  signal raw    : std_logic;
  signal q_r    : std_logic := '0';
  signal cnt    : integer range 0 to STABLE_MS := 0;
begin
  raw <= (not s2) when ACTIVE_LOW else s2;

  process (clk)
  begin
    if rising_edge(clk) then
      s1    <= d_in;
      s2    <= s1;
      press <= '0';
      if rst_n = '0' then
        q_r <= '0';
        cnt <= 0;
      elsif raw = q_r then
        cnt <= 0;
      elsif tick_ms = '1' then
        if cnt = STABLE_MS - 1 then
          q_r <= raw;
          cnt <= 0;
          if raw = '1' then
            press <= '1';
          end if;
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;

  q <= q_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/hcsr04.vhd
-- ======================================================================
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

-- ======================================================================
-- FILE: rtl/obstacle_filter.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- obstacle_filter.vhd : turns raw distances into a clean 'obstacle' flag.
--  * Assert  : N_NEAR consecutive readings below thr_cm.
--  * Release : N_FAR  consecutive readings at/above thr_cm + HYST_CM.
--  * Readings inside the hysteresis band hold the current state.
-- This removes single-sample ultrasonic glitches and flicker at the threshold.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity obstacle_filter is
  generic (N_NEAR  : positive := 2;
           N_FAR   : positive := 3;
           HYST_CM : natural  := 5);
  port (clk        : in  std_logic;
        rst_n      : in  std_logic;
        enable     : in  std_logic;
        meas_valid : in  std_logic;
        dist_cm    : in  integer range 0 to 511;
        thr_cm     : in  integer range 0 to 511;
        obstacle   : out std_logic);
end entity obstacle_filter;

architecture rtl of obstacle_filter is
  signal near_cnt : integer range 0 to N_NEAR := 0;
  signal far_cnt  : integer range 0 to N_FAR  := 0;
  signal obs_r    : std_logic := '0';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' or enable = '0' then
        near_cnt <= 0;
        far_cnt  <= 0;
        obs_r    <= '0';
      elsif meas_valid = '1' then
        if dist_cm < thr_cm then
          far_cnt <= 0;
          if near_cnt + 1 >= N_NEAR then
            near_cnt <= N_NEAR;
            obs_r    <= '1';
          else
            near_cnt <= near_cnt + 1;
          end if;
        elsif dist_cm >= thr_cm + HYST_CM then
          near_cnt <= 0;
          if far_cnt + 1 >= N_FAR then
            far_cnt <= N_FAR;
            obs_r   <= '0';
          else
            far_cnt <= far_cnt + 1;
          end if;
        else                                   -- inside hysteresis band: hold
          near_cnt <= 0;
          far_cnt  <= 0;
        end if;
      end if;
    end if;
  end process;
  obstacle <= obs_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/spi_master.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- spi_master.vhd : byte-wide SPI master, MODE 3 (CPOL=1, CPHA=1), MSB first.
--   * SCLK idles HIGH. MOSI changes when SCLK falls; MISO is sampled just
--     before SCLK rises (ADXL345 shifts data out on the falling edge).
--   * Chip-select is handled by the caller so several bytes can share one CS.
--   * SCLK period = 2 * HALF_DIV clocks.
--   * 3-wire support: when three_wire='1' and rd='1' the byte is a DATA-READ byte
--     and mosi_oe goes low for the whole byte, so the caller can release the
--     bidirectional SDIO line and let the ADXL345 drive it.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_master is
  generic (HALF_DIV : positive := 25);           -- 50 MHz / (2*25) = 1 MHz SCLK
  port (clk     : in  std_logic;
        rst_n   : in  std_logic;
        start   : in  std_logic;                 -- 1-clk pulse (ignored while busy)
        tx_byte : in  std_logic_vector(7 downto 0);
        rd         : in  std_logic := '0';       -- this byte carries data FROM the slave
        three_wire : in  std_logic := '0';       -- SDI doubles as data-out (SDIO)
        rx_byte : out std_logic_vector(7 downto 0);
        busy    : out std_logic;
        done    : out std_logic;                 -- 1-clk pulse, rx_byte valid
        sclk    : out std_logic;
        mosi    : out std_logic;
        mosi_oe : out std_logic;                 -- '0' = release the SDIO line
        miso    : in  std_logic);
end entity spi_master;

architecture rtl of spi_master is
  type st_t is (ST_IDLE, ST_LOW, ST_HIGH);
  signal st     : st_t := ST_IDLE;
  signal tmr    : integer range 0 to HALF_DIV - 1 := 0;
  signal bitn   : integer range 0 to 7 := 0;
  signal tx_sh  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sh  : std_logic_vector(7 downto 0) := (others => '0');
  signal sclk_r : std_logic := '1';
  signal mosi_r : std_logic := '0';
  signal busy_r : std_logic := '0';
  signal done_r : std_logic := '0';
  signal miso_s : std_logic := '0';
  signal oe_r   : std_logic := '1';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      miso_s <= miso;
      done_r <= '0';
      if rst_n = '0' then
        st <= ST_IDLE; sclk_r <= '1'; busy_r <= '0'; tmr <= 0; bitn <= 0;
      else
        case st is
          when ST_IDLE =>
            sclk_r <= '1';
            if start = '1' then
              tx_sh  <= tx_byte;
              oe_r   <= not (rd and three_wire);
              mosi_r <= tx_byte(7);
              bitn   <= 0;
              tmr    <= 0;
              sclk_r <= '0';                    -- first falling edge
              busy_r <= '1';
              st     <= ST_LOW;
            end if;

          when ST_LOW =>
            if tmr = HALF_DIV - 1 then
              tmr    <= 0;
              rx_sh  <= rx_sh(6 downto 0) & miso_s;   -- sample just before rising edge
              sclk_r <= '1';
              st     <= ST_HIGH;
            else
              tmr <= tmr + 1;
            end if;

          when ST_HIGH =>
            if tmr = HALF_DIV - 1 then
              tmr <= 0;
              if bitn = 7 then
                busy_r <= '0';
                done_r <= '1';
                st     <= ST_IDLE;
              else
                bitn   <= bitn + 1;
                tx_sh  <= tx_sh(6 downto 0) & '0';
                mosi_r <= tx_sh(6);
                sclk_r <= '0';
                st     <= ST_LOW;
              end if;
            else
              tmr <= tmr + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  sclk    <= sclk_r;
  mosi    <= mosi_r;
  mosi_oe <= oe_r;
  busy    <= busy_r;
  done    <= done_r;
  rx_byte <= rx_sh;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/pattern_gen.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- pattern_gen.vhd : digital-timing pattern generator for buzzer / LED.
-- A 16-bit PATTERN is played MSB-first, one bit per STEP_MS milliseconds, and
-- repeats while 'enable' = '1'. On enable the pattern restarts at bit 15, so
-- an alarm always starts with its first beep. Output is '0' when disabled.
--   x"CCCC", 125 ms -> 2 Hz blink      (250 ms on / 250 ms off)
--   x"A800", 100 ms -> triple beep + 1.0 s pause (1.6 s period)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity pattern_gen is
  generic (PATTERN : std_logic_vector(15 downto 0) := x"CCCC";
           STEP_MS : positive := 125);
  port (clk     : in  std_logic;
        rst_n   : in  std_logic;
        tick_ms : in  std_logic;
        enable  : in  std_logic;
        q       : out std_logic);
end entity pattern_gen;

architecture rtl of pattern_gen is
  signal idx  : integer range 0 to 15 := 15;
  signal ms   : integer range 0 to STEP_MS := 0;
  signal q_r  : std_logic := '0';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' or enable = '0' then
        idx <= 15;
        ms  <= 0;
        q_r <= '0';
      else
        q_r <= PATTERN(idx);
        if tick_ms = '1' then
          if ms = STEP_MS - 1 then
            ms <= 0;
            if idx = 0 then idx <= 15; else idx <= idx - 1; end if;
          else
            ms <= ms + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
  q <= q_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/bin2bcd_seq.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- bin2bcd_seq.vhd : sequential "double dabble" binary -> 5-digit BCD.
-- One iteration per clock (14 clocks per conversion) so there is no long
-- combinational path. Input range 0..16383.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bin2bcd_seq is
  port (clk   : in  std_logic;
        rst_n : in  std_logic;
        start : in  std_logic;
        bin   : in  unsigned(13 downto 0);
        busy  : out std_logic;
        done  : out std_logic;                          -- 1-clk pulse, bcd valid
        bcd   : out std_logic_vector(19 downto 0));     -- d4 d3 d2 d1 d0
end entity bin2bcd_seq;

architecture rtl of bin2bcd_seq is
  signal sh     : unsigned(33 downto 0) := (others => '0');
  signal cnt    : integer range 0 to 13 := 0;
  signal run    : std_logic := '0';
  signal done_r : std_logic := '0';
begin
  process (clk)
    variable v : unsigned(33 downto 0);
  begin
    if rising_edge(clk) then
      done_r <= '0';
      if rst_n = '0' then
        run <= '0';
        cnt <= 0;
      elsif run = '0' then
        if start = '1' then
          sh  <= (33 downto 14 => '0') & bin;
          cnt <= 0;
          run <= '1';
        end if;
      else
        v := sh;
        for d in 0 to 4 loop                            -- add 3 to any BCD digit > 4
          if to_integer(v(17 + 4 * d downto 14 + 4 * d)) > 4 then
            v(17 + 4 * d downto 14 + 4 * d) := v(17 + 4 * d downto 14 + 4 * d) + 3;
          end if;
        end loop;
        sh <= v(32 downto 0) & '0';
        if cnt = 13 then
          run    <= '0';
          done_r <= '1';
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;

  bcd  <= std_logic_vector(sh(33 downto 14));
  busy <= run;
  done <= done_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/adxl345_ctrl.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- adxl345_ctrl.vhd : initialises the on-board ADXL345 accelerometer over SPI
-- (mode 3) and then reads X/Y/Z every POLL_MS milliseconds.
--
-- WIRE MODE (automatic): power-up default is 4-wire (data out on SDO). If the DEVID
-- read does not return 0xE5 the controller switches the chip to 3-wire (DATA_FORMAT
-- bit 6 = 1, data comes back on the bidirectional SDI/SDIO pin, which is what the
-- Terasic demo uses) and tries again, alternating every RETRY_MS until it works.
--
-- Start-up sequence (each line = one CS-low transaction):
--   1. read  0x00 DEVID       -> must be 0xE5, else retry every RETRY_MS
--   2. write 0x31 DATA_FORMAT = 0x0B  (FULL_RES=1, +-16 g, SPI bit 0 = 4-wire)
--                          or 0x4B  (same, SPI bit 1 = 3-wire)
--   3. write 0x2C BW_RATE     = 0x0B  (200 Hz output data rate)
--   4. write 0x2D POWER_CTL   = 0x08  (Measure = 1)
--   5. forever: burst-read 6 bytes from 0x32 (cmd 0xF2) = X0 X1 Y0 Y1 Z0 Z1
-- Full-resolution mode => 256 LSB per g on every axis (1 LSB = 3.9 mg).
-- The first WARMUP_SAMPLES readings are discarded (registers read 0 until the
-- first conversion completes).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adxl345_ctrl is
  generic (CLK_HZ         : positive := 50_000_000;
           SPI_HZ         : positive := 1_000_000;
           POLL_MS        : positive := 10;
           BOOT_MS        : positive := 20;
           RETRY_MS       : positive := 100;
           WARMUP_SAMPLES : natural  := 5);
  port (clk          : in  std_logic;
        rst_n        : in  std_logic;
        tick_ms      : in  std_logic;
        cs_n         : out std_logic;
        sclk         : out std_logic;
        sdi          : inout std_logic;                  -- MOSI (4-wire) / SDIO (3-wire)
        sdo          : in  std_logic;                    -- MISO in 4-wire mode
        wires3       : out std_logic;                    -- '1' = running in 3-wire mode
        ax, ay, az   : out signed(15 downto 0);
        sample_valid : out std_logic;                    -- 1-clk pulse per new sample
        dev_ok       : out std_logic;                    -- DEVID == 0xE5 seen
        devid        : out std_logic_vector(7 downto 0));
end entity adxl345_ctrl;

architecture rtl of adxl345_ctrl is
  function imax (a, b : integer) return integer is
  begin
    if a > b then return a; else return b; end if;
  end function;

  constant HALF_DIV : positive := imax(2, CLK_HZ / (2 * SPI_HZ));
  constant GAP_CYC  : positive := 12;                    -- CS high time > 150 ns @ 50 MHz

  type st_t is (ST_BOOT, ST_CS_LOW, ST_SEND, ST_WAIT_BYTE, ST_CS_HIGH,
                ST_NEXT, ST_POLL_WAIT, ST_RETRY_WAIT);
  signal st     : st_t := ST_BOOT;
  signal txn    : integer range 0 to 4 := 0;             -- 0 DEVID,1 FMT,2 BW,3 PWR,4 DATA
  signal bidx   : integer range 0 to 7 := 0;             -- byte index inside transaction
  signal ms_cnt : integer range 0 to 1023 := 0;
  signal gap    : integer range 0 to 15 := 0;
  signal warm   : integer range 0 to 255 := 0;

  type bytes_t is array (0 to 5) of std_logic_vector(7 downto 0);
  signal raw     : bytes_t := (others => (others => '0'));
  signal devid_r : std_logic_vector(7 downto 0) := (others => '0');
  signal ax_r, ay_r, az_r : signed(15 downto 0) := (others => '0');
  signal ok_r, valid_r    : std_logic := '0';
  signal cs_r             : std_logic := '1';
  signal mode3_r          : std_logic := '0';          -- 0 = 4-wire, 1 = 3-wire
  signal sp_rd, sp_oe     : std_logic := '0';
  signal mosi_s, miso_i   : std_logic;

  signal sp_start, sp_busy, sp_done : std_logic;
  signal sp_tx, sp_rx               : std_logic_vector(7 downto 0);
  signal oe_comb                    : std_logic;

  function tx_of (t : integer; i : integer) return std_logic_vector is
  begin
    if i = 0 then
      case t is
        when 0      => return x"80";     -- read  DEVID
        when 1      => return x"31";     -- write DATA_FORMAT
        when 2      => return x"2C";     -- write BW_RATE
        when 3      => return x"2D";     -- write POWER_CTL
        when others => return x"F2";     -- read burst from 0x32 (R=1, MB=1)
      end case;
    else
      case t is
        when 1      => return x"0B";
        when 2      => return x"0B";
        when 3      => return x"08";
        when others => return x"00";     -- dummy byte while reading
      end case;
    end if;
  end function;

  function nbytes_of (t : integer) return integer is
  begin
    if t = 4 then return 7; else return 2; end if;
  end function;
begin
  u_spi : entity work.spi_master
    generic map (HALF_DIV => HALF_DIV)
    port map (clk => clk, rst_n => rst_n, start => sp_start, tx_byte => sp_tx,
              rd => sp_rd, three_wire => mode3_r,
              rx_byte => sp_rx, busy => sp_busy, done => sp_done,
              sclk => sclk, mosi => mosi_s, mosi_oe => sp_oe, miso => miso_i);

  -- SDI/SDIO pin: we drive it except while the chip is sending (3-wire read byte),
  -- plus a short hold-off after CS rises so we never fight the chip releasing the line.
  oe_comb <= '1' when (cs_r = '1' and not (st = ST_CS_HIGH and gap < 3)) else sp_oe;
  sdi     <= mosi_s when oe_comb = '1' else 'Z';
  miso_i  <= sdi when mode3_r = '1' else sdo;
  wires3  <= mode3_r;

  process (clk)
  begin
    if rising_edge(clk) then
      sp_start <= '0';
      valid_r  <= '0';
      if rst_n = '0' then
        st <= ST_BOOT; txn <= 0; ms_cnt <= 0; gap <= 0; cs_r <= '1'; ok_r <= '0'; warm <= 0;
        mode3_r <= '0'; sp_rd <= '0';
      else
        case st is

          when ST_BOOT =>                                  -- let the sensor power up
            if tick_ms = '1' then
              if ms_cnt = BOOT_MS - 1 then
                ms_cnt <= 0; txn <= 0; st <= ST_CS_LOW;
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

          when ST_CS_LOW =>
            cs_r <= '0';
            bidx <= 0;
            if gap = 2 then gap <= 0; st <= ST_SEND; else gap <= gap + 1; end if;

          when ST_SEND =>
            sp_start <= '1';
            sp_tx    <= tx_of(txn, bidx);
            if txn = 1 and bidx = 1 then                   -- DATA_FORMAT: SPI bit follows the mode
              if mode3_r = '1' then sp_tx <= x"4B"; else sp_tx <= x"0B"; end if;
            end if;
            if (txn = 0 or txn = 4) and bidx >= 1 then sp_rd <= '1'; else sp_rd <= '0'; end if;
            st       <= ST_WAIT_BYTE;

          when ST_WAIT_BYTE =>
            if sp_done = '1' then
              if bidx >= 1 then
                if txn = 0 then
                  devid_r <= sp_rx;
                elsif txn = 4 then
                  raw(bidx - 1) <= sp_rx;
                end if;
              end if;
              if bidx = nbytes_of(txn) - 1 then
                st <= ST_CS_HIGH;
              else
                bidx <= bidx + 1;
                st   <= ST_SEND;
              end if;
            end if;

          when ST_CS_HIGH =>
            cs_r <= '1';
            if gap = GAP_CYC - 1 then gap <= 0; st <= ST_NEXT; else gap <= gap + 1; end if;

          when ST_NEXT =>
            case txn is
              when 0 =>
                if devid_r = x"E5" then
                  ok_r <= '1'; txn <= 1; st <= ST_CS_LOW;
                else
                  ok_r <= '0'; ms_cnt <= 0; mode3_r <= not mode3_r; st <= ST_RETRY_WAIT;
                end if;
              when 1 =>
                if ok_r = '1' then txn <= 2; else txn <= 0; end if;   -- probing: re-read DEVID
                st <= ST_CS_LOW;
              when 2 =>
                txn <= 3; st <= ST_CS_LOW;
              when 3 =>
                txn <= 4; warm <= 0; ms_cnt <= 0; st <= ST_POLL_WAIT;
              when others =>                               -- txn = 4: a sample is ready
                ax_r <= signed(std_logic_vector'(raw(1) & raw(0)));
                ay_r <= signed(std_logic_vector'(raw(3) & raw(2)));
                az_r <= signed(std_logic_vector'(raw(5) & raw(4)));
                if warm < WARMUP_SAMPLES then
                  warm <= warm + 1;
                else
                  valid_r <= '1';
                end if;
                ms_cnt <= 0; st <= ST_POLL_WAIT;
            end case;

          when ST_POLL_WAIT =>
            if tick_ms = '1' then
              if ms_cnt = POLL_MS - 1 then
                ms_cnt <= 0; txn <= 4; st <= ST_CS_LOW;
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

          when ST_RETRY_WAIT =>
            if tick_ms = '1' then
              if ms_cnt = RETRY_MS - 1 then
                ms_cnt <= 0; txn <= 1; st <= ST_CS_LOW;   -- set the new wire mode, then re-read DEVID
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

  cs_n         <= cs_r;
  ax           <= ax_r;
  ay           <= ay_r;
  az           <= az_r;
  sample_valid <= valid_r;
  dev_ok       <= ok_r;
  devid        <= devid_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/drop_detect.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- drop_detect.vhd : decides from accelerometer samples whether the stick was
-- dropped, and whether it has been picked up again.
--
-- Units: 256 LSB = 1 g (ADXL345 full-resolution mode). One call per sample.
--
-- DROP condition (only while 'armed'):
--   (a) free-fall : |ax|+|ay|+|az| < FF_THR  for FF_N  consecutive samples
--                   (weightless: a held/resting stick always reads >= 1 g = 256)
--   (b) lying     : |a_axis|       < LAY_THR for LAY_N consecutive samples
--                   a_axis = the accelerometer axis that runs ALONG the stick.
--                   Upright -> ~1 g on that axis; lying flat -> ~0 g.
-- RECOVERY condition ('upright' output):
--   |a_axis| > UP_THR for UP_N consecutive samples (stick lifted back up).
-- 'armed' is set once the stick has been seen upright and is cleared when a
-- drop fires, so a stick that is switched ON while lying on a table does not
-- alarm until it has been picked up once.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity drop_detect is
  generic (FF_THR  : natural  := 128;     -- 0.5 g
           FF_N    : positive := 3;       -- 30 ms @ 100 Hz
           LAY_THR : natural  := 90;      -- ~0.35 g  (stick within ~20 deg of horizontal)
           LAY_N   : positive := 50;      -- 0.5 s
           UP_THR  : natural  := 154;     -- ~0.6 g   (stick at least ~37 deg from horizontal)
           UP_N    : positive := 20);     -- 0.2 s
  port (clk          : in  std_logic;
        rst_n        : in  std_logic;
        enable       : in  std_logic;                  -- '1' while the system is active
        sample_valid : in  std_logic;
        ax, ay, az   : in  signed(15 downto 0);
        axis_sel     : in  std_logic_vector(1 downto 0); -- 00=X 01=Y 1x=Z : axis along the stick
        drop_event   : out std_logic;                  -- 1-clk pulse
        upright      : out std_logic;                  -- recovery condition satisfied (level)
        armed        : out std_logic;                  -- debug
        a_axis_abs   : out integer range 0 to 65535);  -- debug: |a| on the selected axis
end entity drop_detect;

architecture rtl of drop_detect is
  signal ff_cnt   : integer range 0 to FF_N  := 0;
  signal lay_cnt  : integer range 0 to LAY_N := 0;
  signal up_cnt   : integer range 0 to UP_N  := 0;
  signal armed_r  : std_logic := '0';
  signal up_r     : std_logic := '0';
  signal drop_r   : std_logic := '0';
  signal a_abs_r  : integer range 0 to 65535 := 0;
begin
  process (clk)
    variable xa, ya, za, sel, l1 : integer;
    variable v_ff, v_lay, v_up   : integer;
  begin
    if rising_edge(clk) then
      drop_r <= '0';
      if rst_n = '0' then
        ff_cnt <= 0; lay_cnt <= 0; up_cnt <= 0; armed_r <= '0'; up_r <= '0'; a_abs_r <= 0;
      else
        xa := abs(to_integer(ax));
        ya := abs(to_integer(ay));
        za := abs(to_integer(az));
        l1 := xa + ya + za;
        case axis_sel is
          when "00"   => sel := xa;
          when "01"   => sel := ya;
          when others => sel := za;
        end case;

        if sample_valid = '1' then
          a_abs_r <= sel;
        end if;

        if enable = '0' then
          ff_cnt <= 0; lay_cnt <= 0; up_cnt <= 0; armed_r <= '0'; up_r <= '0';
        elsif sample_valid = '1' then
          v_ff := ff_cnt; v_lay := lay_cnt; v_up := up_cnt;

          if l1 < FF_THR then
            if v_ff < FF_N then v_ff := v_ff + 1; end if;
          else
            v_ff := 0;
          end if;

          if sel < LAY_THR then
            if v_lay < LAY_N then v_lay := v_lay + 1; end if;
          else
            v_lay := 0;
          end if;

          if sel > UP_THR then
            if v_up < UP_N then v_up := v_up + 1; end if;
          else
            v_up := 0;
          end if;

          ff_cnt <= v_ff; lay_cnt <= v_lay; up_cnt <= v_up;

          if v_up >= UP_N then
            up_r    <= '1';
            armed_r <= '1';
          else
            up_r <= '0';
          end if;

          if armed_r = '1' and (v_ff >= FF_N or v_lay >= LAY_N) then
            drop_r  <= '1';
            armed_r <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  drop_event <= drop_r;
  upright    <= up_r;
  armed      <= armed_r;
  a_axis_abs <= a_abs_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/display_ctrl.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- display_ctrl.vhd : drives the six 7-segment digits.
--
--  page "00" : operating-state word   (ON / OFF / SAFE / ALErt / drOP / blank)
--  page "01" : debug - measured distance in cm            "d    123"
--  page "10" : debug - |acceleration| on the stick axis   "A x 0256"  (x = axis index)
--  page "11" : debug - ADXL345 DEVID register in hex      "d 3 E5"  (E5 = chip found;
--                the middle digit is the SPI wire mode in use, 4 or 3)
--
-- Output 'seg' packs the 6 digits, 7 bits each (HEX5 in bits 41..35 ... HEX0 in 6..0).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.stick_pkg.all;

entity display_ctrl is
  port (clk        : in  std_logic;
        rst_n      : in  std_logic;
        tick_ms    : in  std_logic;
        state      : in  state_t;
        page       : in  std_logic_vector(1 downto 0);
        dist_cm    : in  integer range 0 to 511;
        a_axis_abs : in  integer range 0 to 65535;
        axis_sel   : in  std_logic_vector(1 downto 0);
        devid      : in  std_logic_vector(7 downto 0);
        wires3     : in  std_logic := '0';
        seg        : out std_logic_vector(41 downto 0));
end entity display_ctrl;

architecture rtl of display_ctrl is
  function imin (a, b : integer) return integer is
  begin
    if a < b then return a; else return b; end if;
  end function;

  signal conv_start, conv_busy, conv_done : std_logic := '0';
  signal conv_in  : unsigned(13 downto 0);
  signal conv_bcd : std_logic_vector(19 downto 0);
  signal bcd_r    : std_logic_vector(19 downto 0) := (others => '0');
  signal seg_c    : std_logic_vector(41 downto 0);
  signal seg_r    : std_logic_vector(41 downto 0) := (others => '1');
begin
  conv_in <= to_unsigned(dist_cm, 14) when page = "01"
             else to_unsigned(imin(a_axis_abs, 9999), 14);

  u_bcd : entity work.bin2bcd_seq
    port map (clk => clk, rst_n => rst_n, start => conv_start, bin => conv_in,
              busy => conv_busy, done => conv_done, bcd => conv_bcd);

  -- refresh the BCD value once per millisecond
  process (clk)
  begin
    if rising_edge(clk) then
      conv_start <= '0';
      if rst_n = '1' then
        if tick_ms = '1' and conv_busy = '0' then
          conv_start <= '1';
        end if;
        if conv_done = '1' then
          bcd_r <= conv_bcd;
        end if;
      end if;
    end if;
  end process;

  -- choose what each digit shows
  process (page, state, bcd_r, axis_sel, devid, wires3)
    variable d       : disp_t;
    variable h, t, u : natural range 0 to 15;
  begin
    d := BLANK_DISP;
    case page is
      when "00" =>
        case state is
          when S_ON_MSG  => d := WORD_ON;
          when S_OFF_MSG => d := WORD_OFF;
          when S_NORMAL  => d := WORD_SAFE;
          when S_ALERT   => d := WORD_ALERT;
          when S_DROP    => d := WORD_DROP;
          when S_OFF     => d := BLANK_DISP;
        end case;
      when "01" =>
        d(5) := SEG_d;
        h := to_integer(unsigned(bcd_r(11 downto 8)));
        t := to_integer(unsigned(bcd_r(7 downto 4)));
        u := to_integer(unsigned(bcd_r(3 downto 0)));
        if h /= 0 then d(2) := seg_hex(h); end if;
        if h /= 0 or t /= 0 then d(1) := seg_hex(t); end if;
        d(0) := seg_hex(u);
      when "10" =>
        d(5) := SEG_A;
        d(4) := seg_hex(to_integer(unsigned(axis_sel)));
        for i in 0 to 3 loop
          d(i) := seg_hex(to_integer(unsigned(bcd_r(4 * i + 3 downto 4 * i))));
        end loop;
      when others =>
        d(5) := SEG_d;
        if wires3 = '1' then d(3) := seg_hex(3); else d(3) := seg_hex(4); end if;
        d(1) := seg_hex(to_integer(unsigned(devid(7 downto 4))));
        d(0) := seg_hex(to_integer(unsigned(devid(3 downto 0))));
    end case;
    seg_c <= pack(d);
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      seg_r <= seg_c;
    end if;
  end process;

  seg <= seg_r;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/stick_fsm.vhd
-- ======================================================================
-------------------------------------------------------------------------------
-- stick_fsm.vhd : main control FSM of the Smart Blind Stick (spec tasks 1-3, 8, 10, 12)
--
--   S_OFF      switch off, everything disabled, display blank
--   S_ON_MSG   "ON"  shown for MSG_MS, then -> S_NORMAL           (task 2)
--   S_NORMAL   monitoring surroundings                             (task 4)
--   S_ALERT    obstacle ahead  (display ALERT, motor, LED)         (task 5)
--   S_DROP     stick dropped   (display DROP, buzzer, blinking LED)(task 7)
--   S_OFF_MSG  "OFF" shown for MSG_MS, then -> S_OFF               (task 3)
--
-- Priorities: switch OFF > DROP > ALERT > NORMAL.
-- Recovery from DROP needs BOTH the recovery button AND the recovery
-- condition (stick lifted upright again)                          (tasks 7d, 10)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.stick_pkg.all;

entity stick_fsm is
  generic (MSG_MS : positive := 2000);
  port (clk        : in  std_logic;
        rst_n      : in  std_logic;
        tick_ms    : in  std_logic;
        sw_on      : in  std_logic;       -- debounced ON/OFF switch ('1' = ON)
        obstacle   : in  std_logic;       -- filtered obstacle flag
        drop_event : in  std_logic;       -- 1-clk pulse from drop_detect
        upright    : in  std_logic;       -- recovery condition
        key_clear  : in  std_logic;       -- 1-clk pulse: recovery button pressed
        state      : out state_t);
end entity stick_fsm;

architecture rtl of stick_fsm is
  signal st      : state_t := S_OFF;
  signal msg_cnt : integer range 0 to MSG_MS := 0;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        st      <= S_OFF;
        msg_cnt <= 0;
      else
        case st is

          when S_OFF =>
            if sw_on = '1' then
              st <= S_ON_MSG; msg_cnt <= 0;
            end if;

          when S_ON_MSG =>
            if sw_on = '0' then
              st <= S_OFF_MSG; msg_cnt <= 0;
            elsif tick_ms = '1' then
              if msg_cnt = MSG_MS - 1 then
                st <= S_NORMAL; msg_cnt <= 0;
              else
                msg_cnt <= msg_cnt + 1;
              end if;
            end if;

          when S_NORMAL =>
            if sw_on = '0' then
              st <= S_OFF_MSG; msg_cnt <= 0;
            elsif drop_event = '1' then
              st <= S_DROP;
            elsif obstacle = '1' then
              st <= S_ALERT;
            end if;

          when S_ALERT =>
            if sw_on = '0' then
              st <= S_OFF_MSG; msg_cnt <= 0;
            elsif drop_event = '1' then
              st <= S_DROP;
            elsif obstacle = '0' then
              st <= S_NORMAL;
            end if;

          when S_DROP =>
            if sw_on = '0' then
              st <= S_OFF_MSG; msg_cnt <= 0;
            elsif key_clear = '1' and upright = '1' then
              st <= S_NORMAL;
            end if;

          when S_OFF_MSG =>
            if sw_on = '1' then
              st <= S_ON_MSG; msg_cnt <= 0;
            elsif tick_ms = '1' then
              if msg_cnt = MSG_MS - 1 then
                st <= S_OFF; msg_cnt <= 0;
              else
                msg_cnt <= msg_cnt + 1;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

  state <= st;
end architecture rtl;

-- ======================================================================
-- FILE: rtl/blind_stick_top.vhd
-- ======================================================================
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
