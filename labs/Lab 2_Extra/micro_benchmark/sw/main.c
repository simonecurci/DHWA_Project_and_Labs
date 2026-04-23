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
    // Basic NEORV32 setup
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);

    neorv32_uart0_printf("\n--- MAC Accelerator Microbenchmarking ---\n");

    // Check if the CFS module is available in the hardware
    if (neorv32_cfs_available() == 0) {
        neorv32_uart0_printf("ERROR: CFS module not implemented!\n");
        return 1;
    }

    volatile uint32_t *cfs = (volatile uint32_t *) NEORV32_CFS_BASE;

    uint32_t mat_A[N][N];
    uint32_t mat_B[N][N];
    uint32_t hw_res[N][N];
    uint32_t sw_res[N][N];

    // Timing variables for hardware microbenchmarking
    uint32_t t0, t1, t2, t3;
    uint32_t time_tx_in, time_compute, time_tx_out, time_total_hw;
    
    // Timing variables for software baseline
    uint32_t sw_start, sw_end, sw_cycles;

    // ========================================================================
    // 1. Data Generation
    // ========================================================================
    neorv32_uart0_printf("Generating test data...\n");
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    neorv32_uart0_printf("Starting Hardware Microbenchmarking...\n");

    // ========================================================================
    // PHASE 1: Data Transfer IN (CPU -> CFS)
    // ========================================================================
    t0 = get_cycles(); 
    
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            cfs[(i * 10) + j]       = mat_A[i][j];
            cfs[100 + (i * 10) + j] = mat_B[i][j];
        }
    }
    
    t1 = get_cycles(); 
    time_tx_in = t1 - t0;

    // ========================================================================
    // PHASE 2: Pure Hardware Computation and Polling
    // ========================================================================
    cfs[300] = 1; // Trigger FSM
    while ((cfs[300] & 0x01) == 0); // Polling loop
    
    t2 = get_cycles();
    time_compute = t2 - t1;

    // ========================================================================
    // PHASE 3: Data Transfer OUT (CFS -> CPU)
    // ========================================================================
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            hw_res[i][j] = cfs[200 + (i * 10) + j]; 
        }
    }
    
    t3 = get_cycles();
    time_tx_out = t3 - t2;

    // Calculate total hardware cost
    time_total_hw = time_tx_in + time_compute + time_tx_out;

    // ========================================================================
    // SOFTWARE MEASUREMENT (For baseline comparison)
    // ========================================================================
    neorv32_uart0_printf("Starting Software baseline computation...\n");
    sw_start = get_cycles(); 
    
    sw_matrix_mult(mat_A, mat_B, sw_res);
    
    sw_end = get_cycles();   
    sw_cycles = sw_end - sw_start;

    // ========================================================================
    // VERIFICATION
    // ========================================================================
    int errors = 0;
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (hw_res[i][j] != sw_res[i][j]) {
                errors++;
            }
        }
    }

    if (errors == 0) {
        neorv32_uart0_printf("\nSUCCESS! Hardware results match software.\n");
    } else {
        neorv32_uart0_printf("\nFAILED. %d errors found!\n", errors);
    }

    // ========================================================================
    // PRINT REPORT
    // ========================================================================
    neorv32_uart0_printf("\n--- MICROBENCHMARK REPORT ---\n");
    neorv32_uart0_printf("1. HW Transfer IN (200 words)  : %u cycles\n", time_tx_in);
    neorv32_uart0_printf("2. Pure HW Computation         : %u cycles\n", time_compute);
    neorv32_uart0_printf("3. HW Transfer OUT (100 words) : %u cycles\n", time_tx_out);
    neorv32_uart0_printf("--------------------------------------\n");
    neorv32_uart0_printf("TOTAL HW Cost (IN + COMP + OUT): %u cycles\n", time_total_hw);
    neorv32_uart0_printf("TOTAL SW Cost (Baseline)       : %u cycles\n", sw_cycles);
    neorv32_uart0_printf("--------------------------------------\n");

    // Calculate the net speedup multiplier
    if (time_total_hw > 0) {
        uint32_t speedup = sw_cycles / time_total_hw;
        neorv32_uart0_printf("Net Speedup (including data transfers): ~%ux faster\n\n", speedup);
    }

    return 0;
}