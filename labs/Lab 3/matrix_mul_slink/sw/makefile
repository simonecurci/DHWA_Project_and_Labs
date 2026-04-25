# Application makefile.
# Use this makefile to configure all relevant CPU / compiler options.

# Override the default CPU ISA
MARCH = rv32im_zicsr_zifencei

# Override the default RISC-V GCC prefix
#RISCV_PREFIX ?= riscv-none-elf-

# Override default optimization goal
EFFORT = -Os

# Add extended debug symbols
USER_FLAGS += -ggdb -gdwarf-3

# Adjust processor IMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=16k

# Adjust processor DMEM size
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=8k

# Adjust maximum heap size
#USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=1k

# Additional sources
APP_SRC = main.c
#APP_SRC += $(wildcard ./*.c)
#APP_INC += -I .


# ==============================================================================
# NEORV32 PATH CONFIGURATION
# ==============================================================================
# Set path to NEORV32 root directory. 
# The "?=" allows the run.sh bash script to override this variable automatically.
# Fallback relative path is provided just in case you run "make" manually.
NEORV32_HOME ?= ../../../neorv32-setups/neorv32

# Include the main NEORV32 makefile
include $(NEORV32_HOME)/sw/common/common.mk
