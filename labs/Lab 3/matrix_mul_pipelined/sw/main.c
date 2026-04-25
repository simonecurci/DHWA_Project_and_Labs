#include <neorv32.h>

#define N 10

// ========================================================================
// 1. Cycle Counter Helper
// ========================================================================
inline uint32_t get_cycles(void) {
    uint32_t cycles;
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycles));
    return cycles;
}

// ========================================================================
// 2. Pure Software Matrix Multiplication (For Verification)
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

// ========================================================================
// 3. Independent Software Task
// ========================================================================
// This simulates "useful work" the CPU can do while the HW is busy.
void dummy_cpu_task() {
    volatile uint32_t dummy_sum = 0;
    // We run a loop to burn some CPU cycles. 
    // In a real application, this could be data pre-processing, 
    // handling network packets, or updating a display.
    for(int i = 0; i < 150; i++) {
        dummy_sum += (i * 7) ^ 0xAA;
    }
}

int main() {
    // Basic NEORV32 setup
    neorv32_rte_setup();
    neorv32_uart0_setup(19200, 0);

    neorv32_uart0_printf("\n--- Advanced MAC Accelerator: Latency Hiding ---\n");

    if (neorv32_cfs_available() == 0) {
        neorv32_uart0_printf("ERROR: CFS module not implemented!\n");
        return 1;
    }

    // Pointer to the Custom Functions Subsystem base address
    volatile uint32_t *cfs = (volatile uint32_t *) NEORV32_CFS_BASE;

    uint32_t mat_A[N][N];
    uint32_t mat_B[N][N];
    uint32_t hw_res[N][N];
    uint32_t sw_res[N][N];

    // Timing variables
    uint32_t t_start, t_end;
    uint32_t t_burst, t_blocking, t_retrieve;

    // ========================================================================
    // Data Initialization
    // ========================================================================
    neorv32_uart0_printf("Generating test data...\n");
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            mat_A[i][j] = i + j;       
            mat_B[i][j] = i * j + 1;   
        }
    }

    // Hardware Reset: Write bit 1 to Control Register (ADDR 1)
    cfs[1] = 2; 

    // ========================================================================
    // PHASE A: Write Burst (T_burst)
    // ========================================================================
    neorv32_uart0_printf("Executing FIFO write burst...\n");
    
    // Flatten arrays using pointers for maximum speed
    uint32_t *ptr_A = &mat_A[0][0];
    uint32_t *ptr_B = &mat_B[0][0];

    t_start = get_cycles();
    
    // Write 200 elements continuously to the same FIFO address (ADDR 0)
    for (int i = 0; i < 100; i++) {
        cfs[0] = ptr_A[i];
    }
    for (int i = 0; i < 100; i++) {
        cfs[0] = ptr_B[i];
    }
    
    // Trigger the Hardware: Write bit 0 to Control Register (ADDR 1)
    cfs[1] = 1; 

    t_end = get_cycles();
    t_burst = t_end - t_start;

    // ========================================================================
    // PHASE B: Latency Hiding (CPU executes independent task)
    // ========================================================================
    neorv32_uart0_printf("CPU executing independent task while HW computes...\n");
    
    dummy_cpu_task(); 

    // ========================================================================
    // PHASE C: Polling (T_blocking)
    // ========================================================================
    // If Latency Hiding is successful, the HW should be done (or almost done)
    // by the time the CPU reaches this point.
    
    t_start = get_cycles();
    
    // Wait until Status Register (ADDR 1) bit 0 (DONE) becomes 1
    while ((cfs[1] & 0x01) == 0) {
        // Blocked waiting...
    }

    t_end = get_cycles();
    t_blocking = t_end - t_start;

    // ========================================================================
    // PHASE D: Retrieve Results via Output Streaming Pseudo-FIFO
    // ========================================================================
    neorv32_uart0_printf("Retrieving results via streaming interface...\n");
    
    uint32_t *res_ptr = &hw_res[0][0];
    
    t_start = get_cycles();
    
    // Read 100 elements continuously from the same Streaming address (ADDR 2)
    for (int i = 0; i < 100; i++) {
        res_ptr[i] = cfs[2]; 
    }
    
    t_end = get_cycles();
    t_retrieve = t_end - t_start;

    // ========================================================================
    // Verification
    // ========================================================================
    sw_matrix_mult(mat_A, mat_B, sw_res);

    int errors = 0;
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (hw_res[i][j] != sw_res[i][j]) {
                errors++;
            }
        }
    }

    // ========================================================================
    // Final Report
    // ========================================================================
    if (errors == 0) {
        neorv32_uart0_printf("\nSUCCESS! Hardware output matches software.\n");
    } else {
        neorv32_uart0_printf("\nFAILED. Found %d errors.\n", errors);
    }

    neorv32_uart0_printf("\n--- PERFORMANCE METRICS ---\n");
    neorv32_uart0_printf("T_burst    (Load FIFO)    : %u cycles\n", t_burst);
    neorv32_uart0_printf("T_blocking (CPU waiting)  : %u cycles\n", t_blocking);
    neorv32_uart0_printf("T_retrieve (Read Stream)  : %u cycles\n", t_retrieve);
    
    // The ultimate test for Latency Hiding efficiency:
    if (t_blocking < 100) {
        neorv32_uart0_printf("-> EXCELLENT: Latency successfully hidden! CPU was rarely blocked.\n");
    } else {
        neorv32_uart0_printf("-> NOTE: HW took longer than the independent task. CPU had to wait.\n");
    }

    return 0;
}