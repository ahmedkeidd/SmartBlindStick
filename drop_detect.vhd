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
