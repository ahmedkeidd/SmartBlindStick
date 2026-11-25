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
