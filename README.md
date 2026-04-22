# DoHA Containerized Environment

This repository provides a fully containerized environment equipped with all the necessary tools for the **Design of Hardware Accelerators (DoHA)** lab sessions. It is specifically designed to give students a reliable, plug-and-play CLI environment for FPGA simulation and software compiling for the NeoRV32 MCU — all seamlessly contained within Docker.

Final Gowin EDA synthesis, bitstream programming, and waveform viewing should be performed natively on the host OS referencing the mapped local repository files.

## Features
- **NeoRV32 MCU Environment**: Pre-configured `neorv32-setups` repo, including automatic setup of standard `riscv-gnu-toolchain` prebuilt binaries.
- **HDL Development in VS Code:** Verilog/SystemVerilog extensions pre-configured.
- **Pre-installed simulation and verification tools**:
  - Icarus Verilog
  - GHDL
  - Verilator
  - Verible
  - Cocotb & Cocotb-test

## Building the Environment

### Building in Visual Studio Code
1. Clone this repository:
   ```sh
   git clone https://github.com/Hardware-Forge/lab_DHWA
   cd lab_DHWA
   ```
2. Open the folder in **Visual Studio Code**
3. Open the **Command Palette** (`Ctrl+Shift+P`) and select:
   ```
   Dev Containers: Rebuild and Reopen in Container
   ```
4. Wait for the process to complete (the setup script will clone required submodules and pull GCC prebuilts automatically).
5. Once inside, run your compilation and simulation commands directly from the integrated VS Code terminal!

## Using the Environment
Once inside the container, use the following commands in the terminal to launch the tools:

- **NeoRV32 Compilation**
  The RISC-V GCC toolchain is added to the system `PATH` and configured perfectly for `neorv32`. You can navigate directly to the application source directories and run `make`:
  ```sh
  cd neorv32-setups/neorv32/sw/example/blink_led
  make clean all
  ```

## Credits
This environment has been inspired by publicly available projects:
- [A Productive VSCode Setup for SystemVerilog Development - Igor Freire](https://igorfreire.com.br/2023/06/18/vscode-setup-for-systemverilog-development/)
