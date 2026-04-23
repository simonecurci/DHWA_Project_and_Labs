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

    neorv32_uart0_printf("\n--- MAC Accelerator Test with Benchmarking ---\n");

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

    // Benchmarking variables
    uint32_t hw_start, hw_end, hw_cycles;
    uint32_t sw_start, sw_end, sw_cycles;

    // 1. Data generation
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    // ========================================================================
    // HARDWARE MEASUREMENT (Includes Data Transfer)
    // ========================================================================
    hw_start = get_cycles(); // <--- HW TIMER START

    // A. Send data to CFS
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            cfs[(i * 10) + j]       = mat_A[i][j];
            cfs[100 + (i * 10) + j] = mat_B[i][j];
        }
    }

    // B. Trigger FSM and Wait
    cfs[300] = 1;
    while ((cfs[300] & 0x01) == 0); // Polling

    // C. Read results from CFS
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            hw_res[i][j] = cfs[200 + (i * 10) + j]; 
        }
    }

    hw_end = get_cycles(); // <--- HW TIMER STOP
    hw_cycles = hw_end - hw_start;


    // ========================================================================
    // SOFTWARE MEASUREMENT
    // ========================================================================
    sw_start = get_cycles(); // <--- SW TIMER START
    
    sw_matrix_mult(mat_A, mat_B, sw_res);
    
    sw_end = get_cycles();   // <--- SW TIMER STOP
    sw_cycles = sw_end - sw_start;


    // ========================================================================
    // VERIFICATION AND PRINTING RESULTS
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
        neorv32_uart0_printf("\nSUCCESS! No errors found.\n");
    } else {
        neorv32_uart0_printf("\nFAILED. %d errors found!\n", errors);
    }

    // Print the Performance Report
    neorv32_uart0_printf("\n--- BENCHMARK RESULTS ---\n");
    neorv32_uart0_printf("Software CPU cycles : %u\n", sw_cycles);
    neorv32_uart0_printf("Hardware CPU cycles : %u\n", hw_cycles);
    
    // Calculate the speedup multiplier
    // We use integers to avoid printf/float issues on microcontrollers
    if (hw_cycles > 0) {
        uint32_t speedup = sw_cycles / hw_cycles;
        neorv32_uart0_printf("The hardware is approximately %ux faster!\n\n", speedup);
    }

    return 0;
}