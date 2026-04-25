#!/bin/bash

# Exit immediately if any command exits with a non-zero status
set -e

# ==============================================================================
# PATH CONFIGURATION
# ==============================================================================

# Absolute path of THIS script's directory (independent of the execution context)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="$SCRIPT_DIR"
APP_NAME="$(basename "$PROJECT_DIR")"

# Resolve the absolute path to the NEORV32 repository (assuming fixed relative structure)
NEORV_DIR="$(cd "$PROJECT_DIR/../../../neorv32-setups/neorv32" && pwd)"
TARGET_SW_DIR="$NEORV_DIR/sw/example/$APP_NAME"

# ==============================================================================
# BACKUP & CLEANUP SYSTEM (TRAP)
# ==============================================================================

BACKUP_DIR=$(mktemp -d)
ADDED_FILES=()

cleanup() {
    # Prevent the cleanup function from running multiple times
    trap - EXIT INT TERM HUP

    echo ""
    echo "================================================================"
    echo "CLEANUP: Restoring original state & removing temporary files..."
    echo "================================================================"
    
    # Restore modified core files from backup
    if [ -d "$BACKUP_DIR" ] && [ "$(find "$BACKUP_DIR" -mindepth 1 -print -quit)" ]; then
        cp -a "$BACKUP_DIR"/. "$NEORV_DIR"/ 2>/dev/null || true
        echo "   [✔] Original core and simulation files restored."
    fi
    rm -rf "$BACKUP_DIR"

    # Delete files that were dynamically added to the repository
    for f in "${ADDED_FILES[@]}"; do
        rm -f "$f"
    done
    echo "   [✔] Custom and testbench files removed from NEORV32 tree."

    # Remove the custom RTL directory if it is empty
    if [ -d "$NEORV_DIR/rtl/custom" ]; then
        rmdir "$NEORV_DIR/rtl/custom" 2>/dev/null || true
    fi

    # Remove the temporary software compilation folder
    if [ -d "$TARGET_SW_DIR" ]; then
        rm -rf "$TARGET_SW_DIR"
        echo "   [✔] Temporary software folder removed."
    fi

    echo ">> Workspace is clean."
}

# Trigger the cleanup function on normal exit, CTRL+C, termination, or hang up
trap cleanup EXIT INT TERM HUP

# ==============================================================================
# ARGUMENT CHECK
# ==============================================================================

ACTION=$1

if [ "$ACTION" != "simulate" ] && [ "$ACTION" != "compile" ]; then
    echo "Error: Invalid or missing command."
    echo "Usage:"
    echo "  ./run.sh simulate -> Compile the C code and run the GHDL simulation."
    echo "  ./run.sh compile  -> Compile the C code and export memory images to hw/."
    exit 1
fi

echo "================================================================"
echo "STARTING WORKFLOW ($ACTION) FOR: $APP_NAME"
echo "================================================================"

# ==============================================================================
# PHASE 1: HARDWARE SYNCHRONIZATION
# ==============================================================================

echo ">> 1. Preparing the hardware environment..."

# Pre-create the custom RTL directory
mkdir -p "$NEORV_DIR/rtl/custom"

