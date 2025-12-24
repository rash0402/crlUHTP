#!/bin/bash
# =============================================================================
# UHTP Setup Script
# =============================================================================
# Installs dependencies for Julia and Python (only if not already installed)
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JULIA_PATH="$HOME/.juliaup/bin/julia"
PYTHON_VENV="$HOME/local/venv"

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  UHTP Setup Script${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Check Julia
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[1/4] Checking Julia...${NC}"

if [ ! -f "$JULIA_PATH" ]; then
    echo -e "${RED}Error: Julia not found at $JULIA_PATH${NC}"
    echo "Please install Julia via juliaup:"
    echo "  curl -fsSL https://install.julialang.org | sh"
    exit 1
fi

JULIA_VERSION=$("$JULIA_PATH" --version | head -1)
echo -e "${GREEN}  Found: $JULIA_VERSION${NC}"

# -----------------------------------------------------------------------------
# Check Python venv
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[2/4] Checking Python venv...${NC}"

if [ ! -d "$PYTHON_VENV" ]; then
    echo -e "${RED}Error: Python venv not found at $PYTHON_VENV${NC}"
    echo "Please create the venv:"
    echo "  python3 -m venv $PYTHON_VENV"
    exit 1
fi

source "$PYTHON_VENV/bin/activate"
PYTHON_VERSION=$(python --version)
echo -e "${GREEN}  Found: $PYTHON_VERSION (venv: $PYTHON_VENV)${NC}"

# -----------------------------------------------------------------------------
# Setup Julia packages
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[3/4] Setting up Julia packages...${NC}"

cd "$PROJECT_ROOT"

# Create Project.toml if it doesn't exist
if [ ! -f "julia/Project.toml" ]; then
    echo -e "  Creating julia/Project.toml..."
    mkdir -p julia
    cat > julia/Project.toml << 'TOML'
name = "UHTP"
uuid = "12345678-1234-1234-1234-123456789abc"
authors = ["AI-DLC Team"]
version = "0.1.0"

[deps]
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
Sockets = "6462fe0b-24de-5631-8697-dd941f90decc"
StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"
YAML = "ddb6d928-2868-570f-bddf-ab3f9cf99eb6"

[compat]
julia = "1.10"
StaticArrays = "1.9"
YAML = "0.4"
TOML
fi

# Check if packages are already installed
echo -e "  Checking Julia packages..."
PACKAGES_INSTALLED=$("$JULIA_PATH" --project=julia -e '
    using Pkg
    deps = Pkg.dependencies()
    required = ["Random", "Sockets", "StaticArrays", "YAML"]
    missing = String[]
    for pkg in required
        found = false
        for (uuid, info) in deps
            if info.name == pkg
                found = true
                break
            end
        end
        if !found
            push!(missing, pkg)
        end
    end
    if isempty(missing)
        println("OK")
    else
        println("MISSING:" * join(missing, ","))
    end
' 2>/dev/null || echo "MISSING:all")

if [[ "$PACKAGES_INSTALLED" == "OK" ]]; then
    echo -e "${GREEN}  Julia packages already installed${NC}"
else
    echo -e "  Installing Julia packages..."
    "$JULIA_PATH" --project=julia -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    echo -e "${GREEN}  Julia packages installed${NC}"
fi

# -----------------------------------------------------------------------------
# Setup Python packages
# -----------------------------------------------------------------------------
echo -e "${YELLOW}[4/4] Setting up Python packages...${NC}"

# Create requirements.txt if it doesn't exist
if [ ! -f "python/requirements.txt" ]; then
    echo -e "  Creating python/requirements.txt..."
    mkdir -p python
    cat > python/requirements.txt << 'REQUIREMENTS'
# UHTP Python Dependencies
vispy>=0.14.0
pygame>=2.5.0
pyqt6>=6.6.0
h5py>=3.10.0
numpy>=1.26.0
pyyaml>=6.0.1
REQUIREMENTS
fi

# Check if packages are already installed
echo -e "  Checking Python packages..."
PYTHON_PACKAGES_OK=true

while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] && continue
    [[ -z "$line" ]] && continue

    # Extract package name (before >= or ==)
    pkg_name=$(echo "$line" | sed -E 's/([a-zA-Z0-9_-]+).*/\1/')

    if ! python -c "import $pkg_name" 2>/dev/null; then
        # Handle package name differences (pyqt6 -> PyQt6)
        if [[ "$pkg_name" == "pyqt6" ]]; then
            if ! python -c "from PyQt6 import QtWidgets" 2>/dev/null; then
                PYTHON_PACKAGES_OK=false
                break
            fi
        else
            PYTHON_PACKAGES_OK=false
            break
        fi
    fi
done < python/requirements.txt

if [ "$PYTHON_PACKAGES_OK" = true ]; then
    echo -e "${GREEN}  Python packages already installed${NC}"
else
    echo -e "  Installing Python packages..."
    pip install -q -r python/requirements.txt
    echo -e "${GREEN}  Python packages installed${NC}"
fi

# Deactivate venv
deactivate

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "To run UHTP:"
echo "  Terminal 1: ./scripts/start_julia.sh"
echo "  Terminal 2: ./scripts/start_python.sh"
echo ""
echo "Or use: ./scripts/run_experiment.sh"
