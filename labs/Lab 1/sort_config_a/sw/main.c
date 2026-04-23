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