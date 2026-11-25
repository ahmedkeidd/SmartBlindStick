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
