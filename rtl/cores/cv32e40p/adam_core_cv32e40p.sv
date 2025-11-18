
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
    //
    // Décodage basé sur la carte mémoire ADAM:
    // 
    // INSTRUCTIONS (instr_*):
    // - ROM (MEM[0]) : 0x01000000 - 0x01FFFFFF → Via AXI (pas de DEMUX)
    //
    // DATA (data_*):
    // - RAM (MEM[1]) : 0x02000000 - 0x02FFFFFF → OBI DIRECT
    // - PÉRIPH       : Autres adresses           → Via AXI
    //
    // ========================================================================

    logic is_ram_addr;      // True si accès DATA vers RAM (MEM[1])
    logic is_periph_addr;   // True si accès DATA vers périphériques

    // Décodage d'adresse (seulement pour DATA)
    assign is_ram_addr    = (data_addr[31:24] == 8'h02);  // RAM = 0x02xxxxxx
    assign is_periph_addr = ~is_ram_addr;                 // PÉRIPH = tout le reste

    // ========================================================================
    // CHEMIN RAM - OBI DIRECT
    // ========================================================================

    logic ram_req_core;
    
    assign ram_req_core = data_req & is_ram_addr;
    
    // Connexion directe vers RAM (pas de conversion)
    assign ram_req_o   = ram_req_core;
    assign ram_addr_o  = data_addr;
    assign ram_we_o    = data_we;
    assign ram_be_o    = data_be;
    assign ram_wdata_o = data_wdata;
    
    // ram_gnt_i et ram_rvalid_i viennent de l'extérieur (MEM[1])
    // ram_rdata_i vient de l'extérieur (MEM[1])

    // ========================================================================
    // CHEMIN PÉRIPHÉRIQUES - OBI → AXI
    // ========================================================================

    logic  periph_req;
    logic  periph_gnt;
    logic  periph_rvalid;
    DATA_T periph_rdata;
    
    assign periph_req = data_req & is_periph_addr;

    // Conversion OBI → AXI-Lite pour périphériques
    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),

        .axil (axil_data),

        // Signaux OBI depuis le core (filtrés par DEMUX)
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
    // MUX DE RÉPONSE - Routage vers le Core
    // ========================================================================
    //
    // Le core doit recevoir gnt/rvalid/rdata de la bonne source
    // On utilise une FSM simple pour tracker d'où viendra la réponse
    //
    // ========================================================================

    typedef enum logic {
        RESP_RAM,     // Réponse attendue depuis RAM
        RESP_PERIPH   // Réponse attendue depuis Périphériques (via AXI)
    } resp_state_t;

    resp_state_t resp_state_q, resp_state_d;

    // FSM - Flip-flop
    always_ff @(posedge seq.clk) begin
        if (seq.rst) begin
            resp_state_q <= RESP_PERIPH;
        end else begin
            resp_state_q <= resp_state_d;
        end
    end

    // FSM - Next state logic
    always_comb begin
        resp_state_d = resp_state_q;
        
        // Quand une requête est acceptée (gnt), on sait d'où viendra la réponse
        if (ram_req_core ) begin
            resp_state_d = RESP_RAM;
        end else if (periph_req ) begin
            resp_state_d = RESP_PERIPH;
        end
    end

    // MUX - Grant vers le core
    assign data_gnt = 1'b1;

    // MUX - Réponse vers le core (basé sur l'état FSM)
    assign data_rvalid = (resp_state_q == RESP_RAM) ? ram_rvalid_i : periph_rvalid;
    assign data_rdata  = (resp_state_q == RESP_RAM) ? ram_rdata_i  : periph_rdata;

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

