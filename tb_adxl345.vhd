-------------------------------------------------------------------------------
-- tb_adxl345.vhd : self-checking test of adxl345_ctrl + spi_master at the REAL
-- 50 MHz clock (SPI = 1 MHz). Two sensors are simulated side by side:
--   A : healthy ADXL345 (DEVID = 0xE5)  -> must be initialised and polled
--   B : wrong DEVID (0x00)              -> must NOT be initialised / never produce samples
--   C : SDO dead (reads 0xFF), chip in 4-wire default -> must fall back to 3-wire and work
--   D : chip already in 3-wire (FPGA re-programmed, board not power-cycled) -> must recover
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_adxl345 is
  generic (CLK_HZ : positive := 50_000_000);
end entity tb_adxl345;

architecture sim of tb_adxl345 is
  constant CLK_PERIOD : time := 1 sec / CLK_HZ;
  signal clk, rst_n, tick_ms : std_logic := '0';
  signal done : boolean := false;

  signal ax_t, ay_t, az_t : integer := 0;

  signal cs_a, sclk_a, mosi_a, miso_a : std_logic;
  signal axa, aya, aza : signed(15 downto 0);
  signal valid_a, ok_a : std_logic;
  signal devid_a : std_logic_vector(7 downto 0);
  signal fmt_a, bw_a, pwr_a : std_logic_vector(7 downto 0);
  signal bursts_a : integer;
  signal n_valid_a : integer := 0;

  signal cs_b, sclk_b, mosi_b, miso_b : std_logic;
  signal axb, ayb, azb : signed(15 downto 0);
  signal valid_b, ok_b : std_logic;
  signal devid_b : std_logic_vector(7 downto 0);
  signal fmt_b, bw_b, pwr_b : std_logic_vector(7 downto 0);
  signal bursts_b : integer;
  signal n_valid_b : integer := 0;

  signal cs_c, sclk_c, sdi_c, miso_c : std_logic;
  signal axc, ayc, azc : signed(15 downto 0);
  signal valid_c, ok_c, w3_c : std_logic;
  signal devid_c : std_logic_vector(7 downto 0);
  signal fmt_c, bw_c, pwr_c : std_logic_vector(7 downto 0);
  signal bursts_c : integer;
  signal n_valid_c : integer := 0;

  signal cs_d, sclk_d, sdi_d, miso_d : std_logic;
  signal axd, ayd, azd : signed(15 downto 0);
  signal valid_d, ok_d, w3_d : std_logic;
  signal devid_d : std_logic_vector(7 downto 0);
  signal fmt_d, bw_d, pwr_d : std_logic_vector(7 downto 0);
  signal bursts_d : integer;
  signal n_valid_d : integer := 0;

  signal w3_a, w3_b : std_logic;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done else clk;

  u_tick : entity work.tick_gen generic map (DIV => CLK_HZ / 1000)
    port map (clk => clk, rst_n => rst_n, tick => tick_ms);

  -- device A (healthy)
  dut_a : entity work.adxl345_ctrl
    generic map (CLK_HZ => CLK_HZ)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, cs_n => cs_a, sclk => sclk_a,
              sdi => mosi_a, sdo => miso_a, wires3 => w3_a, ax => axa, ay => aya, az => aza,
              sample_valid => valid_a, dev_ok => ok_a, devid => devid_a);
  mod_a : entity work.adxl345_model
    port map (cs_n => cs_a, sclk => sclk_a, mosi => mosi_a, miso => miso_a,
              ax => ax_t, ay => ay_t, az => az_t, devid_val => x"E5",
              reg_data_format => fmt_a, reg_bw_rate => bw_a, reg_power_ctl => pwr_a,
              burst_reads => bursts_a);

  -- device B (wrong ID)
  dut_b : entity work.adxl345_ctrl
    generic map (CLK_HZ => CLK_HZ)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, cs_n => cs_b, sclk => sclk_b,
              sdi => mosi_b, sdo => miso_b, wires3 => w3_b, ax => axb, ay => ayb, az => azb,
              sample_valid => valid_b, dev_ok => ok_b, devid => devid_b);
  mod_b : entity work.adxl345_model
    port map (cs_n => cs_b, sclk => sclk_b, mosi => mosi_b, miso => miso_b,
              ax => ax_t, ay => ay_t, az => az_t, devid_val => x"00",
              reg_data_format => fmt_b, reg_bw_rate => bw_b, reg_power_ctl => pwr_b,
              burst_reads => bursts_b);

  -- device C (SDO dead, chip in power-up 4-wire mode)
  dut_c : entity work.adxl345_ctrl
    generic map (CLK_HZ => CLK_HZ)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, cs_n => cs_c, sclk => sclk_c,
              sdi => sdi_c, sdo => miso_c, wires3 => w3_c, ax => axc, ay => ayc, az => azc,
              sample_valid => valid_c, dev_ok => ok_c, devid => devid_c);
  mod_c : entity work.adxl345_model
    generic map (SDO_WORKS => false)
    port map (cs_n => cs_c, sclk => sclk_c, mosi => sdi_c, miso => miso_c,
              ax => ax_t, ay => ay_t, az => az_t, devid_val => x"E5",
              reg_data_format => fmt_c, reg_bw_rate => bw_c, reg_power_ctl => pwr_c,
              burst_reads => bursts_c);

  -- device D (chip already left in 3-wire mode by a previous run)
  dut_d : entity work.adxl345_ctrl
    generic map (CLK_HZ => CLK_HZ)
    port map (clk => clk, rst_n => rst_n, tick_ms => tick_ms, cs_n => cs_d, sclk => sclk_d,
              sdi => sdi_d, sdo => miso_d, wires3 => w3_d, ax => axd, ay => ayd, az => azd,
              sample_valid => valid_d, dev_ok => ok_d, devid => devid_d);
  mod_d : entity work.adxl345_model
    generic map (INIT_FMT => x"4B")
    port map (cs_n => cs_d, sclk => sclk_d, mosi => sdi_d, miso => miso_d,
              ax => ax_t, ay => ay_t, az => az_t, devid_val => x"E5",
              reg_data_format => fmt_d, reg_bw_rate => bw_d, reg_power_ctl => pwr_d,
              burst_reads => bursts_d);

  process (clk)
  begin
    if rising_edge(clk) then
      if valid_c = '1' then n_valid_c <= n_valid_c + 1; end if;
      if valid_d = '1' then n_valid_d <= n_valid_d + 1; end if;
      if valid_a = '1' then n_valid_a <= n_valid_a + 1; end if;
      if valid_b = '1' then n_valid_b <= n_valid_b + 1; end if;
    end if;
  end process;

  main : process
    variable n0 : integer;
  begin
    ax_t <= 100; ay_t <= -50; az_t <= 256;
    rst_n <= '0';
    wait for 20 * CLK_PERIOD;
    rst_n <= '1';

    wait for 80 ms;                                  -- boot 20 ms + init + warm-up samples
    assert ok_a = '1' and devid_a = x"E5" report "A: DEVID not recognised" severity failure;
    assert fmt_a = x"0B" report "A: DATA_FORMAT not 0x0B" severity failure;
    assert w3_a = '0' report "A: healthy 4-wire chip must stay in 4-wire mode" severity failure;
    assert bw_a  = x"0B" report "A: BW_RATE not 0x0B" severity failure;
    assert pwr_a = x"08" report "A: POWER_CTL not 0x08 (Measure)" severity failure;
    report "A: init sequence OK (DEVID=E5, FMT=0B, BW=0B, PWR=08)" severity note;

    assert axa = to_signed(100, 16) and aya = to_signed(-50, 16) and aza = to_signed(256, 16)
      report "A: sample mismatch (positive/negative values)" severity failure;
    report "A: sample values OK" severity note;

    ax_t <= -256; ay_t <= 4095; az_t <= -4096;       -- sign extension and 13-bit extremes
    wait for 30 ms;
    assert axa = to_signed(-256, 16) and aya = to_signed(4095, 16) and aza = to_signed(-4096, 16)
      report "A: extreme values mismatch" severity failure;
    report "A: sign extension / extremes OK" severity note;

    n0 := n_valid_a;
    wait for 200 ms;
    assert (n_valid_a - n0) >= 18 and (n_valid_a - n0) <= 20
      report "A: sample rate not ~100 Hz, got " & integer'image(n_valid_a - n0) & " in 200 ms"
      severity failure;
    report "A: sample rate " & integer'image(n_valid_a - n0) & " per 200 ms (~100 Hz) OK" severity note;

    -- B: wrong ID => never configured, never reports samples, keeps retrying
    assert ok_b = '0' report "B: dev_ok must stay 0 with wrong DEVID" severity failure;
    assert n_valid_b = 0 report "B: no samples may be produced" severity failure;
    assert pwr_b = x"00" report "B: POWER_CTL must not be written (never measuring)" severity failure;
    assert bursts_b = 0 report "B: must not burst-read data" severity failure;
    report "B: wrong-DEVID handling OK" severity note;

    -- C: dead SDO -> automatic 3-wire fallback
    assert ok_c = '1' and devid_c = x"E5" report "C: 3-wire fallback did not find the chip" severity failure;
    assert w3_c = '1' report "C: must be running in 3-wire mode" severity failure;
    assert fmt_c = x"4B" report "C: DATA_FORMAT must be 0x4B (3-wire, full-res, +-16 g)" severity failure;
    assert bw_c = x"0B" and pwr_c = x"08" report "C: init sequence incomplete in 3-wire" severity failure;
    assert axc = to_signed(-256, 16) and ayc = to_signed(4095, 16) and azc = to_signed(-4096, 16)
      report "C: 3-wire sample values wrong" severity failure;
    assert n_valid_c > 0 report "C: no samples in 3-wire mode" severity failure;
    report "C: dead-SDO -> 3-wire fallback OK (values match)" severity note;

    -- D: chip already in 3-wire, FPGA starts in 4-wire
    assert ok_d = '1' and devid_d = x"E5" and w3_d = '1' report "D: did not recover from 3-wire chip" severity failure;
    assert fmt_d = x"4B" and pwr_d = x"08" report "D: registers wrong after recovery" severity failure;
    assert axd = to_signed(-256, 16) and ayd = to_signed(4095, 16) and azd = to_signed(-4096, 16)
      report "D: samples wrong after recovery" severity failure;
    report "D: recovery from chip left in 3-wire mode OK" severity note;

    report "tb_adxl345: ALL TESTS PASSED" severity note;
    done <= true;
    wait;
  end process;
end architecture sim;
