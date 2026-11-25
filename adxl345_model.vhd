-------------------------------------------------------------------------------
-- adxl345_model.vhd (SIMULATION ONLY) : behavioural ADXL345, SPI mode 3.
--  * 4-wire (DATA_FORMAT bit6 = 0, power-up default): data returns on MISO.
--  * 3-wire (DATA_FORMAT bit6 = 1): data returns on the shared SDIO pin and MISO is
--    high-Z, exactly like the real chip.
--  * SDO_WORKS = false emulates a board whose SDO path does not reach the FPGA (MISO
--    reads as all ones); INIT_FMT = x"4B" emulates a chip already left in 3-wire mode
--    (FPGA re-programmed without cycling the board power).
--  * Command byte: bit7 = R/W (1=read), bit6 = MB, bits5:0 = register address.
--  * Slave shifts data out on the falling SCLK edge, samples MOSI on the rising edge.
--  * Registers modelled: DEVID(0x00), BW_RATE(0x2C), POWER_CTL(0x2D),
--    DATA_FORMAT(0x31), DATAX0..DATAZ1(0x32..0x37).
--  * ax/ay/az are raw LSB values injected by the testbench (256 LSB = 1 g).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adxl345_model is
  generic (SDO_WORKS : boolean := true;
           INIT_FMT  : std_logic_vector(7 downto 0) := x"00");
  port (cs_n   : in  std_logic;
        sclk   : in  std_logic;
        mosi   : inout std_logic;                 -- SDI / SDIO
        miso   : out std_logic;
        ax, ay, az : in integer;
        devid_val  : in std_logic_vector(7 downto 0) := x"E5";
        reg_data_format : out std_logic_vector(7 downto 0);
        reg_bw_rate     : out std_logic_vector(7 downto 0);
        reg_power_ctl   : out std_logic_vector(7 downto 0);
        burst_reads     : out integer);
end entity adxl345_model;

architecture sim of adxl345_model is
  signal r_fmt : std_logic_vector(7 downto 0) := INIT_FMT;
  signal r_bw, r_pwr : std_logic_vector(7 downto 0) := (others => '0');
  signal n_burst : integer := 0;
begin
  reg_data_format <= r_fmt;
  reg_bw_rate     <= r_bw;
  reg_power_ctl   <= r_pwr;
  burst_reads     <= n_burst;

  process
    variable shin    : std_logic_vector(7 downto 0);
    variable outb    : std_logic_vector(7 downto 0);
    variable bitcnt  : integer;
    variable bytecnt : integer;
    variable addr    : integer;
    variable is_read : boolean;

    impure function rd_reg (a : integer) return std_logic_vector is
      variable v : std_logic_vector(15 downto 0);
    begin
      case a is
        when 16#00# => return devid_val;
        when 16#2C# => return r_bw;
        when 16#2D# => return r_pwr;
        when 16#31# => return r_fmt;
        when 16#32# => v := std_logic_vector(to_signed(ax, 16)); return v(7 downto 0);
        when 16#33# => v := std_logic_vector(to_signed(ax, 16)); return v(15 downto 8);
        when 16#34# => v := std_logic_vector(to_signed(ay, 16)); return v(7 downto 0);
        when 16#35# => v := std_logic_vector(to_signed(ay, 16)); return v(15 downto 8);
        when 16#36# => v := std_logic_vector(to_signed(az, 16)); return v(7 downto 0);
        when 16#37# => v := std_logic_vector(to_signed(az, 16)); return v(15 downto 8);
        when others => return x"00";
      end case;
    end function;
  begin
    miso <= 'Z';
    mosi <= 'Z';
    wait until falling_edge(cs_n);
    bitcnt := 0; bytecnt := 0; addr := 0; is_read := false;
    shin := (others => '0'); outb := (others => '0');

    tx_loop : loop
      wait on sclk, cs_n;
      if cs_n = '1' then
        miso <= 'Z'; mosi <= 'Z';                  -- CS high releases every output
        exit tx_loop;
      end if;

      if rising_edge(sclk) then
        shin   := shin(6 downto 0) & mosi;
        bitcnt := bitcnt + 1;
        if bitcnt = 8 then
          bitcnt := 0;
          if bytecnt = 0 then                         -- command byte
            is_read := (shin(7) = '1');
            addr    := to_integer(unsigned(shin(5 downto 0)));
            if is_read then
              outb := rd_reg(addr);
              if addr = 16#32# then n_burst <= n_burst + 1; end if;
            end if;
          else                                        -- data byte
            if is_read then
              addr := addr + 1;
              outb := rd_reg(addr);
            else
              case addr is
                when 16#2C# => r_bw  <= shin;
                when 16#2D# => r_pwr <= shin;
                when 16#31# => r_fmt <= shin;
                when others => null;
              end case;
              addr := addr + 1;
            end if;
          end if;
          bytecnt := bytecnt + 1;
        end if;
      elsif falling_edge(sclk) then
        if is_read and bytecnt >= 1 then
          if r_fmt(6) = '1' then                      -- 3-wire: drive SDIO, MISO released
            mosi <= outb(7 - bitcnt);
            miso <= 'Z';
          elsif SDO_WORKS then                        -- 4-wire
            miso <= outb(7 - bitcnt);
          else                                        -- SDO broken: line reads as ones
            miso <= '1';
          end if;
        else
          mosi <= 'Z';
          if r_fmt(6) = '1' then miso <= 'Z';
          elsif SDO_WORKS then miso <= '0';
          else miso <= '1'; end if;
        end if;
      end if;
    end loop tx_loop;
  end process;
end architecture sim;
