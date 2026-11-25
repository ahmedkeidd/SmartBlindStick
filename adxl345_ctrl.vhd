-------------------------------------------------------------------------------
-- adxl345_ctrl.vhd : initialises the on-board ADXL345 accelerometer over SPI
-- (mode 3) and then reads X/Y/Z every POLL_MS milliseconds.
--
-- WIRE MODE (automatic): power-up default is 4-wire (data out on SDO). If the DEVID
-- read does not return 0xE5 the controller switches the chip to 3-wire (DATA_FORMAT
-- bit 6 = 1, data comes back on the bidirectional SDI/SDIO pin, which is what the
-- Terasic demo uses) and tries again, alternating every RETRY_MS until it works.
--
-- Start-up sequence (each line = one CS-low transaction):
--   1. read  0x00 DEVID       -> must be 0xE5, else retry every RETRY_MS
--   2. write 0x31 DATA_FORMAT = 0x0B  (FULL_RES=1, +-16 g, SPI bit 0 = 4-wire)
--                          or 0x4B  (same, SPI bit 1 = 3-wire)
--   3. write 0x2C BW_RATE     = 0x0B  (200 Hz output data rate)
--   4. write 0x2D POWER_CTL   = 0x08  (Measure = 1)
--   5. forever: burst-read 6 bytes from 0x32 (cmd 0xF2) = X0 X1 Y0 Y1 Z0 Z1
-- Full-resolution mode => 256 LSB per g on every axis (1 LSB = 3.9 mg).
-- The first WARMUP_SAMPLES readings are discarded (registers read 0 until the
-- first conversion completes).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adxl345_ctrl is
  generic (CLK_HZ         : positive := 50_000_000;
           SPI_HZ         : positive := 1_000_000;
           POLL_MS        : positive := 10;
           BOOT_MS        : positive := 20;
           RETRY_MS       : positive := 100;
           WARMUP_SAMPLES : natural  := 5);
  port (clk          : in  std_logic;
        rst_n        : in  std_logic;
        tick_ms      : in  std_logic;
        cs_n         : out std_logic;
        sclk         : out std_logic;
        sdi          : inout std_logic;                  -- MOSI (4-wire) / SDIO (3-wire)
        sdo          : in  std_logic;                    -- MISO in 4-wire mode
        wires3       : out std_logic;                    -- '1' = running in 3-wire mode
        ax, ay, az   : out signed(15 downto 0);
        sample_valid : out std_logic;                    -- 1-clk pulse per new sample
        dev_ok       : out std_logic;                    -- DEVID == 0xE5 seen
        devid        : out std_logic_vector(7 downto 0));
end entity adxl345_ctrl;

architecture rtl of adxl345_ctrl is
  function imax (a, b : integer) return integer is
  begin
    if a > b then return a; else return b; end if;
  end function;

  constant HALF_DIV : positive := imax(2, CLK_HZ / (2 * SPI_HZ));
  constant GAP_CYC  : positive := 12;                    -- CS high time > 150 ns @ 50 MHz

  type st_t is (ST_BOOT, ST_CS_LOW, ST_SEND, ST_WAIT_BYTE, ST_CS_HIGH,
                ST_NEXT, ST_POLL_WAIT, ST_RETRY_WAIT);
  signal st     : st_t := ST_BOOT;
  signal txn    : integer range 0 to 4 := 0;             -- 0 DEVID,1 FMT,2 BW,3 PWR,4 DATA
  signal bidx   : integer range 0 to 7 := 0;             -- byte index inside transaction
  signal ms_cnt : integer range 0 to 1023 := 0;
  signal gap    : integer range 0 to 15 := 0;
  signal warm   : integer range 0 to 255 := 0;

  type bytes_t is array (0 to 5) of std_logic_vector(7 downto 0);
  signal raw     : bytes_t := (others => (others => '0'));
  signal devid_r : std_logic_vector(7 downto 0) := (others => '0');
  signal ax_r, ay_r, az_r : signed(15 downto 0) := (others => '0');
  signal ok_r, valid_r    : std_logic := '0';
  signal cs_r             : std_logic := '1';
  signal mode3_r          : std_logic := '0';          -- 0 = 4-wire, 1 = 3-wire
  signal sp_rd, sp_oe     : std_logic := '0';
  signal mosi_s, miso_i   : std_logic;

  signal sp_start, sp_busy, sp_done : std_logic;
  signal sp_tx, sp_rx               : std_logic_vector(7 downto 0);
  signal oe_comb                    : std_logic;

  function tx_of (t : integer; i : integer) return std_logic_vector is
  begin
    if i = 0 then
      case t is
        when 0      => return x"80";     -- read  DEVID
        when 1      => return x"31";     -- write DATA_FORMAT
        when 2      => return x"2C";     -- write BW_RATE
        when 3      => return x"2D";     -- write POWER_CTL
        when others => return x"F2";     -- read burst from 0x32 (R=1, MB=1)
      end case;
    else
      case t is
        when 1      => return x"0B";
        when 2      => return x"0B";
        when 3      => return x"08";
        when others => return x"00";     -- dummy byte while reading
      end case;
    end if;
  end function;

  function nbytes_of (t : integer) return integer is
  begin
    if t = 4 then return 7; else return 2; end if;
  end function;
