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
