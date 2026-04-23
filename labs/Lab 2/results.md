# Custom Functions Subsystem (CFS) Benchmark: Matrix MAC Accelerator

This document outlines the implementation and benchmarking of a custom hardware accelerator integrated into the NEORV32 **Custom Functions Subsystem (CFS)**.

The objective of this project is to offload a fixed-size $10 \times 10$ Matrix Multiplication workload from the main CPU to a dedicated hardware Finite State Machine (FSM) utilizing a custom Multiply-Accumulate (MAC) unit, and to validate its performance against pure software execution.

## 1\. Hardware Architecture (VHDL)

The hardware accelerator is implemented as a memory-mapped peripheral within the CFS. It contains dedicated RAM blocks for the operands and the result, alongside a control FSM.

### Memory Map

The CFS exposes a 32-bit memory interface to the CPU. The address space is carefully partitioned into word addresses to store the $10 \times 10$ matrices (100 elements each):

  * **`mat_A` (0 - 99):** CPU Write/Read (Input Matrix A)
  * **`mat_B` (100 - 199):** CPU Write/Read (Input Matrix B)
  * **`mat_C` (200 - 299):** CPU Read-Only (Hardware Result Matrix C)
  * **`Control Register` (300):** CPU Write (Bit 0 = `Start`), CPU Read (Bit 0 = `Done`)

### The FSM and MAC Logic

Once the CPU triggers the start condition, the independent FSM takes over.
The FSM operates through 5 states: `S_IDLE`, `S_FETCH`, `S_MAC`, `S_STORE`, and `S_DONE`.

  * **`S_FETCH` & `S_MAC`:** The FSM pipelines the retrieval of operands from the internal RAMs and feeds them into the MAC unit. The 64-bit multiplication result is truncated to 32 bits and accumulated.
  * **`S_STORE`:** Upon completing a row-column dot product, the accumulator is written to `mat_C`, and the indices are updated.
  * **`S_DONE`:** Signals completion to the CPU, allowing polling loops to exit.
  
