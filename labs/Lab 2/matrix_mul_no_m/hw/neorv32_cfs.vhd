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
    bus_req_i : in  bus_req_t; -- bus request
    bus_rsp_o : out bus_rsp_t; -- bus response
    -- CPU interrupt --
    irq_o     : out std_ulogic; -- interrupt request
    -- external IO --
    cfs_in_i  : in  std_ulogic_vector(255 downto 0); -- custom inputs conduit
    cfs_out_o : out std_ulogic_vector(255 downto 0) -- custom outputs conduit
  );
end neorv32_cfs;

architecture neorv32_cfs_rtl of neorv32_cfs is

  -- ========================================================================
  -- Types and Signals for Matrices
  -- ========================================================================
  -- 100-element array for 10x10 matrices
  type ram_t is array (0 to 99) of std_ulogic_vector(31 downto 0);
  signal mat_a, mat_b, mat_c : ram_t;

  -- Bus addressing signal (word address)
  signal word_addr : integer range 0 to 16383;

  -- ========================================================================
  -- Control Signals and FSM
  -- ========================================================================
  signal ctrl_start : std_ulogic;
  signal ctrl_done  : std_ulogic;

  -- State machine definition
  type state_t is (S_IDLE, S_FETCH, S_MAC, S_STORE, S_DONE);
  signal state : state_t;

  -- Indices for matrix multiplication (i = row, j = col, k = dot product step)
  signal i_idx, j_idx, k_idx : integer range 0 to 10;
  
  -- Accumulator and data signals for the MAC logic
  signal acc    : signed(31 downto 0);
  signal a_data : std_ulogic_vector(31 downto 0);
  signal b_data : std_ulogic_vector(31 downto 0);

begin

  -- Unused IOs for this specific example
  cfs_out_o <= (others => '0');
  irq_o     <= '0'; 

  -- Convert 16-bit byte address to word address (drop the 2 LSBs)
  word_addr <= to_integer(unsigned(bus_req_i.addr(15 downto 2)));

  -- ========================================================================
  -- 1. CPU Bus Interface (Memory Read/Write)
  -- ========================================================================
  bus_access: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      bus_rsp_o  <= rsp_terminate_c;
      ctrl_start <= '0';
    elsif rising_edge(clk_i) then
      
      -- Default bus response: acknowledge the request and output zero
      bus_rsp_o.ack  <= bus_req_i.stb;
      bus_rsp_o.err  <= '0';
      bus_rsp_o.data <= (others => '0');

      -- Auto-clear the start signal once the FSM leaves the IDLE state
      if state /= S_IDLE then
        ctrl_start <= '0';
      end if;

      -- Check if there is a valid bus request
      if (bus_req_i.stb = '1') then
        
        -- WRITE ACCESS
        if (bus_req_i.rw = '1') then
          if word_addr < 100 then
            mat_a(word_addr) <= bus_req_i.data;
          elsif word_addr >= 100 and word_addr < 200 then
            mat_b(word_addr - 100) <= bus_req_i.data;
          -- Matrix C (200-299) is Read-Only for the CPU.
          -- Write to word_addr 300 triggers the hardware accelerator.
          elsif word_addr = 300 then
            ctrl_start <= bus_req_i.data(0);
          end if;

        -- READ ACCESS
        else
          if word_addr < 100 then
            bus_rsp_o.data <= mat_a(word_addr);
          elsif word_addr >= 100 and word_addr < 200 then
            bus_rsp_o.data <= mat_b(word_addr - 100);
          elsif word_addr >= 200 and word_addr < 300 then
            bus_rsp_o.data <= mat_c(word_addr - 200);
          -- Read from word_addr 300 returns the 'done' status.
          elsif word_addr = 300 then
            bus_rsp_o.data(0) <= ctrl_done;
          end if;
        end if;
      end if;
    end if;
  end process bus_access;

  -- Combinational read from RAMs for the hardware accelerator
  a_data <= mat_a(i_idx * 10 + k_idx);
  b_data <= mat_b(k_idx * 10 + j_idx);

  -- ========================================================================
  -- 2. Hardware MAC FSM (Matrix Multiplication)
  -- ========================================================================
  mac_fsm: process(clk_i, rstn_i)
    variable mult_res : signed(63 downto 0);
  begin
    if (rstn_i = '0') then
      state      <= S_IDLE;
      ctrl_done  <= '0';
      i_idx      <= 0;
      j_idx      <= 0;
      k_idx      <= 0;
      acc        <= (others => '0');
    elsif rising_edge(clk_i) then
      case state is
      
        -- Wait for the CPU to issue the Start command
        when S_IDLE =>
          if (ctrl_start = '1') then
            i_idx     <= 0;
            j_idx     <= 0;
            k_idx     <= 0;
            acc       <= (others => '0');
            ctrl_done <= '0';
            state     <= S_FETCH;
          end if;

        -- Allow one clock cycle for RAM data to propagate
        when S_FETCH =>
          state <= S_MAC;

        -- Multiply and Accumulate
        when S_MAC =>
          -- Perform 64-bit multiplication to prevent overflow, then truncate to 32-bit
          mult_res := signed(a_data) * signed(b_data);
          acc      <= acc + mult_res(31 downto 0);
          
          -- Check if the dot product for the current element is complete
          if (k_idx = 9) then
            state <= S_STORE;
          else
            k_idx <= k_idx + 1;
            state <= S_FETCH;
          end if;

        -- Save the accumulated result and manage row/col indices
        when S_STORE =>
          mat_c(i_idx * 10 + j_idx) <= std_ulogic_vector(acc);
          acc   <= (others => '0');
          k_idx <= 0;
          
          -- Nested loop logic (j -> columns, i -> rows)
          if (j_idx = 9) then
            j_idx <= 0;
            if (i_idx = 9) then
              state <= S_DONE;
            else
              i_idx <= i_idx + 1;
              state <= S_FETCH;
            end if;
          else
            j_idx <= j_idx + 1;
            state <= S_FETCH;
          end if;

        -- Signal completion to the CPU
        when S_DONE =>
          ctrl_done <= '1';
          state     <= S_IDLE;

      end case;
    end if;
  end process mac_fsm;

end neorv32_cfs_rtl;