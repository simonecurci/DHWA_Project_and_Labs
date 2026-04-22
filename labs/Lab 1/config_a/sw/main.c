// ================================================================================ //
// The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              //
// Copyright (c) NEORV32 contributors.                                              //
// Copyright (c) 2020 - 2025 Stephan Nolting. All rights reserved.                  //
// Licensed under the BSD-3-Clause license, see LICENSE for details.                //
// SPDX-License-Identifier: BSD-3-Clause                                            //
// ================================================================================ //

#include <neorv32.h>

#define MATRIX_SIZE 16
#define ITERATIONS 5

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