#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
# PATH CONFIGURATION (Absolute paths to ensure reliable cleanup)
# ==============================================================================
PROJECT_DIR="$PWD"

# Resolve the absolute path to the NEORV32 core repository
NEORV_DIR="$(cd "../../../neorv32-setups/neorv32" && pwd)"

# ==============================================================================
# BACKUP & CLEANUP SYSTEM (TRAP)
# ==============================================================================
BACKUP_DIR=$(mktemp -d)
ADDED_FILES=()

cleanup() {
    echo ""
    echo "========================================================"
    echo "🧹 CLEANUP: Restoring NEORV32 repository to original state..."
    echo "========================================================"
    
    # 1. Restore modified/overwritten files from backup
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR")" ]; then
        cp -a "$BACKUP_DIR"/* "$NEORV_DIR"/ 2>/dev/null || true
        echo "   [✔] Original core/sim files restored."
    fi
    rm -rf "$BACKUP_DIR"

    # 2. Delete dynamically added files (custom modules, testbenches, etc.)
    for f in "${ADDED_FILES[@]}"; do
        rm -f "$f"
    done
    echo "   [✔] Custom/Added files removed."

    # 3. Remove the custom folder if it's empty
    if [ -d "$NEORV_DIR/rtl/custom" ]; then
        rmdir "$NEORV_DIR/rtl/custom" 2>/dev/null || true
    fi

    echo ">> NEORV32 repository is clean."
}

# Trigger the cleanup function on: 
# EXIT (normal script end), INT (Ctrl+C), TERM (kill command), HUP (terminal closed)
trap cleanup EXIT INT TERM HUP


# ==============================================================================
# ARGUMENT CHECK
# ==============================================================================
ACTION=$1

if [ "$ACTION" != "simulate" ] && [ "$ACTION" != "compile" ]; then
    echo "❌ Error: Invalid or missing command."
    echo "Usage:"
    echo "  ./run.sh simulate -> Compiles C code, updates VHDL, and runs GHDL simulation."
    echo "  ./run.sh compile  -> Compiles C code and copies memory images to the local hw/ folder."
    exit 1
fi

echo "========================================================"
echo "🚀 STARTING WORKFLOW ($ACTION)"
echo "========================================================"

# ==============================================================================
# PHASE 1: HARDWARE SYNCHRONIZATION
# ==============================================================================
echo ">> 1. Preparing the hardware environment..."

# Create the folder for custom modules just in case
mkdir -p "$NEORV_DIR/rtl/custom"

# Smart VHDL file routing
if [ -d "hw" ] && [ "$(ls -A hw)" ]; then
    for file in hw/*.vhd; do
        [ -e "$file" ] || continue 
        
        filename=$(basename "$file")
        
        # CATEGORY 1: Testbench -> sim/
        if [[ "$filename" == *"_tb.vhd" ]]; then
            DEST="$NEORV_DIR/sim/$filename"
            if [ -f "$DEST" ]; then
                mkdir -p "$BACKUP_DIR/sim"
                cp "$DEST" "$BACKUP_DIR/sim/"
            else
                ADDED_FILES+=("$DEST")
            fi
            cp "$file" "$DEST"
            echo "   [+] Copied Testbench: $filename -> sim/"
            
        # CATEGORY 2: Test Setups (Top) -> rtl/test_setups/
        elif [[ "$filename" == "neorv32_test_setup_"* ]]; then
            DEST="$NEORV_DIR/rtl/test_setups/$filename"
            if [ -f "$DEST" ]; then
                mkdir -p "$BACKUP_DIR/rtl/test_setups"
                cp "$DEST" "$BACKUP_DIR/rtl/test_setups/"
            else
                ADDED_FILES+=("$DEST")
            fi
            cp "$file" "$DEST"
            echo "   [+] Copied Test Setup: $filename -> rtl/test_setups/"
            
        # CATEGORY 3: Core Overrides (e.g., neorv32_cfs.vhd) -> rtl/core/
        elif [ -f "$NEORV_DIR/rtl/core/$filename" ]; then
            DEST="$NEORV_DIR/rtl/core/$filename"
            mkdir -p "$BACKUP_DIR/rtl/core"
            cp "$DEST" "$BACKUP_DIR/rtl/core/"
            cp "$file" "$DEST"
            echo "   [+] Overriding Core RTL: $filename -> rtl/core/"
            
        # CATEGORY 4: New Custom Modules -> rtl/custom/
        else
            DEST="$NEORV_DIR/rtl/custom/$filename"
            cp "$file" "$DEST"
            ADDED_FILES+=("$DEST")
            echo "   [+] Copied Custom RTL: $filename -> rtl/custom/"
            
            # --- Auto-Injection into ghdl.sh for simulation ---
            GHDL_SCRIPT="$NEORV_DIR/sim/ghdl.sh"
            if [ -f "$GHDL_SCRIPT" ]; then
                # Backup ghdl.sh only the first time
                if [ ! -f "$BACKUP_DIR/sim/ghdl.sh" ]; then
                    mkdir -p "$BACKUP_DIR/sim"
                    cp "$GHDL_SCRIPT" "$BACKUP_DIR/sim/"
                fi
                # Inject the custom module compilation just before the test_setups
                sed -i.bak "/neorv32_test_setup_approm.vhd/i ghdl -a \$GHDL_FLAGS ../rtl/custom/$filename" "$GHDL_SCRIPT"
                rm -f "$GHDL_SCRIPT.bak"
                echo "       -> Auto-injected $filename into sim/ghdl.sh"
            fi
        fi
    done
else
    echo "   [i] No VHDL files found in hw/ directory. Proceeding with default hardware."
fi


# ==============================================================================
# PHASE 2: SOFTWARE COMPILATION & EXECUTION
# ==============================================================================
# Check if the local 'sw' directory and Makefile exist
if [ ! -d "sw" ] || { [ ! -f "sw/Makefile" ] && [ ! -f "sw/makefile" ]; }; then
    echo "❌ Error: 'sw' directory or makefile not found (accepted: sw/Makefile or sw/makefile)."
    echo "Please make sure your C code and makefile are inside the local 'sw' folder."
    exit 1
fi

cd "$PROJECT_DIR/sw"

if [ "$ACTION" == "simulate" ]; then
    echo ""
    echo ">> 2. Compiling C Code & Starting Simulation (UART0_SIM_MODE)..."
    # Pass NEORV32_HOME to Makefile and run compilation + simulation
    make NEORV32_HOME="$NEORV_DIR" USER_FLAGS+=-DUART0_SIM_MODE clean_all install sim

elif [ "$ACTION" == "compile" ]; then
    echo ""
    echo ">> 2. Compiling C Code & Generating VHDL Memory Images..."
    # Pass NEORV32_HOME to Makefile and compile
    make NEORV32_HOME="$NEORV_DIR" clean_all install

    echo ""
    echo ">> 3. Retrieving generated images..."
    # Copy the generated VHDL memory files back to the local hw/ directory
    cp "$NEORV_DIR/rtl/core/neorv32_imem_image.vhd" "$PROJECT_DIR/hw/"
    
    # Copy dmem_image if generated (ignore errors if it wasn't)
    cp "$NEORV_DIR/rtl/core/neorv32_dmem_image.vhd" "$PROJECT_DIR/hw/" 2>/dev/null || true 
    
    echo "   [+] Saved: hw/neorv32_imem_image.vhd is ready for synthesis!"
fi

echo "========================================================"
echo "✅ WORKFLOW EXECUTED SUCCESSFULLY!"
echo "========================================================"
# The trap function 'cleanup' will automatically run here to restore the files.
