# Microbenchmarking Report: MAC Accelerator Bottleneck Analysis

Following the successful validation of the Custom Functions Subsystem (CFS) MAC Accelerator, a detailed microbenchmarking phase was conducted. The objective of this test is to break down the total hardware execution time into its fundamental phases (Data Input, Computation, Data Output) to identify the true system bottlenecks.

**Test Context:** \* **Matrix Size:** 10x10 (100 elements per matrix).

  * **CPU Configuration:** The `M` extension (Hardware Multiplier) was **ACTIVE** during this test, providing a highly optimized software baseline (`rv32imc`).

## 1\. Microbenchmarking Strategy (C Source Code)

To isolate the latencies, the standard RISC-V `cycle` CSR (Control and Status Register) was sampled at four distinct points during the hardware execution:

1.  Before sending `mat_A` and `mat_B` to the CFS.
2.  After data transmission, right before triggering the FSM.
3.  Immediately after the FSM polling loop completes.
4.  After reading `mat_C` back from the CFS into the CPU's memory.

```c
#include <neorv32.h>

#define N 10

// ========================================================================
// Function to read the hardware cycle counter (Standard RISC-V)
// ========================================================================
inline uint32_t get_cycles(void) {
    uint32_t cycles;
    // Reads the 'cycle' hardware register and stores it in the 'cycles' variable
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycles));
    return cycles;
}

// ========================================================================
// Pure Software Matrix Multiplication
// ========================================================================
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

    neorv32_uart0_printf("\n--- MAC Accelerator Microbenchmarking ---\n");

    if (neorv32_cfs_available() == 0) {
        neorv32_uart0_printf("ERROR: CFS module not implemented!\n");
        return 1;
    }

    volatile uint32_t *cfs = (volatile uint32_t *) NEORV32_CFS_BASE;

    uint32_t mat_A[N][N], mat_B[N][N], hw_res[N][N], sw_res[N][N];
    uint32_t t0, t1, t2, t3;
    uint32_t time_tx_in, time_compute, time_tx_out, time_total_hw;
    uint32_t sw_start, sw_end, sw_cycles;

    // 1. Data Generation
    neorv32_uart0_printf("Generating test data...\n");
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    neorv32_uart0_printf("Starting Hardware Microbenchmarking...\n");

    // PHASE 1: Data Transfer IN (CPU -> CFS)
    t0 = get_cycles(); 
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            cfs[(i * 10) + j]       = mat_A[i][j];
            cfs[100 + (i * 10) + j] = mat_B[i][j];
        }
    }
    t1 = get_cycles(); 
    time_tx_in = t1 - t0;

    // PHASE 2: Pure Hardware Computation and Polling
    cfs[300] = 1; 
    while ((cfs[300] & 0x01) == 0); 
    t2 = get_cycles();
    time_compute = t2 - t1;

    // PHASE 3: Data Transfer OUT (CFS -> CPU)
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            hw_res[i][j] = cfs[200 + (i * 10) + j]; 
        }
    }
    t3 = get_cycles();
    time_tx_out = t3 - t2;

    time_total_hw = time_tx_in + time_compute + time_tx_out;

    // SOFTWARE MEASUREMENT (Baseline)
    neorv32_uart0_printf("Starting Software baseline computation...\n");
    sw_start = get_cycles(); 
    sw_matrix_mult(mat_A, mat_B, sw_res);
    sw_end = get_cycles();   
    sw_cycles = sw_end - sw_start;

    // VERIFICATION
    int errors = 0;
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (hw_res[i][j] != sw_res[i][j]) errors++;
        }
    }

    if (errors == 0) neorv32_uart0_printf("\nSUCCESS! Hardware results match software.\n");
    else neorv32_uart0_printf("\nFAILED. %d errors found!\n", errors);

    // PRINT REPORT
    neorv32_uart0_printf("\n--- MICROBENCHMARK REPORT ---\n");
    neorv32_uart0_printf("1. HW Transfer IN (200 words)  : %u cycles\n", time_tx_in);
    neorv32_uart0_printf("2. Pure HW Computation         : %u cycles\n", time_compute);
    neorv32_uart0_printf("3. HW Transfer OUT (100 words) : %u cycles\n", time_tx_out);
    neorv32_uart0_printf("--------------------------------------\n");
    neorv32_uart0_printf("TOTAL HW Cost (IN + COMP + OUT): %u cycles\n", time_total_hw);
    neorv32_uart0_printf("TOTAL SW Cost (Baseline)       : %u cycles\n", sw_cycles);
    neorv32_uart0_printf("--------------------------------------\n");
    
    if (time_total_hw > 0) {
        uint32_t speedup = sw_cycles / time_total_hw;
        neorv32_uart0_printf("Net Speedup (including data transfers): ~%ux faster\n\n", speedup);
    }
    return 0;
}
```

## 2\. Benchmark Results

| Execution Phase | Clock Cycles | % of Total HW Time |
| :--- | :--- | :--- |
| **Phase 1: Transfer IN** (Write 200 words to CFS) | 5,099 | 49.3% |
| **Phase 2: Pure Computation** (FSM MAC processing) | 2,149 | 20.8% |
| **Phase 3: Transfer OUT** (Read 100 words from CFS) | 3,100 | 30.0% |
| **Total Hardware Cost** | **10,348** | **100%** |
| **Total Software Cost** (Baseline with M-Extension) | **43,388** | N/A |
| **Net Speedup** | **\~4x** | N/A |

-----

## 3\. Bottleneck Analysis

The data gathered from this microbenchmark provides crucial insights into the system's architecture, revealing that the accelerator is heavily **I/O Bound** rather than Compute Bound.

### 1\. The I/O Dominance (The Data Transfer Bottleneck)

The combined cost of moving data in and out of the CFS accelerator (5,099 + 3,100 = **8,199 cycles**) accounts for approximately **79% of the total hardware execution time**. The CPU spends the vast majority of its time fetching data from main memory, pushing it across the system bus word-by-word via `store` instructions, and subsequently reading the results back via `load` instructions.

### 2\. High Computational Efficiency

The pure hardware computation only requires **2,149 cycles**.
A 10x10 matrix multiplication requires exactly 1,000 Multiply-Accumulate operations. This means the custom FSM is achieving an impressive throughput of roughly **\~2.1 cycles per MAC operation**, including state transitions and loop management. The silicon logic is highly optimized.

### 3\. Conclusion & Future Work

While achieving a **4x net speedup** against a CPU already equipped with a hardware multiplier (`M` extension) is a success, the microbenchmark proves that the MAC logic is currently starved for data.

To further optimize this accelerator in a future iteration, the CPU-driven transfer loop must be eliminated. Implementing a **Direct Memory Access (DMA)** controller would allow the CFS to pull the matrices directly from main memory in burst modes, bypassing the CPU entirely and potentially reducing the I/O overhead from 8,000 cycles down to a few hundred, thereby unleashing the true potential of the 2,100-cycle computation core.