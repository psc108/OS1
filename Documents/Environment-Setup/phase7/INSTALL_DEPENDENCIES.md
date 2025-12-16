# Phase 7 Dependencies Installation

## Required Dependencies

To complete Phase 7 setup, install the following dependencies:

```bash
# Install required static analysis tools
sudo dnf install -y cppcheck cppcheck-htmlreport

# Verify clang-15 is installed (should be available)
clang-15 --version

# Verify all tools are available
which gcc cppcheck valgrind clang-15 python3
```

## Verification

After installation, run:
```bash
cd Documents/Environment-Setup/phase7/
./scripts/setup_phase7_testing_validation.sh
```

All dependencies are available in the EPEL repository and should install successfully.