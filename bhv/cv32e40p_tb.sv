/*
 * cv32e40p_simple_tb.sv
 * 
 * Testbench simple pour CV32E40P avec DIFT désactivé
 * - ROM séparée pour instructions (avec INIT_FILE)
 * - RAM séparée pour data
 * - Interface OBI directe via simple_mem
 */

`timescale 1ns/1ps
`include "vunit_defines.svh"

module cv32e40p_tb;

    // ========================================================================
    // PARAMETRES
    // ========================================================================
    
    parameter CLK_PERIOD   = 10;           // 100MHz
    parameter ROM_SIZE     = 65536;        // 64KB pour instructions
    parameter RAM_SIZE     = 65536;        // 64KB pour data
    parameter BOOT_ADDR    = 32'h0000_0000;
    parameter DEBUG_ADDR_HALT      = 32'h1A11_0800;
    parameter DEBUG_ADDR_EXCEPTION = 32'h1A11_0808;
    
    // ========================================================================
    // SIGNAUX GENERAUX
    // ========================================================================
    
    logic clk;
    logic rst_n;
    
    // ========================================================================
    // INTERFACE INSTRUCTION (OBI)
    // ========================================================================
    
    logic        inst_req;
    logic        inst_gnt;
    logic        inst_rvalid;
    logic [31:0] inst_addr;
    logic [31:0] inst_rdata;
    
    // ========================================================================
    // INTERFACE DATA (OBI)
    // ========================================================================
    
    logic        data_req;
    logic        data_gnt;
    logic        data_rvalid;
    logic [31:0] data_addr;
    logic [3:0]  data_be;
    logic [31:0] data_wdata;
    logic        data_we;
    logic [31:0] data_rdata;
    
    // ========================================================================
    // SIGNAUX DIFT (non utilisés mais nécessaires pour connexion)
    // ========================================================================
    
    logic       data_we_tag;
    logic       data_wdata_tag;
    logic [3:0] data_rdata_tag;
    logic       data_gnt_tag;
    logic       data_rvalid_tag;
    
    // Tie-off DIFT signals (DIFT désactivé)
    assign data_rdata_tag   = 4'b0;
    assign data_gnt_tag     = data_gnt;      // Mirror data_gnt
    assign data_rvalid_tag  = data_rvalid;   // Mirror data_rvalid
    
    // ========================================================================
    // SIGNAUX DE CONTROLE
    // ========================================================================
    
    logic        irq;
    logic        debug_req;
    logic [31:0] hart_id;
    
    // ========================================================================
    // GENERATEUR CLOCK
    // ========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ========================================================================
    // INSTRUCTION MEMORY (ROM)
    // ========================================================================
    
    simple_mem #(
        .SIZE      (ROM_SIZE),
        .INIT_FILE ("/adam/mem0.hex")  // Charger depuis fichier hex
    ) imem (
        .clk    (clk),
        .rst_n  (rst_n),
        
        .req    (inst_req),
        .gnt    (inst_gnt),
        .rvalid (inst_rvalid),
        .addr   (inst_addr),
        .we     (1'b0),          // ROM = lecture seule
        .be     (4'b0),
        .wdata  (32'b0),
        .rdata  (inst_rdata)
    );
    
    // ========================================================================
    // DATA MEMORY (RAM)
    // ========================================================================
    
    simple_mem #(
        .SIZE      (RAM_SIZE),
        .INIT_FILE ("dmem.hex")  // Optionnel: charger données initiales
    ) dmem (
        .clk    (clk),
        .rst_n  (rst_n),
        
        .req    (data_req),
        .gnt    (data_gnt),
        .rvalid (data_rvalid),
        .addr   (data_addr),
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rdata  (data_rdata)
    );
    
    // ========================================================================
    // DUT: CV32E40P CORE
    // ========================================================================
    
    cv32e40p_top #(
        .FPU              (1),
        .FPU_ADDMUL_LAT   (2),
        .FPU_OTHERS_LAT   (2),
        .ZFINX            (0),
        .COREV_PULP       (0),
        .COREV_CLUSTER    (0),
        .NUM_MHPMCOUNTERS (1)
    ) dut (
        // Clock and reset
        .rst_ni       (rst_n),
        .clk_i        (clk),
        .scan_cg_en_i (1'b0),
        
        // Special control signals
        .fetch_enable_i  (1'b1),
        .core_sleep_o    (),
        .pulp_clock_en_i (1'b0),
        
        // Configuration
        .boot_addr_i         (BOOT_ADDR),
        .mtvec_addr_i        (BOOT_ADDR),
        .dm_halt_addr_i      (DEBUG_ADDR_HALT),
        .dm_exception_addr_i (DEBUG_ADDR_EXCEPTION),
        .hart_id_i           (hart_id),
        
        // Instruction memory interface (OBI)
        .instr_req_o    (inst_req),
        .instr_gnt_i    (inst_gnt),
        .instr_rvalid_i (inst_rvalid),
        .instr_addr_o   (inst_addr),
        .instr_rdata_i  (inst_rdata),
        
        // Data memory interface (OBI)
        .data_req_o    (data_req),
        .data_gnt_i    (data_gnt),
        .data_rvalid_i (data_rvalid),
        .data_addr_o   (data_addr),
        .data_be_o     (data_be),
        .data_wdata_o  (data_wdata),
        .data_we_o     (data_we),
        .data_rdata_i  (data_rdata),
        
        // Interrupt interface
        .irq_i     ({20'b0, irq, 11'b0}),
        .irq_ack_o (),
        .irq_id_o  (),
        
        // Debug interface
        .debug_req_i       (debug_req),
        .debug_havereset_o (),
        .debug_running_o   (),
        .debug_halted_o    (),
        
        // DIFT signals (connectés mais inactifs)
        .data_we_tag_o     (data_we_tag),
        .data_wdata_tag_o  (data_wdata_tag),
        .data_rdata_tag_i  (data_rdata_tag),
        .data_gnt_tag_i    (data_gnt_tag),
        .data_rvalid_tag_i (data_rvalid_tag)
    );

    // ========================================================================
    // TIMEOUT
    // ========================================================================
    
    initial begin
        #1000us $error("timeout");
    end
    
    // ========================================================================
    // HELPER TASKS
    // ========================================================================
    
    task reset_dut();
        $display("[%0t] Reset start", $time);
        rst_n     = 0;
        irq       = 0;
        debug_req = 0;
        hart_id   = 32'h0;
        
        #100;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
    endtask
    
    // ========================================================================
    // VUNIT TEST SUITE
    // ========================================================================
    
    `TEST_SUITE begin
        
        `TEST_CASE("minimal") begin
            reset_dut();
            #10us;
            $display("[%0t] Test minimal completed", $time);
        end
        
        `TEST_CASE("simple_exec") begin
            reset_dut();
            
            // Le programme est chargé depuis imem.hex automatiquement
            $display("[%0t] Executing program from imem.hex", $time);
            
            // Laisser le CPU exécuter
            #50us;
            
            $display("[%0t] Test simple_exec completed", $time);
        end
        
        `TEST_CASE("mem_access") begin
            reset_dut();
            
            // Le programme est chargé depuis imem.hex
            // Les données initiales depuis dmem.hex (optionnel)
            $display("[%0t] Testing memory access", $time);
            
            // Laisser le CPU exécuter
            #20us;
            
            $display("[%0t] Test mem_access completed", $time);
        end
        
        `TEST_CASE("c_code_exec") begin
            reset_dut();
            
            // Charger le code C compilé depuis program.hex (via imem.hex)
            $display("[%0t] Executing C code from program.hex", $time);
            
            // Laisser le CPU exécuter ton code C
            #100us;
            
            $display("[%0t] Test c_code_exec completed", $time);
        end
    end

endmodule