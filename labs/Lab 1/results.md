# Benchmarking Report: NEORV32 Hardware Optimization

This document outlines the testing and benchmarking sessions performed on the **NEORV32** RISC-V soft-core processor. The goal of this project is to measure the impact of different architectural optimizations—specifically ISA extensions and cache memories—on the processor's execution times.

**Methodological Note:** All results documented in this report were obtained via **RTL Simulation** (using GHDL in a containerized Docker environment). Execution times are measured in physical clock cycles calculated by the simulator using the `neorv32_cpu_get_cycle()` function.

## Hardware Configurations

The processor was simulated in three incremental configurations to isolate the impact of each additional hardware component:

* **Config A (Minimal Baseline):** Base `rv32i` architecture. No hardware accelerators or caches are implemented. Complex mathematical operations (such as multiplication) are resolved via software emulation loops.
* **Config B (I-Cache):** `rv32i` architecture with the **Instruction Cache** enabled (`ICACHE_EN => true`).
    * *Technical Note:* Since the test code resides in the ultra-fast internal Instruction Memory (IMEM), which already provides single-cycle access, the I-Cache is not required for latency reduction. The cache controller, however, still performs tag checks and hit/miss logic during execution.
* **Config C (Hardware Math):** `rv32imc` architecture. The **M** extension (Hardware Multiplier/Divider) is enabled in VHDL (`RISCV_ISA_M => true`), and the `-march=rv32imc` flag is passed to the C compiler. Multiplications are resolved natively by dedicated hardware.

## 1. Benchmark: Matrix Math

This test performs the multiplication of two $8 \times 8$ matrices. It is a "math-intensive" algorithm designed to stress the CPU's arithmetic capabilities and evaluate the effectiveness of the **M** ISA extension.

### Simulation Results

| Configuration | Hardware Setup | Total Cycles | Performance Notes |
| :--- | :--- | :--- | :--- |
| **Config A** | Base (`rv32i`) | 63,182 | Baseline. Multiplications emulated via software. |
| **Config B** | Base + I-Cache | 63,239 | **Slight regression.** Overhead of 57 cycles due to cache controller logic. |
| **Config C** | M Ext (`rv32imc`) | **23,837** | **~62% Optimization.** Hardware handles multiplication natively. |

---

## 2. Benchmark: Bubble Sort (Memory & Control Flow)

This test sorts an array of 64 elements. It is a "memory-intensive" and "branch-intensive" algorithm. It does not utilize multiplication but heavily stresses conditional branches and memory access operations (Load/Store).

### Simulation Results

| Configuration | Hardware Setup | Total Cycles | Performance Notes |
| :--- | :--- | :--- | :--- |
| **Config A** | Base (`rv32i`) | 125,462 | Baseline for memory and branch operations. |
| **Config B** | Base + I-Cache | 125,505 | **Slight regression.** Overhead of 43 cycles from cache check logic. |
| **Config C** | M Ext (`rv32imc`) | **125,493** | Negligible variance. The hardware multiplier is not utilized by this algorithm. |

---

## Final Data Analysis

The comparison between these two benchmarks demonstrates several fundamental principles of hardware architecture:

1.  **Dominance of Task-Specific Acceleration:** In the Matrix Math benchmark, enabling the hardware **M** extension (Config C) slashed processing cycles by approximately **62%**. This confirms that for arithmetic-heavy tasks, moving from software emulation to native hardware support is the most impactful optimization.
2.  **Cache Controller Overhead:** A notable observation from Config B is that execution is slightly *slower* (by 40–60 cycles) compared to Config A. This indicates that when code is executed from a zero-latency memory like the NEORV32 IMEM, the addition of an instruction cache provides no benefit and actually introduces a small management overhead for each memory check.
3.  **Algorithmic Resource Mapping:** In the Bubble Sort benchmark, the hardware multiplier provided no measurable gain. The performance of this algorithm is entirely bound by the Load/Store unit and the efficiency of branch handling, which were not targeted by the configurations tested here.

**Conclusion:** NEORV32 hardware optimization should be strictly profile-driven. Adding caches is counterproductive if the executable fits entirely within the IMEM, whereas specific ISA extensions like **M** are essential for numerical applications.