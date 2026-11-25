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
