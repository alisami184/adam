
/*
 * Copyright 2025 LIRMM
 * 
 * adam_core_cv32e40p.sv
 * 
 * Wrapper pour CV32E40P avec DEMUX d'adresse:
 * - Accès RAM (MEM[1] = 0x02xxxxxx) → OBI DIRECT
 * - Accès ROM (MEM[0] = 0x01xxxxxx) + Périphériques → OBI→AXI conversion
 * 
 * Architecture:
 *   CV32E40P Core
 *   ├─ instr_* (OBI) → adam_obi_to_axil → axil_inst
 *   └─ data_* (OBI)  → DEMUX basé sur adresse
 *                       ├─ Si RAM (0x02xxxxxx) → ram_* (OBI direct)
 *                       └─ Sinon → adam_obi_to_axil → axil_data
 */

`include "adam/macros.svh"

module adam_core_cv32e40p #(
    `ADAM_CFG_PARAMS
) (
    ADAM_SEQ.Slave   seq,
    ADAM_PAUSE.Slave pause,

    input ADDR_T boot_addr,
    input DATA_T hart_id,

    // ============ AXI-Lite Interfaces ============
    AXI_LITE.Master axil_inst,    // Instructions → MEM[0] (ROM)
    AXI_LITE.Master axil_data,    // Périphériques

    input logic irq,
    
    input  logic debug_req,
    output logic debug_unavail,

    // ============ OBI Direct vers RAM (MEM[1]) ============
    output logic  ram_req_o,
    output ADDR_T ram_addr_o,
    output logic  ram_we_o,
    output STRB_T ram_be_o,
    output DATA_T ram_wdata_o,
    input  logic  ram_rvalid_i,
    input  DATA_T ram_rdata_i
`ifdef DIFT
    // ============ DIFT (PARALLÈLE) ============
    ,
    // Vers Data Memory - Tags en écriture
    output logic       we_tag,
    output logic       wdata_tag,    
    // Depuis Data Memory - Tags en lecture
    input  logic [3:0] rdata_tag
`endif
);

    ADAM_PAUSE pause_inst ();
    ADAM_PAUSE pause_data ();

    logic  inst_req;
    logic  inst_gnt;
    logic  inst_rvalid;
    logic  inst_rready;
    ADDR_T inst_addr;
    STRB_T inst_be;
    DATA_T inst_wdata;
    logic  inst_we;
    DATA_T inst_rdata;

    logic  data_req;
    logic  data_gnt;
    logic  data_rvalid;
    logic  data_rready;
    ADDR_T data_addr;
    STRB_T data_be;
    DATA_T data_wdata;
    logic  data_we;
    DATA_T data_rdata;
    
    assign inst_rready = 1;
    assign inst_be     = 0;
    assign inst_wdata  = 0;
    assign inst_we     = 0;

    assign data_rready = 1;

    assign debug_unavail = pause.req || pause.ack;

    cv32e40p_top #(
        .FPU              (1),
        .FPU_ADDMUL_LAT   (2),
        .FPU_OTHERS_LAT   (2),
        .ZFINX            (0),
        .COREV_PULP       (0),
        .COREV_CLUSTER    (0),
        .NUM_MHPMCOUNTERS (1)
    ) cv32e40p_top (
        // Clock and reset
        .rst_ni       (!seq.rst),
        .clk_i        (seq.clk),
        .scan_cg_en_i ('0),

        // Special control signals
        .fetch_enable_i  ('1),
        .core_sleep_o    (),
        .pulp_clock_en_i ('0),

        // Configuration
        .boot_addr_i         (boot_addr),
        .mtvec_addr_i        (boot_addr),
        .dm_halt_addr_i      (DEBUG_ADDR_HALT),
        .dm_exception_addr_i (DEBUG_ADDR_EXCEPTION),
        .hart_id_i           (hart_id),

        // Instruction memory interface
        .instr_req_o    (inst_req),
        .instr_gnt_i    (inst_gnt),
        .instr_rvalid_i (inst_rvalid),
        .instr_addr_o   (inst_addr),
        .instr_rdata_i  (inst_rdata),

        // Data memory interface
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
        .debug_halted_o    ()

`ifdef DIFT
        // ============  DIFT ============
        ,
        .data_we_tag_o     (we_tag),
        .data_wdata_tag_o  (wdata_tag),
        .data_rdata_tag_i  (rdata_tag),
        .data_gnt_tag_i    (data_gnt),
        .data_rvalid_tag_i (data_rvalid)
`endif
    );
    // ========================================================================
    // DEMUX D'ADRESSE - Routage DATA seulement
    // ========================================================================

    logic is_ram_addr;
    logic is_periph_addr;

    assign is_ram_addr    = (data_addr[31:24] == 8'h02);
    assign is_periph_addr = ~is_ram_addr;     // PERIPH seulement

    // ========================================================================
    // CHEMIN RAM - OBI DIRECT
    // ========================================================================

    logic ram_req_core;
    logic ram_gnt_core;

    assign ram_req_core = data_req & is_ram_addr;
    assign ram_gnt_core = ram_req_core;  // RAM synchrone : gnt immédiat

    assign ram_req_o   = ram_req_core;
    assign ram_addr_o  = data_addr;
    assign ram_we_o    = data_we;
    assign ram_be_o    = data_be;
    assign ram_wdata_o = data_wdata;

    // ========================================================================
    // CHEMIN PÉRIPHÉRIQUES - OBI → AXI
    // ========================================================================

    logic  periph_req;
    logic  periph_gnt;
    logic  periph_rvalid;
    DATA_T periph_rdata;

    assign periph_req = data_req & is_periph_addr;

    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),

        .axil (axil_data),

        .req    (periph_req),
        .gnt    (periph_gnt),
        .addr   (data_addr),
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rvalid (periph_rvalid),
        .rready (data_rready),
        .rdata  (periph_rdata)
    );

    // ========================================================================
    // TRANSACTION TRACKER - FIFO pour mémoriser le routing
    // ========================================================================
    //
    // Quand une transaction est acceptée (req && gnt), on enregistre
    // si c'est vers RAM (0) ou PERIPH (1) dans une FIFO.
    // Quand une réponse arrive (rvalid), on POP la FIFO pour savoir
    // d'où router la réponse.
    //
    // ========================================================================

 // ========================================================================
    // TRANSACTION TRACKER - VERSION FINALE SANS INITIAL
    // ========================================================================

    localparam int TRACKER_DEPTH = 7;

    typedef enum logic {
        SRC_RAM    = 1'b0,
        SRC_PERIPH = 1'b1
    } rsp_src_t;

    // Signaux FIFO
    rsp_src_t tracker_mem [TRACKER_DEPTH];
    logic [$clog2(TRACKER_DEPTH)-1:0] tracker_wptr;
    logic [$clog2(TRACKER_DEPTH)-1:0] tracker_rptr;
    logic [$clog2(TRACKER_DEPTH):0]   tracker_count;
    logic tracker_full;
    logic tracker_empty;

    rsp_src_t tracker_push_data;
    logic     tracker_push;
    rsp_src_t tracker_pop_data;
    logic     tracker_pop;

    // PUSH : Enregistrer la source quand req && gnt
    assign tracker_push = (ram_req_core && ram_gnt_core) || 
                        (periph_req && periph_gnt);
    assign tracker_push_data = (ram_req_core && ram_gnt_core) ? SRC_RAM : SRC_PERIPH;

    // ✅ POP CORRIGÉ : Basé sur les sources, pas sur data_rvalid
    assign tracker_pop = (ram_rvalid_i || periph_rvalid) && data_rready;

    // Lecture de la FIFO
    assign tracker_pop_data = tracker_mem[tracker_rptr];

    // Logique FIFO
    always_ff @(posedge seq.clk) begin
        if (seq.rst) begin
            tracker_wptr  <= '0;
            tracker_rptr  <= '0;
            tracker_count <= '0;
        end else begin
            // PUSH
            if (tracker_push && !tracker_full) begin
                tracker_mem[tracker_wptr] <= tracker_push_data;
                tracker_wptr <= tracker_wptr + 1;
            end
            
            // POP
            if (tracker_pop && !tracker_empty) begin
                tracker_rptr <= tracker_rptr + 1;
            end
            
            // COUNT
            case ({tracker_push && !tracker_full, tracker_pop && !tracker_empty})
                2'b10:   tracker_count <= tracker_count + 1;
                2'b01:   tracker_count <= tracker_count - 1;
                default: tracker_count <= tracker_count;
            endcase
        end
    end

    assign tracker_full  = (tracker_count == TRACKER_DEPTH);
    assign tracker_empty = (tracker_count == 0);

    // ========================================================================
    // MUX DE RÉPONSE - VERSION SÉCURISÉE
    // ========================================================================

    // Grant : Bloquer si FIFO pleine
    assign data_gnt = tracker_full ? 1'b0 : 
                    (is_ram_addr ? ram_gnt_core : periph_gnt);

    // ✅ Réponse : NE LIT JAMAIS tracker_pop_data si empty
    always_comb begin
        // Valeurs par défaut
        data_rvalid = 1'b0;
        data_rdata  = '0;
        
        // ✅ Seulement si la FIFO n'est PAS vide
        if (!tracker_empty) begin
            case (tracker_pop_data)
                SRC_RAM: begin
                    data_rvalid = ram_rvalid_i;
                    data_rdata  = ram_rdata_i;
                end
                
                SRC_PERIPH: begin
                    data_rvalid = periph_rvalid;
                    data_rdata  = periph_rdata;
                end
                
                default: begin
                    // Cas X ou invalide : rester à 0
                    data_rvalid = 1'b0;
                    data_rdata  = '0;
                end
            endcase
        end
    end
    // ========================================================================
    // INSTRUCTIONS - OBI → AXI (ROM via MEM[0])
    // ========================================================================

    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) instr_obi_to_axil (
        .seq   (seq),
        .pause (pause_inst),

        .axil (axil_inst),

        .req    (inst_req),
        .gnt    (inst_gnt),
        .addr   (inst_addr),
        .we     (1'b0),
        .be     (4'b0),
        .wdata  (32'b0),
        .rvalid (inst_rvalid),
        .rready (inst_rready),
        .rdata  (inst_rdata)
    );

    // pause ==================================================================

    ADAM_PAUSE pause_null ();
    ADAM_PAUSE temp_pause [3] ();
    assign temp_pause[0].ack        = pause_inst.ack;
    assign temp_pause[1].ack        = pause_data.ack;
    assign temp_pause[2].ack        = pause_null.ack;
    assign pause_inst.req           = temp_pause[0].req;
    assign pause_data.req           = temp_pause[1].req;
    assign pause_null.req           = temp_pause[2].req;

    adam_pause_demux #(
        `ADAM_CFG_PARAMS_MAP,

        .NO_MSTS  (2),
        .PARALLEL (1)
    ) adam_pause_demux (
        .seq (seq),

        .slv (pause),
        .mst (temp_pause)
    );

endmodule

