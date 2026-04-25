-- ================================================================================ --
-- NEORV32 SoC - Custom Functions Subsystem (CFS)                                   --
-- Matrix Multiplication Accelerator with Input FIFO & Output Streaming             --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    -- global control --
    clk_i     : in  std_ulogic; -- global clock line
    rstn_i    : in  std_ulogic; -- global reset line, low-active, async
    -- CPU access --
    bus_req_i : in  bus_req_t;  -- bus request
    bus_rsp_o : out bus_rsp_t;  -- bus response
    -- CPU interrupt --
    irq_o     : out std_ulogic; -- interrupt request
    -- external IO --
    cfs_in_i  : in  std_ulogic_vector(255 downto 0); -- custom inputs conduit
    cfs_out_o : out std_ulogic_vector(255 downto 0)  -- custom outputs conduit
  );
end neorv32_cfs;

architecture neorv32_cfs_rtl of neorv32_cfs is

  -- ========================================================================
  -- 1. Internal RAMs for Matrices (10x10 = 100 elements each)
  -- ========================================================================
  type ram_t is array (0 to 99) of std_ulogic_vector(31 downto 0);
  signal mat_a, mat_b, mat_c : ram_t;

  -- ========================================================================
  -- 2. Input FIFO Definitions (256 words deep)
  -- ========================================================================
  type fifo_mem_t is array (0 to 255) of std_ulogic_vector(31 downto 0);
  signal fifo_mem : fifo_mem_t;
  
  signal fifo_wr_ptr, fifo_rd_ptr : unsigned(7 downto 0);
  signal fifo_count               : unsigned(8 downto 0);
  signal fifo_dout                : std_ulogic_vector(31 downto 0);
  signal fifo_full                : std_ulogic;
  signal fifo_empty               : std_ulogic;

  -- ========================================================================
  -- 3. Output Streaming Pointer (Pseudo-FIFO for output)
  -- ========================================================================
  signal out_ptr : unsigned(6 downto 0); -- Counts 0 to 99

  -- ========================================================================
  -- 4. Control, Status and FSM Signals
  -- ========================================================================
  signal word_addr  : integer range 0 to 16383;
  signal ctrl_start : std_ulogic;
  signal ctrl_reset : std_ulogic;
  signal ctrl_done  : std_ulogic;

  -- FSM States: Added S_LOAD to move data from FIFO to RAMs
  type state_t is (S_IDLE, S_LOAD, S_FETCH, S_MAC, S_STORE, S_DONE);
  signal state : state_t;

  -- Computational variables
  signal load_cnt            : unsigned(7 downto 0);
  signal i_idx, j_idx, k_idx : integer range 0 to 10;
  signal acc                 : signed(31 downto 0);
  
  signal a_data, b_data      : std_ulogic_vector(31 downto 0);

