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
