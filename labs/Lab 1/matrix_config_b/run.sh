#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
# PATH CONFIGURATION
# ==============================================================================
# Automatically extract the current directory name (e.g., "config_A_minimal")
APP_NAME=$(basename "$PWD")

# Relative path to the NEORV32 core
# Saliamo di 3 directory (da labs/Lab 1/config_a a root) e scendiamo in neorv32-setups/neorv32
NEORV_DIR="../../../neorv32-setups/neorv32"
TARGET_SW_DIR="$NEORV_DIR/sw/example/$APP_NAME"

# ==============================================================================
# ARGUMENT CHECK
# ==============================================================================
ACTION=$1

if [ "$ACTION" != "sim" ] && [ "$ACTION" != "compile" ]; then
    echo "❌ Error: Invalid or missing command."
    echo "Usage:"
    echo "  ./run.sh simulate -> Compiles C code, updates VHDL, and runs GHDL simulation."
    echo "  ./run.sh compile  -> Compiles C code and copies imem_image.vhd to the local hw/ folder."
    exit 1
fi

echo "========================================================"
echo "🚀 STARTING WORKFLOW FOR: $APP_NAME ($ACTION)"
echo "========================================================"

# ==============================================================================
# PHASE 1: HARDWARE & SOFTWARE SYNCHRONIZATION
# ==============================================================================
echo ">> 1. Preparing the environment..."

# Create the temporary application folder in the NEORV32 tree and clean it
mkdir -p "$TARGET_SW_DIR"
rm -rf "$TARGET_SW_DIR"/*

# Copy the software files (main.c, Makefile)
if [ -d "sw" ] && [ "$(ls -A sw)" ]; then
    cp sw/* "$TARGET_SW_DIR"/
    echo "   [+] Copied Software files -> sw/example/$APP_NAME/"
else
    echo "   [!] Warning: 'sw' folder is empty or missing."
fi

# Copy the hardware files to their respective target directories
if [ -d "hw" ] && [ "$(ls -A hw)" ]; then
    for file in hw/*.vhd; do
        # Skip if no VHDL files are found
        [ -e "$file" ] || continue 
        
        filename=$(basename "$file")
        
        if [[ "$filename" == *"_tb.vhd" ]]; then
            cp "$file" "$NEORV_DIR/sim/"
            echo "   [+] Copied Testbench: $filename -> sim/"
        elif [[ "$filename" == "neorv32_test_setup_"* ]]; then
            cp "$file" "$NEORV_DIR/rtl/test_setups/"
            echo "   [+] Copied Test Setup: $filename -> rtl/test_setups/"
        else
            cp "$file" "$NEORV_DIR/rtl/core/"
            echo "   [+] Copied Core RTL: $filename -> rtl/core/"
        fi
    done
fi

# ==============================================================================
# PHASE 2: EXECUTION (SIM vs COMPILE)
# ==============================================================================
cd "$TARGET_SW_DIR"

if [ "$ACTION" == "simulate" ]; then
    echo ""
    echo ">> 2. Compiling C Code & Starting Simulation (UART0_SIM_MODE)..."
    # This compiles the C code and triggers the GHDL simulation script automatically
    make USER_FLAGS+=-DUART0_SIM_MODE clean_all install sim

elif [ "$ACTION" == "compile" ]; then
    echo ""
    echo ">> 2. Compiling C Code & Generating VHDL Memory Images..."
    make clean_all install

    echo ""
    echo ">> 3. Retrieving generated images..."
    # Navigate back to the local project folder
    cd - > /dev/null
    
    # Copy the generated VHDL memory files back to the local hw/ directory
    cp "$NEORV_DIR/rtl/core/neorv32_imem_image.vhd" "./hw/"
    
    # Also copy dmem_image if it was generated (ignoring errors if it wasn't)
    # cp "$NEORV_DIR/rtl/core/neorv32_dmem_image.vhd" "./hw/" 2>/dev/null || true 
    
    echo "   [+] Saved: hw/neorv32_imem_image.vhd is ready for Gowin EDA synthesis!"
fi

echo "========================================================"
echo "✅ WORKFLOW COMPLETED SUCCESSFULLY!"
echo "========================================================"