```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    clk_i     : in  std_ulogic;
    rstn_i    : in  std_ulogic;
    bus_req_i : in  bus_req_t;
    bus_rsp_o : out bus_rsp_t;
    irq_o     : out std_ulogic;
    cfs_in_i  : in  std_ulogic_vector(255 downto 0);
    cfs_out_o : out std_ulogic_vector(255 downto 0)
  );
end neorv32_cfs;

architecture neorv32_cfs_rtl of neorv32_cfs is
  type ram_t is array (0 to 99) of std_ulogic_vector(31 downto 0);
  signal mat_a, mat_b, mat_c : ram_t;
  signal word_addr : integer range 0 to 16383;

  signal ctrl_start : std_ulogic;
  signal ctrl_done  : std_ulogic;

  type state_t is (S_IDLE, S_FETCH, S_MAC, S_STORE, S_DONE);
  signal state : state_t;

  signal i_idx, j_idx, k_idx : integer range 0 to 10;
  signal acc    : signed(31 downto 0);
  signal a_data : std_ulogic_vector(31 downto 0);
  signal b_data : std_ulogic_vector(31 downto 0);

begin
  cfs_out_o <= (others => '0');
  irq_o     <= '0'; 
  word_addr <= to_integer(unsigned(bus_req_i.addr(15 downto 2)));

  bus_access: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      bus_rsp_o  <= rsp_terminate_c;
      ctrl_start <= '0';
    elsif rising_edge(clk_i) then
      bus_rsp_o.ack  <= bus_req_i.stb;
      bus_rsp_o.err  <= '0';
      bus_rsp_o.data <= (others => '0');

      if state /= S_IDLE then
        ctrl_start <= '0';
      end if;

      if (bus_req_i.stb = '1') then
        if (bus_req_i.rw = '1') then
          if word_addr < 100 then mat_a(word_addr) <= bus_req_i.data;
          elsif word_addr >= 100 and word_addr < 200 then mat_b(word_addr - 100) <= bus_req_i.data;
          elsif word_addr = 300 then ctrl_start <= bus_req_i.data(0);
          end if;
        else
          if word_addr < 100 then bus_rsp_o.data <= mat_a(word_addr);
          elsif word_addr >= 100 and word_addr < 200 then bus_rsp_o.data <= mat_b(word_addr - 100);
          elsif word_addr >= 200 and word_addr < 300 then bus_rsp_o.data <= mat_c(word_addr - 200);
          elsif word_addr = 300 then bus_rsp_o.data(0) <= ctrl_done;
          end if;
        end if;
      end if;
    end if;
  end process bus_access;

  a_data <= mat_a(i_idx * 10 + k_idx);
  b_data <= mat_b(k_idx * 10 + j_idx);

  mac_fsm: process(clk_i, rstn_i)
    variable mult_res : signed(63 downto 0);
  begin
    if (rstn_i = '0') then
      state      <= S_IDLE;
      ctrl_done  <= '0';
      i_idx      <= 0; j_idx <= 0; k_idx <= 0;
      acc        <= (others => '0');
    elsif rising_edge(clk_i) then
      case state is
        when S_IDLE =>
          if (ctrl_start = '1') then
            i_idx <= 0; j_idx <= 0; k_idx <= 0;
            acc <= (others => '0');
            ctrl_done <= '0';
            state <= S_FETCH;
          end if;
        when S_FETCH =>
          state <= S_MAC;
        when S_MAC =>
          mult_res := signed(a_data) * signed(b_data);
          acc      <= acc + mult_res(31 downto 0);
          if (k_idx = 9) then state <= S_STORE;
          else k_idx <= k_idx + 1; state <= S_FETCH;
          end if;
        when S_STORE =>
          mat_c(i_idx * 10 + j_idx) <= std_ulogic_vector(acc);
          acc   <= (others => '0');
          k_idx <= 0;
          if (j_idx = 9) then
            j_idx <= 0;
            if (i_idx = 9) then state <= S_DONE;
            else i_idx <= i_idx + 1; state <= S_FETCH;
            end if;
          else
            j_idx <= j_idx + 1; state <= S_FETCH;
          end if;
        when S_DONE =>
          ctrl_done <= '1';
          state     <= S_IDLE;
      end case;
    end if;
  end process mac_fsm;
end neorv32_cfs_rtl;
```
## 2\. Software Design & Validation (C Code)

The software component acts as the testbench. It performs a cycle-accurate measurement of both the hardware offloading pipeline (including memory transfer overhead) and the pure software implementation. It subsequently compares the output matrices to guarantee hardware correctness.

