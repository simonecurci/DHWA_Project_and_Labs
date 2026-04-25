-- ================================================================================ --
-- NEORV32 - Test Setup with Matrix Accelerator (SLINK) for FPGA Deployment         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_test_setup_bootloader is
  generic (
    CLOCK_FREQUENCY : natural := 100000000; -- clock frequency of clk_i in Hz
    IMEM_SIZE       : natural := 16*1024;   -- size of processor-internal instruction memory in bytes
    DMEM_SIZE       : natural := 8*1024     -- size of processor-internal data memory in bytes
  );
  port (
    -- Global control --
    clk_i       : in  std_ulogic; -- global clock, rising edge
    rstn_i      : in  std_ulogic; -- global reset, low-active, async
    -- GPIO --
    gpio_o      : out std_ulogic_vector(7 downto 0); -- parallel output
    -- UART0 --
    uart0_txd_o : out std_ulogic; -- UART0 send data
    uart0_rxd_i : in  std_ulogic  -- UART0 receive data
  );
end entity;

architecture neorv32_test_setup_bootloader_rtl of neorv32_test_setup_bootloader is

  -- Internal Signals --
  signal con_gpio_out : std_ulogic_vector(31 downto 0);

  -- SLINK Internal Interconnect (Wiring between CPU and Accelerator) --
  signal slink_tx_dat : std_ulogic_vector(31 downto 0);
  signal slink_tx_val : std_ulogic;
  signal slink_tx_rdy : std_ulogic;
  
  signal slink_rx_dat : std_ulogic_vector(31 downto 0);
  signal slink_rx_val : std_ulogic;
  signal slink_rx_rdy : std_ulogic;

begin

  -- ========================================================================
  -- 1. NEORV32 Processor Core
  -- ========================================================================
  neorv32_top_inst: neorv32_top
  generic map (
    -- Clocking --
    CLOCK_FREQUENCY   => CLOCK_FREQUENCY,
    -- Boot Configuration --
    BOOT_MODE_SELECT  => 2,                -- boot via internal bootloader
    -- RISC-V CPU Extensions --
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zicntr  => true,
    -- Internal Instruction memory --
    IMEM_EN           => true,
    IMEM_SIZE         => IMEM_SIZE,
    -- Internal Data memory --
    DMEM_EN           => true,
    DMEM_SIZE         => DMEM_SIZE,
    -- Processor peripherals --
    IO_GPIO_NUM       => 8,
    IO_CLINT_EN       => true,
    IO_UART0_EN       => true,
    
    -- [MODIFICATION] Enable SLINK Interface and set FIFO sizes --
    IO_SLINK_EN       => true,
    IO_SLINK_TX_FIFO  => 256, -- Match the size used in your optimized C code
    IO_SLINK_RX_FIFO  => 128  -- Match the size used in your optimized C code
  )
  port map (
    -- Global control --
    clk_i           => clk_i,
    rstn_i          => rstn_i,
    
    -- GPIO --
    gpio_o          => con_gpio_out,
    
    -- UART0 --
    uart0_txd_o     => uart0_txd_o,
    uart0_rxd_i     => uart0_rxd_i,

    -- [MODIFICATION] Connect SLINK to internal signals --
    -- TX Stream (CPU Output)
    slink_tx_dat_o  => slink_tx_dat,
    slink_tx_val_o  => slink_tx_val,
    slink_tx_rdy_i  => slink_tx_rdy,
    slink_tx_lst_o  => open, -- End-of-stream not used
    slink_tx_dst_o  => open, -- Routing not used
    
    -- RX Stream (CPU Input)
    slink_rx_dat_i  => slink_rx_dat,
    slink_rx_val_i  => slink_rx_val,
    slink_rx_rdy_o  => slink_rx_rdy,
    slink_rx_lst_i  => '0',  -- Tie unused inputs to ground
    slink_rx_src_i  => (others => '0')
  );

  -- ========================================================================
  -- 2. Custom Matrix Multiplication Accelerator
  -- ========================================================================
  matrix_accelerator_inst: entity work.matrix_mul_slink
  port map (
    clk_i      => clk_i,
    rstn_i     => rstn_i,

    -- RX Stream (Receives data FROM CPU)
    rx_data_i  => slink_tx_dat,
    rx_valid_i => slink_tx_val,
    rx_ready_o => slink_tx_rdy,

    -- TX Stream (Sends results TO CPU)
    tx_data_o  => slink_rx_dat,
    tx_valid_o => slink_rx_val,
    tx_ready_i => slink_rx_rdy
  );

  -- GPIO output connection --
  gpio_o <= con_gpio_out(7 downto 0);

end architecture;