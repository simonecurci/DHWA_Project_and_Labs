#include <neorv32.h>

#define N 10 // Matrix dimension (10x10)

// Helper: Get current CPU clock cycles
inline uint32_t get_cycles(void) {
    uint32_t cycles;
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycles));
    return cycles;
}

// Helper: Pure Software Matrix Multiplication (for verification)
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

// Dummy task to simulate useful work while the hardware computes
void dummy_cpu_task() {
    volatile uint32_t dummy_sum = 0;
    for(int i = 0; i < 150; i++) {
        dummy_sum += (i * 7) ^ 0xAA;
    }
}

int main() {
    // Initial SoC setup
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);
    neorv32_uart0_printf("\n--- SLINK Accelerator: STANDARD API VERSION ---\n");

    // Check if SLINK was synthesized in the FPGA
    if (neorv32_slink_available() == 0) return 1;
    
    // Setup SLINK (0 = disable interrupts, use polling)
    neorv32_slink_setup(0); 

    uint32_t mat_A[N][N], mat_B[N][N], hw_res[N][N], sw_res[N][N];
    uint32_t t_start, t_end, t_burst, t_retrieve;

    // Initialize test data
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    uint32_t *ptr_A = &mat_A[0][0];
    uint32_t *ptr_B = &mat_B[0][0];
    uint32_t *res_ptr = &hw_res[0][0];

    // --- PHASE A: Data Transmission (Write Burst) ---
    t_start = get_cycles();
    
    // Send Matrix A
    for (int i = 0; i < 100; i++) {
        neorv32_slink_put(ptr_A[i]);             // Library call
    }
    // Send Matrix B
    for (int i = 0; i < 100; i++) {
        neorv32_slink_put(ptr_B[i]);             // Library call
    }
    
    t_end = get_cycles();
    t_burst = t_end - t_start;

    // --- PHASE B: Latency Hiding (Parallel CPU Work) ---
    dummy_cpu_task(); 

    // --- PHASE C & D: Data Retrieval (Read Burst) ---
    t_start = get_cycles();
    for (int i = 0; i < 100; i++) {     
        res_ptr[i] = neorv32_slink_get();         // Library call
    }
    t_end = get_cycles();
    t_retrieve = t_end - t_start;

    // --- Verification ---
    sw_matrix_mult(mat_A, mat_B, sw_res);
    int errors = 0;
    for (int i = 0; i < N * N; i++) {
        if (((uint32_t*)hw_res)[i] != ((uint32_t*)sw_res)[i]) errors++;
    }

    neorv32_uart0_printf("T_burst    : %u cycles\n", t_burst);
    neorv32_uart0_printf("T_retrieve : %u cycles\n", t_retrieve);
    if (errors == 0) neorv32_uart0_printf("SUCCESS!\n");

    return 0;
}