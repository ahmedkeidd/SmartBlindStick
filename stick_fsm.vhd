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