begin
  u_spi : entity work.spi_master
    generic map (HALF_DIV => HALF_DIV)
    port map (clk => clk, rst_n => rst_n, start => sp_start, tx_byte => sp_tx,
              rd => sp_rd, three_wire => mode3_r,
              rx_byte => sp_rx, busy => sp_busy, done => sp_done,
              sclk => sclk, mosi => mosi_s, mosi_oe => sp_oe, miso => miso_i);

  -- SDI/SDIO pin: we drive it except while the chip is sending (3-wire read byte),
  -- plus a short hold-off after CS rises so we never fight the chip releasing the line.
  oe_comb <= '1' when (cs_r = '1' and not (st = ST_CS_HIGH and gap < 3)) else sp_oe;
  sdi     <= mosi_s when oe_comb = '1' else 'Z';
  miso_i  <= sdi when mode3_r = '1' else sdo;
  wires3  <= mode3_r;

  process (clk)
  begin
    if rising_edge(clk) then
      sp_start <= '0';
      valid_r  <= '0';
      if rst_n = '0' then
        st <= ST_BOOT; txn <= 0; ms_cnt <= 0; gap <= 0; cs_r <= '1'; ok_r <= '0'; warm <= 0;
        mode3_r <= '0'; sp_rd <= '0';
      else
        case st is

          when ST_BOOT =>                                  -- let the sensor power up
            if tick_ms = '1' then
              if ms_cnt = BOOT_MS - 1 then
                ms_cnt <= 0; txn <= 0; st <= ST_CS_LOW;
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

          when ST_CS_LOW =>
            cs_r <= '0';
            bidx <= 0;
            if gap = 2 then gap <= 0; st <= ST_SEND; else gap <= gap + 1; end if;

          when ST_SEND =>
            sp_start <= '1';
            sp_tx    <= tx_of(txn, bidx);
            if txn = 1 and bidx = 1 then                   -- DATA_FORMAT: SPI bit follows the mode
              if mode3_r = '1' then sp_tx <= x"4B"; else sp_tx <= x"0B"; end if;
            end if;
            if (txn = 0 or txn = 4) and bidx >= 1 then sp_rd <= '1'; else sp_rd <= '0'; end if;
            st       <= ST_WAIT_BYTE;

          when ST_WAIT_BYTE =>
            if sp_done = '1' then
              if bidx >= 1 then
                if txn = 0 then
                  devid_r <= sp_rx;
                elsif txn = 4 then
                  raw(bidx - 1) <= sp_rx;
                end if;
              end if;
              if bidx = nbytes_of(txn) - 1 then
                st <= ST_CS_HIGH;
              else
                bidx <= bidx + 1;
                st   <= ST_SEND;
              end if;
            end if;

          when ST_CS_HIGH =>
            cs_r <= '1';
            if gap = GAP_CYC - 1 then gap <= 0; st <= ST_NEXT; else gap <= gap + 1; end if;

          when ST_NEXT =>
            case txn is
              when 0 =>
                if devid_r = x"E5" then
                  ok_r <= '1'; txn <= 1; st <= ST_CS_LOW;
                else
                  ok_r <= '0'; ms_cnt <= 0; mode3_r <= not mode3_r; st <= ST_RETRY_WAIT;
                end if;
              when 1 =>
                if ok_r = '1' then txn <= 2; else txn <= 0; end if;   -- probing: re-read DEVID
                st <= ST_CS_LOW;
              when 2 =>
                txn <= 3; st <= ST_CS_LOW;
              when 3 =>
                txn <= 4; warm <= 0; ms_cnt <= 0; st <= ST_POLL_WAIT;
              when others =>                               -- txn = 4: a sample is ready
                ax_r <= signed(std_logic_vector'(raw(1) & raw(0)));
                ay_r <= signed(std_logic_vector'(raw(3) & raw(2)));
                az_r <= signed(std_logic_vector'(raw(5) & raw(4)));
                if warm < WARMUP_SAMPLES then
                  warm <= warm + 1;
                else
                  valid_r <= '1';
                end if;
                ms_cnt <= 0; st <= ST_POLL_WAIT;
            end case;

          when ST_POLL_WAIT =>
            if tick_ms = '1' then
              if ms_cnt = POLL_MS - 1 then
                ms_cnt <= 0; txn <= 4; st <= ST_CS_LOW;
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

          when ST_RETRY_WAIT =>
            if tick_ms = '1' then
              if ms_cnt = RETRY_MS - 1 then
                ms_cnt <= 0; txn <= 1; st <= ST_CS_LOW;   -- set the new wire mode, then re-read DEVID
              else
                ms_cnt <= ms_cnt + 1;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

  cs_n         <= cs_r;
  ax           <= ax_r;
  ay           <= ay_r;
  az           <= az_r;
  sample_valid <= valid_r;
  dev_ok       <= ok_r;
  devid        <= devid_r;
end architecture rtl;
