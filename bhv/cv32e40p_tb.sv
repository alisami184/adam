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
    parameter ROM_SIZE     = 8192;         // 8KB pour instructions (matches linker)
    parameter RAM_SIZE     = 8192;         // 8KB pour data (matches linker)
    parameter RAM_BASE     = 32'h0000_1000; // RAM starts at 0x1000
    parameter BOOT_ADDR    = 32'h0000_0000; // Boot from ROM at 0x0
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
    // SIGNAUX DIFT
    // ========================================================================

    logic       data_we_tag;
    logic       data_wdata_tag;         // 1-bit tag from CPU (0=untainted, 1=tainted)
    logic [3:0] data_rdata_tag;         // 4-bit tag to CPU (1 bit per byte)
    logic       data_gnt_tag;
    logic       data_rvalid_tag;
    
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
    // DATA MEMORY (RAM) - avec décodage d'adresse
    // ========================================================================

    // Address decoding: RAM is at 0x1000+
    logic [31:0] dmem_addr;
    assign dmem_addr = data_addr - RAM_BASE;  // Offset address for RAM

    simple_mem #(
        .SIZE      (RAM_SIZE),
        .INIT_FILE ("dmem.hex")  // Optionnel: charger données initiales
    ) dmem (
        .clk    (clk),
        .rst_n  (rst_n),

        .req    (data_req),
        .gnt    (data_gnt),
        .rvalid (data_rvalid),
        .addr   (dmem_addr),        // Use offset address
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rdata  (data_rdata)
    );

    // ========================================================================
    // TAG MEMORY (DIFT) - parallèle à la RAM
    // ========================================================================

    tag_mem #(
        .SIZE      (RAM_SIZE),          // Same size as data RAM (8KB)
        .INIT_FILE ("tmem.hex")         // Tag initialization file
    ) tmem (
        .clk       (clk),
        .rst_n     (rst_n),

        .req       (data_req),          // Same request as data memory
        .gnt       (data_gnt_tag),      // Tag memory grant
        .rvalid    (data_rvalid_tag),   // Tag memory read valid
        .addr      (dmem_addr),         // Same address as data memory (offset)
        .we        (data_we_tag),       // Tag write enable from core
        .be        (data_be),           // Same byte enables as data
        .wdata_tag (data_wdata_tag),    // 1-bit tag write from core
        .rdata_tag (data_rdata_tag)     // 4-bit tag read to core (1 bit per byte)
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
    // MONITORING & DEBUG
    // ========================================================================

    // Monitor instruction fetches
    always @(posedge clk) begin
        if (inst_req && inst_gnt) begin
            $display("[%0t] IFETCH: addr=0x%08h", $time, inst_addr);
        end
        if (inst_rvalid) begin
            $display("[%0t] IFETCH_RDATA: data=0x%08h", $time, inst_rdata);
        end
    end

    // Monitor data accesses
    always @(posedge clk) begin
        if (data_req && data_gnt) begin
            if (data_we) begin
                $display("[%0t] DWRITE: addr=0x%08h data=0x%08h be=%b",
                         $time, data_addr, data_wdata, data_be);
            end else begin
                $display("[%0t] DREAD: addr=0x%08h", $time, data_addr);
            end
        end
        if (data_rvalid && !data_we) begin
            $display("[%0t] DREAD_RDATA: data=0x%08h", $time, data_rdata);
        end
    end

    // Monitor DIFT tag accesses
    always @(posedge clk) begin
        if (data_req && data_gnt_tag) begin
            if (data_we_tag) begin
                $display("[%0t] TAG_WRITE: addr=0x%08h tag=%b be=%b (if tag=1 → ALL bytes tainted)",
                         $time, data_addr, data_wdata_tag, data_be);
            end
        end
        if (data_rvalid_tag) begin
            $display("[%0t] TAG_READ: tags[3:0]=%b (1 bit per byte)",
                     $time, data_rdata_tag);
        end
    end

    // ========================================================================
    // TIMEOUT
    // ========================================================================

    initial begin
        #1000us begin
            $display("[%0t] TIMEOUT - Test did not complete", $time);
            $error("timeout");
        end
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