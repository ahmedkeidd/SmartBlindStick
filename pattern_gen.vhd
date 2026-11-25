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
