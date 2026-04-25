-- ================================================================================ --
-- Hardware Accelerator: Matrix Multiplication via Stream Link (SLINK)              --
-- 10x10 Matrix Multiplication Unit with AXI4-Stream-like Valid/Ready Handshake     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity matrix_mul_slink is
  port (
    -- Global Control --
    clk_i      : in  std_ulogic; -- Global clock
    rstn_i     : in  std_ulogic; -- Global reset, active-low, synchronous/asynchronous

    -- RX Stream Interface (Data FROM CPU/SLINK TO Accelerator) --
    rx_data_i  : in  std_ulogic_vector(31 downto 0);
    rx_valid_i : in  std_ulogic; -- CPU has valid data to send
    rx_ready_o : out std_ulogic; -- Accelerator is ready to receive

    -- TX Stream Interface (Data FROM Accelerator TO CPU/SLINK) --
    tx_data_o  : out std_ulogic_vector(31 downto 0);
    tx_valid_o : out std_ulogic; -- Accelerator has valid result to send
    tx_ready_i : in  std_ulogic  -- CPU is ready to receive
  );
end matrix_mul_slink;

architecture rtl of matrix_mul_slink is

  -- ========================================================================
  -- 1. Internal Memories
  -- ========================================================================
  -- We need to store the input matrices. Matrix C is not stored; 
  -- it is streamed out immediately as soon as a single dot-product is ready.
  type ram_t is array (0 to 99) of std_ulogic_vector(31 downto 0);
  signal mat_a : ram_t;
  signal mat_b : ram_t;

  -- ========================================================================
  -- 2. FSM and Control Signals
  -- ========================================================================
  type state_t is (
    S_LOAD_A,      -- Stream in 100 elements for Matrix A
    S_LOAD_B,      -- Stream in 100 elements for Matrix B
    S_FETCH,       -- 1-cycle delay to read from RAM
    S_MAC,         -- Multiply and Accumulate
    S_STREAM_OUT   -- Send the computed element of Matrix C back to CPU
  );
  signal state : state_t;

  -- Counters and Indices
  signal load_cnt : integer range 0 to 100;
  signal i_idx    : integer range 0 to 10; -- Row index for Mat A and C
  signal j_idx    : integer range 0 to 10; -- Col index for Mat B and C
  signal k_idx    : integer range 0 to 10; -- Dot product index

  -- Computation Signals
  signal acc      : signed(31 downto 0);
  signal a_data   : std_ulogic_vector(31 downto 0);
  signal b_data   : std_ulogic_vector(31 downto 0);

begin

  -- ========================================================================
  -- Combinational Logic: RAM Read Addresses
  -- ========================================================================
  -- Continuous read assignment. The data will be valid 1 cycle after the 
  -- indices (i_idx, j_idx, k_idx) are updated.
  a_data <= mat_a(i_idx * 10 + k_idx);
  b_data <= mat_b(k_idx * 10 + j_idx);

  -- ========================================================================
  -- Main Process: FSM & Datapath
  -- ========================================================================
  fsm_process: process(clk_i, rstn_i)
    variable mult_res : signed(63 downto 0);
  begin
    -- Asynchronous Reset
    if (rstn_i = '0') then
      state      <= S_LOAD_A;
      rx_ready_o <= '0';
      tx_valid_o <= '0';
      tx_data_o  <= (others => '0');
      
      load_cnt   <= 0;
      i_idx      <= 0;
      j_idx      <= 0;
      k_idx      <= 0;
      acc        <= (others => '0');

    elsif rising_edge(clk_i) then
      
      -- Default output values to prevent unwanted latches/glitches
      rx_ready_o <= '0';
      tx_valid_o <= '0';

      case state is

        -- ------------------------------------------------------------
        -- STATE: LOAD MATRIX A
        -- ------------------------------------------------------------
        when S_LOAD_A =>
          rx_ready_o <= '1'; -- Tell SLINK we are ready to accept data
          
          if (rx_valid_i = '1') then -- Successful Handshake
            mat_a(load_cnt) <= rx_data_i;
            
            if (load_cnt = 99) then
              load_cnt <= 0;
              state    <= S_LOAD_B; -- Move to Matrix B
            else
              load_cnt <= load_cnt + 1;
            end if;
          end if;

        -- ------------------------------------------------------------
        -- STATE: LOAD MATRIX B
        -- ------------------------------------------------------------
        when S_LOAD_B =>
          rx_ready_o <= '1'; -- Tell SLINK we are ready to accept data
          
          if (rx_valid_i = '1') then -- Successful Handshake
            mat_b(load_cnt) <= rx_data_i;
            
            if (load_cnt = 99) then
              load_cnt <= 0;
              i_idx    <= 0;
              j_idx    <= 0;
              k_idx    <= 0;
              acc      <= (others => '0');
              state    <= S_FETCH; -- Start Computation
            else
              load_cnt <= load_cnt + 1;
            end if;
          end if;

        -- ------------------------------------------------------------
        -- STATE: FETCH
        -- ------------------------------------------------------------
        -- Wait 1 clock cycle for the RAMs to output the data based on 
        -- the current i_idx, j_idx, and k_idx.
        when S_FETCH =>
          state <= S_MAC;

        -- ------------------------------------------------------------
        -- STATE: MULTIPLY & ACCUMULATE (MAC)
        -- ------------------------------------------------------------
        when S_MAC =>
          -- Perform 32x32 -> 64 bit multiplication, then truncate and add to 32 bit accumulator
          mult_res := signed(a_data) * signed(b_data);
          acc      <= acc + mult_res(31 downto 0);
          
          -- Check if the 10-element dot product for the current C cell is complete
          if (k_idx = 9) then
            state <= S_STREAM_OUT; -- Result is ready, send it to CPU
          else
            k_idx <= k_idx + 1;
            state <= S_FETCH;      -- Fetch next elements for dot product
          end if;

        -- ------------------------------------------------------------
        -- STATE: STREAM OUT RESULT
        -- ------------------------------------------------------------
        when S_STREAM_OUT =>
          tx_data_o  <= std_ulogic_vector(acc);
          tx_valid_o <= '1'; -- Tell SLINK we have a valid result to send
          
          -- Wait until SLINK accepts the data (Successful Handshake)
          if (tx_ready_i = '1') then
            
            -- Reset accumulator and k_idx for the next dot product
            acc   <= (others => '0');
            k_idx <= 0;
            
            -- Update matrix pointers (Row/Col traversal)
            if (j_idx = 9) then
              j_idx <= 0;
              if (i_idx = 9) then
                -- Entire Matrix C is computed and sent!
                i_idx <= 0;
                state <= S_LOAD_A; -- Reset and wait for new matrices
              else
                i_idx <= i_idx + 1;
                state <= S_FETCH;
              end if;
            else
              j_idx <= j_idx + 1;
              state <= S_FETCH;
            end if;

          end if;

      end case;
    end if;
  end process fsm_process;

end rtl;