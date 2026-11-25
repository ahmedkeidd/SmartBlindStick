-------------------------------------------------------------------------------
-- spi_master.vhd : byte-wide SPI master, MODE 3 (CPOL=1, CPHA=1), MSB first.
--   * SCLK idles HIGH. MOSI changes when SCLK falls; MISO is sampled just
--     before SCLK rises (ADXL345 shifts data out on the falling edge).
--   * Chip-select is handled by the caller so several bytes can share one CS.
--   * SCLK period = 2 * HALF_DIV clocks.
--   * 3-wire support: when three_wire='1' and rd='1' the byte is a DATA-READ byte
--     and mosi_oe goes low for the whole byte, so the caller can release the
--     bidirectional SDIO line and let the ADXL345 drive it.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity spi_master is
  generic (HALF_DIV : positive := 25);           -- 50 MHz / (2*25) = 1 MHz SCLK
  port (clk     : in  std_logic;
        rst_n   : in  std_logic;
        start   : in  std_logic;                 -- 1-clk pulse (ignored while busy)
        tx_byte : in  std_logic_vector(7 downto 0);
        rd         : in  std_logic := '0';       -- this byte carries data FROM the slave
        three_wire : in  std_logic := '0';       -- SDI doubles as data-out (SDIO)
        rx_byte : out std_logic_vector(7 downto 0);
        busy    : out std_logic;
        done    : out std_logic;                 -- 1-clk pulse, rx_byte valid
        sclk    : out std_logic;
        mosi    : out std_logic;
        mosi_oe : out std_logic;                 -- '0' = release the SDIO line
        miso    : in  std_logic);
end entity spi_master;

architecture rtl of spi_master is
  type st_t is (ST_IDLE, ST_LOW, ST_HIGH);
  signal st     : st_t := ST_IDLE;
  signal tmr    : integer range 0 to HALF_DIV - 1 := 0;
  signal bitn   : integer range 0 to 7 := 0;
  signal tx_sh  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_sh  : std_logic_vector(7 downto 0) := (others => '0');
  signal sclk_r : std_logic := '1';
  signal mosi_r : std_logic := '0';
  signal busy_r : std_logic := '0';
  signal done_r : std_logic := '0';
  signal miso_s : std_logic := '0';
  signal oe_r   : std_logic := '1';
begin
  process (clk)
  begin
    if rising_edge(clk) then
      miso_s <= miso;
      done_r <= '0';
      if rst_n = '0' then
        st <= ST_IDLE; sclk_r <= '1'; busy_r <= '0'; tmr <= 0; bitn <= 0;
      else
        case st is
          when ST_IDLE =>
            sclk_r <= '1';
            if start = '1' then
              tx_sh  <= tx_byte;
              oe_r   <= not (rd and three_wire);
              mosi_r <= tx_byte(7);
              bitn   <= 0;
              tmr    <= 0;
              sclk_r <= '0';                    -- first falling edge
              busy_r <= '1';
              st     <= ST_LOW;
            end if;

          when ST_LOW =>
            if tmr = HALF_DIV - 1 then
              tmr    <= 0;
              rx_sh  <= rx_sh(6 downto 0) & miso_s;   -- sample just before rising edge
              sclk_r <= '1';
              st     <= ST_HIGH;
            else
              tmr <= tmr + 1;
            end if;

          when ST_HIGH =>
            if tmr = HALF_DIV - 1 then
              tmr <= 0;
              if bitn = 7 then
                busy_r <= '0';
                done_r <= '1';
                st     <= ST_IDLE;
              else
                bitn   <= bitn + 1;
                tx_sh  <= tx_sh(6 downto 0) & '0';
                mosi_r <= tx_sh(6);
                sclk_r <= '0';
                st     <= ST_LOW;
              end if;
            else
              tmr <= tmr + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  sclk    <= sclk_r;
  mosi    <= mosi_r;
  mosi_oe <= oe_r;
  busy    <= busy_r;
  done    <= done_r;
  rx_byte <= rx_sh;
end architecture rtl;
