# Benchmarking Report: Stream-Based Accelerator on NEORV32

This document describes the implementation and benchmarking of a **stream-based matrix multiplication accelerator** integrated into the **NEORV32** RISC-V soft-core processor.

The objective of the project was to compare a more traditional, blocking accelerator access pattern with a **latency-hiding** approach based on FIFO/streaming communication. The hardware accelerator computes a **10×10 matrix multiplication**, while the software driver measures how many CPU cycles are spent sending input data, waiting for completion, and retrieving the results.

**Methodological Note:**  
All cycle measurements were obtained on the NEORV32 platform by reading the RISC-V **`cycle` CSR** in software. The benchmark focuses on **CPU-visible latency**, not just end-to-end wall time. This is important because the purpose of latency hiding is to reduce the amount of time the CPU is stalled while the accelerator runs.

## Hardware Configurations

The accelerator was implemented in two stream-oriented variants:

* **Config A (CFS FIFO Accelerator):**  
  A custom **NEORV32 CFS** design with a **memory-mapped input FIFO** at address 0, a control/status register at address 1, and a streaming output register at address 2. The CPU writes data continuously to the same address, while the accelerator drains the FIFO and performs the matrix multiplication.

  *Technical note:* The FSM first loads the FIFO contents into internal RAMs for matrices A and B, then executes the MAC loop, and finally exposes matrix C through the output stream.

* **Config B (SLINK Accelerator):**  
  A native **NEORV32 SLINK** design using the built-in streaming interface. The CPU sends input words through the RX stream and receives results through the TX stream. Two software versions were tested for this configuration:
  * a **standard API** version using `neorv32_slink_put()` and `neorv32_slink_get()`
  * a **bare-metal optimized** version using direct register access to `NEORV32_SLINK->DATA`

## 1. Benchmark: Stream-Based Matrix Multiplication

This test performs the multiplication of two $10 \\times 10$ matrices. It is a compute-heavy workload with a large amount of input data, which makes it a good candidate for burst transfers and latency hiding.

### Simulation / Measurement Results

| Configuration | Software Style | T_burst (cycles) | T_blocking (cycles) | T_retrieve (cycles) | Performance Notes |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Config A** | CFS FIFO driver | **4802** | **26** | **2417** | Best evidence of latency hiding: the CPU waits only briefly. |
| **Config B** | SLINK standard API | **7792** | — | **3927** | Correct but slower due to library call overhead. |
| **Config B** | SLINK bare-metal | **4789** | — | **2431** | Fastest software-side transfer, close to the CFS FIFO version. |

### Interpretation

The results show a clear difference between **functionally correct communication** and **efficient communication**:

* The **standard SLINK API** is easier to use, but it introduces extra overhead.
* The **bare-metal SLINK** version removes much of that overhead and significantly improves burst and retrieval times.
* The **CFS FIFO implementation** demonstrates the clearest form of **latency hiding**, since the CPU performs an independent task while the accelerator is still computing.

---

## 2. Hardware Behavior

The accelerator hardware was organized around a finite state machine.

### CFS version
The CFS accelerator uses the following phases:

1. **S_IDLE** — wait for a start command  
2. **S_LOAD** — drain the FIFO into internal RAM  
3. **S_FETCH** — allow combinational RAM data to settle  
4. **S_MAC** — multiply and accumulate one dot product  
5. **S_STORE** — write one matrix element into the result buffer  
6. **S_DONE** — raise the done flag

This architecture is suitable when the software writes input data to one address continuously and the hardware is responsible for buffering and processing it later.

### SLINK version
The SLINK accelerator uses a more direct stream-oriented state machine:

1. **S_LOAD_A** — receive matrix A  
2. **S_LOAD_B** — receive matrix B  
3. **S_FETCH** — prepare data access  
4. **S_MAC** — compute one partial product  
5. **S_STREAM_OUT** — immediately stream the computed result back

This design is closer to the philosophy of a true streaming accelerator, where input and output are handled as data flows rather than as isolated register transactions.

---

## Final Data Analysis

The comparison between the different driver styles and accelerator interfaces shows several important architectural principles:

1. **Latency hiding reduces CPU stall time.**  
   In the CFS implementation, the CPU blocking time was only **26 cycles**. This means that most of the accelerator runtime was overlapped with the independent software task. The CPU was no longer forced to spin while waiting for completion.

2. **Direct register access is faster than library abstraction.**  
   The SLINK standard API completed the same task correctly, but with noticeably higher burst and retrieval times. By switching to direct access of `NEORV32_SLINK->DATA`, the software overhead was reduced and the transfer times improved significantly.

3. **The accelerator is still the dominant compute engine.**  
   Latency hiding does not reduce the actual hardware computation time. Instead, it shifts useful CPU work into the waiting window. In other words, the algorithm may not finish sooner in absolute terms, but the processor spends less time idle.

4. **Stream-oriented communication fits this workload well.**  
   Matrix multiplication requires a large amount of structured input and produces many output words. This makes FIFO-style or stream-based communication a natural match for the problem.

---

## Critical Thinking: Did the Total Execution Time Decrease?

The answer is nuanced.

* The **hardware computation time** did not magically become shorter.
* The **CPU-visible waiting time** did decrease.
* The **overall execution strategy** improved because part of the accelerator latency was hidden behind independent software work.

So the main gain is not necessarily a dramatic reduction in raw end-to-end runtime, but a **better use of the CPU**. Instead of blocking, the CPU can perform other useful tasks. This is exactly the purpose of latency hiding in accelerator-based systems.

---

## Conclusion

This project demonstrated a practical upgrade from a blocking accelerator interface to a **stream-based latency-hiding design** on NEORV32.

Two hardware approaches were implemented:

* a **custom CFS FIFO-based accelerator**
* a **native SLINK streaming accelerator**

Three software access styles were tested:

* a CFS FIFO driver with cycle measurements,
* a standard SLINK API driver,
* a bare-metal optimized SLINK driver.

The experiments confirm that the accelerator works correctly and that stream-based communication can significantly reduce CPU blocking time. The best result came from the optimized direct-register SLINK version, while the CFS version provided the clearest demonstration of latency hiding.

**Overall conclusion:**  
For accelerator workloads with large input/output traffic, a FIFO or streaming interface is a much better architectural choice than a purely blocking register-based approach. The CPU becomes more productive, the software can overlap useful work with hardware execution, and the system behavior is closer to a real pipelined dataflow design.