begin

  -- Unused IOs for this specific accelerator
  cfs_out_o <= (others => '0');
  irq_o     <= '0'; 

  -- Convert byte address to word address (drop 2 LSBs)
  word_addr <= to_integer(unsigned(bus_req_i.addr(15 downto 2)));

  -- ========================================================================
  -- COMBINATIONAL LOGIC ASSIGNMENTS
  -- ========================================================================
  -- FIFO flags
  fifo_empty <= '1' when fifo_count = 0 else '0';
  fifo_full  <= '1' when fifo_count = 256 else '0';
  
  -- First-Word Fall-Through (FWFT) FIFO read
  fifo_dout  <= fifo_mem(to_integer(fifo_rd_ptr));

  -- Combinational read from RAMs for MAC unit
  a_data <= mat_a(i_idx * 10 + k_idx);
  b_data <= mat_b(k_idx * 10 + j_idx);

  -- ========================================================================
  -- PROCESS 1: CPU Bus Interface, FIFO & Output Streaming Logic
  -- ========================================================================
  bus_access: process(rstn_i, clk_i)
    variable write_fifo : boolean;
    variable read_fifo  : boolean;
  begin
    if (rstn_i = '0') then
      bus_rsp_o   <= rsp_terminate_c;
      ctrl_start  <= '0';
      ctrl_reset  <= '0';
      fifo_wr_ptr <= (others => '0');
      fifo_rd_ptr <= (others => '0');
      fifo_count  <= (others => '0');
      out_ptr     <= (others => '0');
    elsif rising_edge(clk_i) then
      
      -- Default bus response: Ack the request
      bus_rsp_o.ack  <= bus_req_i.stb;
      bus_rsp_o.err  <= '0';
      bus_rsp_o.data <= (others => '0');

      -- Auto-clearing control signals (pulse generation)
      ctrl_start <= '0';
      ctrl_reset <= '0';

      -- Boolean flags to cleanly manage FIFO pointers
      -- CPU writes to Addr 0
      write_fifo := (bus_req_i.stb = '1' and bus_req_i.rw = '1' and word_addr = 0 and fifo_full = '0');
      -- FSM reads during S_LOAD state
      read_fifo  := (state = S_LOAD and fifo_empty = '0');

      -- Memory Mapped I/O Operations
      if (bus_req_i.stb = '1') then
        
        -- WRITE ACCESS
        if (bus_req_i.rw = '1') then
          -- ADDR 1: Control Register (Bit 0: Start, Bit 1: Reset)
          if word_addr = 1 then
            ctrl_start <= bus_req_i.data(0);
            ctrl_reset <= bus_req_i.data(1);
          end if;
          
        -- READ ACCESS
        else
          -- ADDR 1: Status Register (Bit 0: Done, Bit 1: FIFO Full, Bit 2: FIFO Empty)
          if word_addr = 1 then
            bus_rsp_o.data(0) <= ctrl_done;
            bus_rsp_o.data(1) <= fifo_full;
            bus_rsp_o.data(2) <= fifo_empty;
            
          -- ADDR 2: Output Streaming Pseudo-FIFO (Reads Matrix C and auto-increments)
          elsif word_addr = 2 then
            bus_rsp_o.data <= mat_c(to_integer(out_ptr));
            
          end if;
        end if;
      end if;

      -- Pointer Management and Resets
      if (ctrl_reset = '1') then
        fifo_wr_ptr <= (others => '0');
        fifo_rd_ptr <= (others => '0');
        fifo_count  <= (others => '0');
        out_ptr     <= (others => '0');
      else
        -- Reset output pointer when a new computation starts
        if (ctrl_start = '1') then
           out_ptr <= (others => '0');
        end if;

        -- Auto-increment Output Pointer on CPU read from ADDR 2
        if (bus_req_i.stb = '1' and bus_req_i.rw = '0' and word_addr = 2) then
          if (out_ptr < 99) then
             out_ptr <= out_ptr + 1;
          end if;
        end if;

        -- Input FIFO Write Logic
        if write_fifo then
          fifo_mem(to_integer(fifo_wr_ptr)) <= bus_req_i.data;
          fifo_wr_ptr <= fifo_wr_ptr + 1;
        end if;

        -- Input FIFO Read Logic
        if read_fifo then
          fifo_rd_ptr <= fifo_rd_ptr + 1;
        end if;

        -- Input FIFO Counter Tracking
        if write_fifo and not read_fifo then
          fifo_count <= fifo_count + 1;
        elsif read_fifo and not write_fifo then
          fifo_count <= fifo_count - 1;
        end if;
      end if;

    end if;
  end process bus_access;

  -- ========================================================================
  -- PROCESS 2: Hardware MAC Finite State Machine
  -- ========================================================================
  mac_fsm: process(clk_i, rstn_i)
    variable mult_res : signed(63 downto 0);
  begin
    if (rstn_i = '0') then
      state      <= S_IDLE;
      ctrl_done  <= '0';
      load_cnt   <= (others => '0');
      i_idx      <= 0;
      j_idx      <= 0;
      k_idx      <= 0;
      acc        <= (others => '0');
    elsif rising_edge(clk_i) then
      
      -- Priority Hardware Reset
      if (ctrl_reset = '1') then
        state      <= S_IDLE;
        ctrl_done  <= '0';
      else
        case state is
        
          -- Wait for the CPU to issue the Start command
          when S_IDLE =>
            if (ctrl_start = '1') then
              load_cnt  <= (others => '0');
              ctrl_done <= '0';
              i_idx     <= 0;
              j_idx     <= 0;
              k_idx     <= 0;
              acc       <= (others => '0');
              state     <= S_LOAD; -- Proceed to drain FIFO first
            end if;

          -- DRAIN FIFO: Move 200 words from FIFO to Internal RAMs
          when S_LOAD =>
            if (fifo_empty = '0') then
              -- First 100 words go to Matrix A, next 100 to Matrix B
              if (load_cnt < 100) then
                mat_a(to_integer(load_cnt)) <= fifo_dout;
              else
                mat_b(to_integer(load_cnt) - 100) <= fifo_dout;
              end if;

              -- Transition to compute when all 200 items are loaded
              if (load_cnt = 199) then
                state <= S_FETCH; 
              else
                load_cnt <= load_cnt + 1;
              end if;
            end if;

          -- 1-Cycle Delay to allow RAM data to propagate combinatorially
          when S_FETCH =>
            state <= S_MAC;

          -- Multiply and Accumulate
          when S_MAC =>
            -- 64-bit safe multiplication, truncating to 32-bit accumulator
            mult_res := signed(a_data) * signed(b_data);
            acc      <= acc + mult_res(31 downto 0);
            
            -- Check if dot product for the current matrix cell is finished
            if (k_idx = 9) then
              state <= S_STORE;
            else
              k_idx <= k_idx + 1;
              state <= S_FETCH;
            end if;

          -- Store result into Matrix C and manage matrix indices (Row/Col)
          when S_STORE =>
            mat_c(i_idx * 10 + j_idx) <= std_ulogic_vector(acc);
            acc   <= (others => '0');
            k_idx <= 0;
            
            -- Inner loop (Columns -> j_idx), Outer loop (Rows -> i_idx)
            if (j_idx = 9) then
              j_idx <= 0;
              if (i_idx = 9) then
                state <= S_DONE; -- All 100 elements calculated
              else
                i_idx <= i_idx + 1;
                state <= S_FETCH;
              end if;
            else
              j_idx <= j_idx + 1;
              state <= S_FETCH;
            end if;

          -- Signal completion to CPU via Status Register
          when S_DONE =>
            ctrl_done <= '1';
            state     <= S_IDLE;

        end case;
      end if;
    end if;
  end process mac_fsm;

end neorv32_cfs_rtl;