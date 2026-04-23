# Benchmarking Report: NEORV32 Hardware Optimization

This document outlines the testing and benchmarking sessions performed on the **NEORV32** RISC-V soft-core processor. The goal of this project is to measure the impact of different architectural optimizations (ISA extensions and Cache memories) on the processor's execution times.

**Methodological Note:** All results documented in this report were obtained via **RTL Simulation** (using GHDL in a containerized Docker environment), measuring the physical clock cycles calculated by the simulator.



## Hardware Configurations

The processor was synthesized and tested in three incremental configurations to isolate the impact of each additional component:

* **Config A (Minimal Baseline):** Base `rv32i` architecture. No hardware accelerators, no cache. All complex mathematical operations (such as multiplication) are resolved via software using libraries and addition loops.
* **Config B (I-Cache):** `rv32i` architecture with the addition of the **Instruction Cache** enabled in the VHDL configuration. 
    * *Technical Note:* Since the test source code is very compact and loaded entirely into the ultra-fast internal memory (IMEM), the cache controller performs a hardware bypass. The IMEM already responds in 1 single clock cycle, making the cache superfluous for this specific use case.
* **Config C (Hardware Math):** `rv32imc` architecture. The **M** extension (Hardware Multiplier/Divider) is enabled in VHDL, and the `-march=rv32imc` flag is passed to the C compiler. Multiplications are no longer emulated via software but are resolved natively in very few cycles by a dedicated hardware circuit.

---

## 1. Benchmark: Matrix Math

This test performs the multiplication of two $8 \times 8$ matrices. It is a "Math-Intensive" algorithm, specifically designed to stress the CPU's arithmetic computing capabilities and evaluate the impact of the `M` ISA extension.

### Source Code (C)
```c
// ================================================================================ //
// The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              //
// Copyright (c) NEORV32 contributors.                                              //
// Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  //
// Licensed under the BSD-3-Clause license, see LICENSE for details.                //
// SPDX-License-Identifier: BSD-3-Clause                                            //
// ================================================================================ //

#include <neorv32.h>

#define MATRIX_SIZE 8
#define ITERATIONS 1

volatile uint32_t mat_a[MATRIX_SIZE][MATRIX_SIZE];
volatile uint32_t mat_b[MATRIX_SIZE][MATRIX_SIZE];
volatile uint32_t mat_c[MATRIX_SIZE][MATRIX_SIZE];

void init_matrix_data() {
    for (int i = 0; i < MATRIX_SIZE; i++) {
        for (int j = 0; j < MATRIX_SIZE; j++) {
            mat_a[i][j] = (i + j) % 100;
            mat_b[i][j] = (i * j) % 100;
            mat_c[i][j] = 0;
        }
    }
}

int main() {
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);
    
    neorv32_uart0_printf("\n--- NEORV32 Matrix Math Benchmark ---\n");
    init_matrix_data();
    
    uint32_t start_cycle, end_cycle, total_cycles;
    
    neorv32_uart0_printf("Running (%dx%d), %d Iterations...\n", MATRIX_SIZE, MATRIX_SIZE, ITERATIONS);
    
    start_cycle = neorv32_cpu_get_cycle();
    
    for(int iter = 0; iter < ITERATIONS; iter++) {
        for (int i = 0; i < MATRIX_SIZE; i++) {
            for (int j = 0; j < MATRIX_SIZE; j++) {
                uint32_t sum = 0;
                for (int k = 0; k < MATRIX_SIZE; k++) {
                    sum += mat_a[i][k] * mat_b[k][j]; 
                }
                mat_c[i][j] = sum;
            }
        }
    }
    
    end_cycle = neorv32_cpu_get_cycle();
    total_cycles = end_cycle - start_cycle;
    
    neorv32_uart0_printf("MatMul Total Cycles: %u\n", total_cycles);
    return 0;
}
```

### Simulation Results

| Configuration | Hardware Setup | Total Cycles | Performance Notes |
| :--- | :--- | :--- | :--- |
| **Config A** | Base (`rv32i`) | 62,565 | Slow. Multiplications resolved via software loops. |
| **Config B** | Base + I-Cache | 62,565 | No improvement. Direct execution from IMEM (1 cycle/instruction). |
| **Config C** | M Ext (`rv32imc`) | **23,165** | **63% optimization.** Hardware executes multiplication natively. |

---

## 2. Benchmark: Bubble Sort (Memory & Control Flow)

This test sorts an array of 64 elements (initialized in reverse order to maximize swaps). It is a "Memory-Intensive" and "Branch-Intensive" algorithm. It does not use any multiplication operations, but heavily stresses conditional branches and memory accesses (Load/Store).

### Source Code (C)
```c
// ================================================================================ //
// The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              //
// Copyright (c) NEORV32 contributors.                                              //
// Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  //
// Licensed under the BSD-3-Clause license, see LICENSE for details.                //
// SPDX-License-Identifier: BSD-3-Clause                                            //
// ================================================================================ //

#include <neorv32.h>

#define ARRAY_SIZE 64
#define ITERATIONS 1

volatile uint32_t sort_array[ARRAY_SIZE];

void init_sort_data() {
    // Reverse ordered array to force maximum swaps/memory movement
    for (int i = 0; i < ARRAY_SIZE; i++) {
        sort_array[i] = ARRAY_SIZE - i; 
    }
}

int main() {
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);
    
    neorv32_uart0_printf("\n--- NEORV32 Memory/Sort Benchmark ---\n");
    init_sort_data();
    
    uint32_t start_cycle, end_cycle, total_cycles;
    
    neorv32_uart0_printf("Running Bubble Sort (%d elements), %d Iterations...\n", ARRAY_SIZE, ITERATIONS);
    
    start_cycle = neorv32_cpu_get_cycle();
    
    for(int iter = 0; iter < ITERATIONS; iter++) {
        for (int i = 0; i < ARRAY_SIZE - 1; i++) {
            for (int j = 0; j < ARRAY_SIZE - i - 1; j++) {
                if (sort_array[j] > sort_array[j + 1]) {
                    uint32_t temp = sort_array[j];
                    sort_array[j] = sort_array[j + 1];
                    sort_array[j + 1] = temp;
                }
            }
        }
    }
    
    end_cycle = neorv32_cpu_get_cycle();
    total_cycles = end_cycle - start_cycle;
    
    neorv32_uart0_printf("Sort Total Cycles: %u\n", total_cycles);
    return 0;
}
```

### Simulation Results

| Configuration | Hardware Setup | Total Cycles | Performance Notes |
| :--- | :--- | :--- | :--- |
| **Config A** | Base (`rv32i`) | 125,615 | No arithmetic bottlenecks detected. |
| **Config B** | Base + I-Cache | 125,615 | Identical. Code runs in IMEM bypassing the I-Cache. |
| **Config C** | M Ext (`rv32imc`) | **125,603** | Negligible variance of 12 cycles. The multiplier is not used by the algorithm. |

---

## Final Data Analysis

The comparison between the two benchmarks clearly demonstrates a fundamental principle of computer architecture: **hardware accelerations are highly dominant and specific**.

1.  In matrix calculation, the addition of the hardware ISA-M extension (Config C) slashed processing cycles by almost two-thirds compared to software emulation.
2.  In Bubble Sort, the presence of the hardware multiplier module (Config C) provided no measurable advantage, as the algorithm is dominated by Load/Store operations (which do not benefit from the dedicated multiplication ALU).
3.  The inclusion of the I-Cache (Config B) did not alter the cycle count in either tested case, proving that for small-sized executables residing within the internal Instruction Memory (IMEM), the architecture already guarantees optimal, zero-latency instruction access.