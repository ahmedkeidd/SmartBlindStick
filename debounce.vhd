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
