# Questa/ModelSim DO file for CV32E40P testbench
# Simple simulation script for cv32e40p_tb

# Create work library if it doesn't exist
if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Compile CV32E40P RTL
vlog -sv -work work +incdir+../libs/cv32e40p/rtl/include \
    ../libs/cv32e40p/rtl/include/cv32e40p_fpu_pkg.sv \
    ../libs/cv32e40p/rtl/include/cv32e40p_apu_core_pkg.sv \
    ../libs/cv32e40p/rtl/include/cv32e40p_pkg.sv

# Compile FPU dependencies
vlog -sv -work work \
    ../libs/cv32e40p/rtl/vendor/pulp_platform_fpnew/src/fpnew_pkg.sv

# Compile CV32E40P core files (main modules needed for basic operation)
vlog -sv -work work +incdir+../libs/cv32e40p/rtl/include \
    ../libs/cv32e40p/rtl/cv32e40p_prefetch_controller.sv \
    ../libs/cv32e40p/rtl/cv32e40p_sleep_unit.sv \
    ../libs/cv32e40p/rtl/cv32e40p_cs_registers.sv \
    ../libs/cv32e40p/rtl/cv32e40p_alu.sv \
    ../libs/cv32e40p/rtl/cv32e40p_hwloop_regs.sv \
    ../libs/cv32e40p/rtl/cv32e40p_int_controller.sv \
    ../libs/cv32e40p/rtl/cv32e40p_controller.sv \
    ../libs/cv32e40p/rtl/cv32e40p_prefetch_buffer.sv \
    ../libs/cv32e40p/rtl/cv32e40p_if_stage.sv \
    ../libs/cv32e40p/rtl/cv32e40p_ff_one.sv \
    ../libs/cv32e40p/rtl/cv32e40p_id_stage.sv \
    ../libs/cv32e40p/rtl/cv32e40p_mult.sv \
    ../libs/cv32e40p/rtl/cv32e40p_fifo.sv \
    ../libs/cv32e40p/rtl/cv32e40p_compressed_decoder.sv \
    ../libs/cv32e40p/rtl/cv32e40p_decoder.sv \
    ../libs/cv32e40p/rtl/cv32e40p_alu_div.sv \
    ../libs/cv32e40p/rtl/cv32e40p_aligner.sv \
    ../libs/cv32e40p/rtl/cv32e40p_popcnt.sv \
    ../libs/cv32e40p/rtl/cv32e40p_register_file_ff.sv \
    ../libs/cv32e40p/rtl/cv32e40p_obi_interface.sv \
    ../libs/cv32e40p/rtl/cv32e40p_load_store_unit.sv \
    ../libs/cv32e40p/rtl/cv32e40p_ex_stage.sv \
    ../libs/cv32e40p/rtl/cv32e40p_core.sv

# Compile DIFT-related files (if they exist)
if {[file exists ../libs/cv32e40p/rtl/cv32e40p_register_file_tag_ff.sv]} {
    vlog -sv -work work +incdir+../libs/cv32e40p/rtl/include \
        ../libs/cv32e40p/rtl/cv32e40p_register_file_tag_ff.sv \
        ../libs/cv32e40p/rtl/mode_tag.sv \
        ../libs/cv32e40p/rtl/enable_tag.sv \
        ../libs/cv32e40p/rtl/load_propagation.sv \
        ../libs/cv32e40p/rtl/tag_propagation_logic.sv \
        ../libs/cv32e40p/rtl/tag_check_logic.sv \
        ../libs/cv32e40p/rtl/load_check.sv \
        ../libs/cv32e40p/rtl/check_tag.sv
}

# Top-level core wrapper
vlog -sv -work work +incdir+../libs/cv32e40p/rtl/include \
    ../libs/cv32e40p/rtl/cv32e40p_top.sv

# Compile simple_mem module
vlog -sv -work work ../rtl/simple_mem.sv

# Compile testbench
vlog -sv -work work +define+VUNIT_RUN_ALL_TESTS ../bhv/cv32e40p_tb.sv

# Run simulation
vsim -t 1ns -voptargs=+acc work.cv32e40p_tb

# Setup waveforms
add wave -noupdate -divider {Clock and Reset}
add wave -noupdate /cv32e40p_tb/clk
add wave -noupdate /cv32e40p_tb/rst_n

add wave -noupdate -divider {Instruction Interface}
add wave -noupdate /cv32e40p_tb/inst_req
add wave -noupdate /cv32e40p_tb/inst_gnt
add wave -noupdate /cv32e40p_tb/inst_rvalid
add wave -noupdate -radix hexadecimal /cv32e40p_tb/inst_addr
add wave -noupdate -radix hexadecimal /cv32e40p_tb/inst_rdata

add wave -noupdate -divider {Data Interface}
add wave -noupdate /cv32e40p_tb/data_req
add wave -noupdate /cv32e40p_tb/data_gnt
add wave -noupdate /cv32e40p_tb/data_rvalid
add wave -noupdate /cv32e40p_tb/data_we
add wave -noupdate -radix hexadecimal /cv32e40p_tb/data_addr
add wave -noupdate -radix hexadecimal /cv32e40p_tb/data_wdata
add wave -noupdate -radix hexadecimal /cv32e40p_tb/data_rdata
add wave -noupdate -radix binary /cv32e40p_tb/data_be

add wave -noupdate -divider {Core Internal - PC}
add wave -noupdate -radix hexadecimal /cv32e40p_tb/dut/core_i/pc_id

# Configure wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Run simulation
run 100us

# Zoom to show activity
wave zoom full