# Process hardware files if the local 'hw' directory exists and is not empty
if [ -d "$PROJECT_DIR/hw" ] && [ "$(ls -A "$PROJECT_DIR/hw")" ]; then
    for file in "$PROJECT_DIR"/hw/*.vhd; do
        [ -e "$file" ] || continue
        filename=$(basename "$file")
        
        # CATEGORY 1: Testbenches
        if [[ "$filename" == *"_tb.vhd" ]]; then
            DEST="$NEORV_DIR/sim/$filename"

            if [ -f "$DEST" ]; then
                mkdir -p "$BACKUP_DIR/sim"
                cp "$DEST" "$BACKUP_DIR/sim/"
            else
                ADDED_FILES+=("$DEST")
            fi

            cp "$file" "$DEST"
            echo "   [+] Testbench -> sim/$filename"

        # CATEGORY 2: Test Setups (Top-Level Wrappers)
        elif [[ "$filename" == neorv32_test_setup_* ]]; then
            DEST="$NEORV_DIR/rtl/test_setups/$filename"

            if [ -f "$DEST" ]; then
                mkdir -p "$BACKUP_DIR/rtl/test_setups"
                cp "$DEST" "$BACKUP_DIR/rtl/test_setups/"
            else
                ADDED_FILES+=("$DEST")
            fi

            cp "$file" "$DEST"
            echo "   [+] Test setup -> rtl/test_setups/$filename"

        # CATEGORY 3: Core File Overrides (e.g., neorv32_cfs.vhd)
        elif [ -f "$NEORV_DIR/rtl/core/$filename" ]; then
            DEST="$NEORV_DIR/rtl/core/$filename"

            mkdir -p "$BACKUP_DIR/rtl/core"
            cp "$DEST" "$BACKUP_DIR/rtl/core/"

            cp "$file" "$DEST"
            echo "   [+] Core override -> rtl/core/$filename"

        # CATEGORY 4: New Custom Modules
        else
            DEST="$NEORV_DIR/rtl/custom/$filename"
            cp "$file" "$DEST"
            ADDED_FILES+=("$DEST")

            echo "   [+] Custom RTL -> rtl/custom/$filename"

            # Safely inject the new module into the GHDL simulation script
            GHDL_SCRIPT="$NEORV_DIR/sim/ghdl.sh"

            if [ -f "$GHDL_SCRIPT" ]; then
                # Backup the script only if it hasn't been backed up yet
                if [ ! -f "$BACKUP_DIR/sim/ghdl.sh" ]; then
                    mkdir -p "$BACKUP_DIR/sim"
                    cp "$GHDL_SCRIPT" "$BACKUP_DIR/sim/"
                fi

                # Inject the compilation command only if it isn't already present
                if ! grep -q "$filename" "$GHDL_SCRIPT"; then
                    # Using sed -i.bak for cross-platform compatibility (Linux/macOS)
                    sed -i.bak "/neorv32_test_setup_approm.vhd/i ghdl -a \$GHDL_FLAGS ../rtl/custom/$filename" "$GHDL_SCRIPT"
                    rm -f "${GHDL_SCRIPT}.bak"
                    echo "       -> Auto-injected compilation command into sim/ghdl.sh"
                fi
            fi
        fi
    done
else
    echo "   [i] No VHDL files found in local hw/ directory. Proceeding with default hardware."
fi

# ==============================================================================
# PHASE 2: SOFTWARE PREPARATION
# ==============================================================================

# Verify the local software directory and Makefile exist
if [ ! -d "$PROJECT_DIR/sw" ] || { [ ! -f "$PROJECT_DIR/sw/Makefile" ] && [ ! -f "$PROJECT_DIR/sw/makefile" ]; }; then
    echo "Error: Local 'sw' directory or Makefile not found."
    exit 1
fi

echo ">> 2. Deploying software to the build environment..."
mkdir -p "$TARGET_SW_DIR"
cp -a "$PROJECT_DIR"/sw/* "$TARGET_SW_DIR"/

# Navigate to the target build directory
cd "$TARGET_SW_DIR"

# ==============================================================================
# PHASE 3: EXECUTION
# ==============================================================================

if [ "$ACTION" == "simulate" ]; then
    echo ""
    echo ">> 3. Building executable and launching simulation..."
    make USER_FLAGS+=-DUART0_SIM_MODE clean_all install sim

elif [ "$ACTION" == "compile" ]; then
    echo ""
    echo ">> 3. Building executable and generating memory images..."
    make clean_all install

    echo ""
    echo ">> 4. Retrieving generated VHDL images..."
    cp "$NEORV_DIR/rtl/core/neorv32_imem_image.vhd" "$PROJECT_DIR/hw/"
    
    # Safely attempt to copy the DMEM image if the compilation generated one
    cp "$NEORV_DIR/rtl/core/neorv32_dmem_image.vhd" "$PROJECT_DIR/hw/" 2>/dev/null || true

    echo "   [+] Hardware images successfully exported to local hw/ directory."
fi

# Return to the initial working directory gracefully
cd "$PROJECT_DIR"

echo "================================================================"
echo "WORKFLOW EXECUTED SUCCESSFULLY!"
echo "================================================================"
# The trap function 'cleanup' will run automatically after this point.
