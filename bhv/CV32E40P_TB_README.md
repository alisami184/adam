# CV32E40P Test Bench - README

## Overview
This is a simplified test bench for the CV32E40P RISC-V core to validate basic operation and prepare for DIFT integration.

## Memory Map
```
0x00000000 - 0x00001FFF  : ROM (Instruction Memory) - 8KB
0x00001000 - 0x00002FFF  : RAM (Data Memory) - 8KB
```

## Files

### Test Bench
- `cv32e40p_tb.sv` - Main testbench with instruction and data memory
- `run_cv32e40p_tb.do` - Questa/ModelSim simulation script
- `../rtl/simple_mem.sv` - Simple memory model with OBI interface

### Software
- `../software/hello_world/src/startup.s` - Startup code (simplified, no Maestro)
- `../software/hello_world/src/main.c` - Main C application
- `../software/hello_world/link.ld` - Linker script (ROM @ 0x0, RAM @ 0x1000)

### Memory Files
- `/adam/mem0.hex` - Instruction memory initialization (simple test program)
- `/adam/dmem.hex` - Data memory initialization (empty for now)

## Building Software

### Prerequisites
- RISC-V GCC toolchain: `riscv32-unknown-elf-gcc`
- CMake 3.15+

### Build Steps
```bash
# From the adam root directory
cd software
mkdir -p build
cd build

# Configure with CMake
cmake .. -DADAM_TARGET_NAME=default

# Build hello_world
make hello_world

# The hex file will be in: build/hello_world/hello_world.hex
# Copy it to /adam/mem0.hex for simulation
cp hello_world/hello_world.hex /adam/mem0.hex
```

## Running Simulation with Questa

### From Command Line
```bash
cd /adam/bhv
vsim -do run_cv32e40p_tb.do
```

### From Questa GUI
1. Open Questa
2. Change directory to `/adam/bhv`
3. Execute: `do run_cv32e40p_tb.do`
4. Waveforms will automatically open showing:
   - Clock and reset signals
   - Instruction fetch interface (OBI)
   - Data access interface (OBI)
   - Core PC (program counter)

## Test Cases (VUnit)

The testbench includes 4 VUnit test cases:

1. **minimal** - Basic reset and clock test (10μs)
2. **simple_exec** - Execute program from memory (50μs)
3. **mem_access** - Test memory read/write operations (20μs)
4. **c_code_exec** - Execute full C program (100μs)

## DIFT Integration (Currently Disabled)

DIFT signals are present in the testbench but tied off:
```systemverilog
assign data_rdata_tag   = 4'b0;
assign data_gnt_tag     = data_gnt;
assign data_rvalid_tag  = data_rvalid;
```

### To Enable DIFT (Future Step):
1. Add tag memory module similar to instruction/data memory
2. Connect DIFT signals to tag memory
3. Enable DIFT in core parameters
4. Update software to configure DIFT CSRs (TPR, TCR)

## Debugging

### Console Output
The testbench prints transaction information:
```
[time] IFETCH: addr=0xXXXXXXXX
[time] IFETCH_RDATA: data=0xXXXXXXXX
[time] DWRITE: addr=0xXXXXXXXX data=0xXXXXXXXX be=XXXX
[time] DREAD: addr=0xXXXXXXXX
[time] DREAD_RDATA: data=0xXXXXXXXX
```

### Common Issues

**Problem**: "Can't find file /adam/mem0.hex"
**Solution**: Either compile software to generate hex file, or use the provided simple test hex

**Problem**: "Module cv32e40p_fp_wrapper not found"
**Solution**: FPU is enabled but not all modules compiled. Check run_cv32e40p_tb.do

**Problem**: "Timeout - Test did not complete"
**Solution**: Check if program is stuck. Increase timeout or verify hex file is valid.

## Simple Test Program

The provided `mem0.hex` contains a minimal hand-coded test:
```assembly
# Load immediate values
li x13, 0xDEAD
li x14, 0xBEEF

# Store to RAM (0x1000)
lui x31, 0x1
sw x13, 0(x31)
sw x14, 4(x31)

# Load back
lw x10, 0(x31)
lw x11, 4(x31)

# Add
add x12, x11, x10

# Infinite loop
loop: j loop
```

Expected behavior:
- Fetch instructions from ROM (0x0+)
- Write 0xDEAD to 0x1000
- Write 0xBEEF to 0x1004
- Read back values
- x12 should contain 0xDEAD + 0xBEEF = 0x1DD9C

## Next Steps

1. ✅ Validate basic core operation with simple test
2. ⏳ Compile and test hello_world C program
3. ⏳ Add tag memory for DIFT
4. ⏳ Enable DIFT in core
5. ⏳ Create DIFT validation tests

## References

- **CV32E40P Documentation**: https://docs.openhwgroup.org/projects/cv32e40p-user-manual/
- **OpenHW Example TB**: https://github.com/openhwgroup/cv32e40p/tree/master/example_tb
- **DIFT Implementation**: Based on Palmiero's work on RI5CY core