```c
#include <neorv32.h>

#define N 10

inline uint32_t get_cycles(void) {
    uint32_t cycles;
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycles));
    return cycles;
}

void sw_matrix_mult(uint32_t A[N][N], uint32_t B[N][N], uint32_t C[N][N]) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            C[i][j] = 0;
            for (int k = 0; k < N; k++) {
                C[i][j] += A[i][k] * B[k][j];
            }
        }
    }
}

int main() {
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);

    neorv32_uart0_printf("\n--- MAC Accelerator Test with Benchmarking ---\n");

    if (neorv32_cfs_available() == 0) {
        neorv32_uart0_printf("ERROR: CFS module not implemented!\n");
        return 1;
    }

    volatile uint32_t *cfs = (volatile uint32_t *) NEORV32_CFS_BASE;

    uint32_t mat_A[N][N], mat_B[N][N], hw_res[N][N], sw_res[N][N];
    uint32_t hw_start, hw_end, hw_cycles;
    uint32_t sw_start, sw_end, sw_cycles;

    // 1. Data generation
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    // 2. HARDWARE MEASUREMENT
    hw_start = get_cycles(); 
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            cfs[(i * 10) + j]       = mat_A[i][j];
            cfs[100 + (i * 10) + j] = mat_B[i][j];
        }
    }
    cfs[300] = 1; // Trigger
    while ((cfs[300] & 0x01) == 0); // Polling
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            hw_res[i][j] = cfs[200 + (i * 10) + j]; 
        }
    }
    hw_end = get_cycles(); 
    hw_cycles = hw_end - hw_start;

    // 3. SOFTWARE MEASUREMENT
    sw_start = get_cycles(); 
    sw_matrix_mult(mat_A, mat_B, sw_res);
    sw_end = get_cycles();   
    sw_cycles = sw_end - sw_start;

    // 4. VERIFICATION
    int errors = 0;
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (hw_res[i][j] != sw_res[i][j]) errors++;
        }
    }

    if (errors == 0) neorv32_uart0_printf("\nSUCCESS! No errors found.\n");
    else neorv32_uart0_printf("\nFAILED. %d errors found!\n", errors);

    neorv32_uart0_printf("\n--- BENCHMARK RESULTS ---\n");
    neorv32_uart0_printf("Software CPU cycles : %u\n", sw_cycles);
    neorv32_uart0_printf("Hardware CPU cycles : %u\n", hw_cycles);
    
    if (hw_cycles > 0) {
        uint32_t speedup = sw_cycles / hw_cycles;
        neorv32_uart0_printf("The hardware is approximately %ux faster!\n\n", speedup);
    }
    return 0;
}
```
## 3\. Benchmark Results & Performance Analysis

The simulation was executed under two different primary CPU configurations to evaluate the relative effectiveness of the accelerator.

### Case A: Base RISC-V CPU (M-Extension Inactive)

In this scenario, the main CPU relies entirely on software emulation to perform standard mathematical multiplication.

| Execution Method | Clock Cycles | Notes |
| :--- | :--- | :--- |
| **Software execution** | 157,911 | Massive bottleneck due to software emulated multiplication loops. |
| **CFS Accelerator execution** | 10,786 | Time includes writing operands, computation, polling, and reading results. |
| **Speedup** | **\~14x** | Massive performance gain by offloading to the CFS. |

### Case B: Upgraded RISC-V CPU (M-Extension Active)

In this scenario, the main CPU possesses the `M` (Hardware Multiplier) ISA extension, accelerating the baseline software performance.

| Execution Method | Clock Cycles | Notes |
| :--- | :--- | :--- |
| **Software execution** | 43,378 | Software is much faster natively thanks to the `M` extension. |
| **CFS Accelerator execution** | 10,315 | Hardware FSM performance remains static. |
| **Speedup** | **\~4x** | The accelerator is still highly beneficial, though the relative gap narrows. |

-----

## Engineering Insights

1.  **Hardware Time is Dominated by Data Transfer (I/O Overhead):** The CFS FSM computes the $10 \times 10$ matrix multiplication in roughly 2,000 cycles (10 rows $\times$ 10 cols $\times$ 10 dot-products $\times$ 2 states). However, the measured hardware time is $\sim$10,000 cycles. This highlights a classic architectural paradigm: **the bottleneck of hardware acceleration is often not the computation itself, but the time it takes the CPU to push and pull data across the bus**.
2.  **Stable Hardware Performance:**
    The CFS execution time ($\sim$10,500 cycles) remains virtually identical regardless of whether the primary CPU has the `M` extension active or not. The slight variance (10,315 vs. 10,786) is simply due to how the compiler schedules the C loop instructions that move the data back and forth to the memory-mapped I/O addresses.
3.  **Relative Speedup:**
    When the CPU is weak (No M-Ext), the CFS provides a massive **14x** speedup. When the CPU is strong (M-Ext active), the software computation completes almost 4 times faster than before, reducing the relative speedup to **4x**. Nonetheless, the CFS accelerator consistently outperforms the software implementation by an order of magnitude.