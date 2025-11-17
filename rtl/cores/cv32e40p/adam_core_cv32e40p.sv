`include "adam/macros.svh"

module adam_core_cv32e40p #(
    `ADAM_CFG_PARAMS
) (
    ADAM_SEQ.Slave   seq,
    ADAM_PAUSE.Slave pause,

    input ADDR_T boot_addr,
    input DATA_T hart_id,

    AXI_LITE.Master axil_inst,
    AXI_LITE.Master axil_data,

    input logic irq,
    
    input  logic debug_req,
    output logic debug_unavail
`ifdef DIFT
    // ============ DIFT - ACCÈS DIRECT RAM ============
    ,
    // Signaux OBI direct vers RAM
    output logic  ram_req_o,
    output ADDR_T ram_addr_o,
    output logic  ram_we_o,
    output STRB_T ram_be_o,
    output DATA_T ram_wdata_o,
    input  logic  ram_rvalid_i,
    input  DATA_T ram_rdata_i,
    
    // Tags (parallèles, même timing)
    output logic              ram_we_tag_o,
    output logic              ram_wdata_tag_o,
    input  logic [3 :0]       ram_rdata_tag_i
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
`ifdef DIFT
    logic       data_we_tag;
    logic       data_wdata_tag;
    logic [3:0] data_rdata_tag;
`endif

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
        .data_we_tag_o     (data_we_tag),
        .data_wdata_tag_o  (data_wdata_tag),
        .data_rdata_tag_i  (data_rdata_tag),
        .data_gnt_tag_i    (data_gnt),
        .data_rvalid_tag_i (data_rvalid)
`endif
    );


`ifdef DIFT
//  DEMUX ADDRESS (if ram => no axi , else use axi)======================================================
    logic is_ram_addr;
    logic is_periph_addr;

    assign is_ram_addr    = (data_addr[31:24] == 8'h02) || (data_addr[31:24] == 8'h01);        // MEM[0] || MEM[1]
    assign is_periph_addr = ~is_ram_addr;

    // Split des requêtes
    logic ram_req_core;
    logic periph_req_core;
    
    assign ram_req_core    = data_req & is_ram_addr;
    assign periph_req_core = data_req & is_periph_addr;

    // ========== CHEMIN RAM DIRECT ==========
    assign ram_req_o       = ram_req_core;
    assign ram_addr_o      = data_addr;
    assign ram_we_o        = data_we;
    assign ram_be_o        = data_be;
    assign ram_wdata_o     = data_wdata;
    assign ram_we_tag_o    = data_we_tag;
    assign ram_wdata_tag_o = data_wdata_tag;
    // ram_rdata_i, ram_rvalid_i, ram_rdata_tag_i viennent de l'extérieur

    // ========== CHEMIN PÉRIPHÉRIQUES (via AXI) ==========
    logic periph_gnt;
    logic periph_rvalid;
    DATA_T periph_rdata;
    
    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_adam_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),

        .axil (axil_data),

        .req    (periph_req_core),
        .gnt    (periph_gnt),
        .addr   (data_addr),
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rvalid (periph_rvalid),
        .rready (data_rready),
        .rdata  (periph_rdata)
    );

    // ========== MUX DE RÉPONSE ==========
    // FSM pour tracker d'où vient la réponse
    typedef enum logic {RESP_RAM, RESP_PERIPH} resp_state_t;
    resp_state_t resp_state_q, resp_state_d;
    
    always_ff @(posedge seq.clk) begin
        if (seq.rst) begin
            resp_state_q <= RESP_RAM;
        end else begin
            resp_state_q <= resp_state_d;
        end
    end
    
    // Next state logic
    always_comb begin
        resp_state_d = resp_state_q;
        
        // Grant immédiat pour RAM (pas d'arbitrage)
        if (ram_req_core) begin
            resp_state_d = RESP_RAM;
        end else if (periph_req_core && periph_gnt) begin
            resp_state_d = RESP_PERIPH;
        end
    end
    
    // Grant et réponses vers le core
    assign data_gnt = is_ram_addr ? 1'b1 : periph_gnt;  // RAM: gnt immédiat
    
    assign data_rvalid    = (resp_state_q == RESP_RAM) ? ram_rvalid_i    : periph_rvalid;
    assign data_rdata     = (resp_state_q == RESP_RAM) ? ram_rdata_i     : periph_rdata;
    assign data_rdata_tag = (resp_state_q == RESP_RAM) ? ram_rdata_tag_i : 4'b0;

`else

    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_adam_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),

        .axil (axil_data),

        .req    (data_req),
        .gnt    (data_gnt),
        .addr   (data_addr),
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rvalid (data_rvalid),
        .rready (data_rready),
        .rdata  (data_rdata) 
    );
`endif

    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) instr_adam_obi_to_axil (
        .seq   (seq),
        .pause (pause_inst),

        .axil (axil_inst),

        .req    (inst_req),
        .gnt    (inst_gnt),
        .addr   (inst_addr),
        .we     ('0),
        .be     ('0),
        .wdata  ('0),
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