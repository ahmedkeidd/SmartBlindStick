-------------------------------------------------------------------------------
-- hcsr04_model.vhd (SIMULATION ONLY) : behavioural HC-SR04.
-- After a trigger pulse >= 10 us it waits 400 us, then raises ECHO for
-- dist_cm * 58 us (+30 us so the result sits mid-bin). dist_cm > 400 models
-- "no obstacle" (echo stays high ~38 ms). connected = '0' models a missing sensor.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity hcsr04_model is
  port (trig      : in  std_logic;
        echo      : out std_logic;
        dist_cm   : in  integer;
        connected : in  std_logic := '1');
end entity hcsr04_model;

architecture sim of hcsr04_model is
begin
  process
    variable t0 : time;
  begin
    echo <= '0';
    wait until rising_edge(trig);
    t0 := now;
    wait until falling_edge(trig);
    if (now - t0) >= 10 us and connected = '1' then
      wait for 400 us;
      echo <= '1';
      if dist_cm > 400 then
        wait for 38 ms;
      else
        wait for dist_cm * 58 us + 30 us;
      end if;
      echo <= '0';
    end if;
  end process;
end architecture sim;
