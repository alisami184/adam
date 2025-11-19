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
`ifdef DIFT
    AXI_LITE.Master axil_tags,  // ✅ 3e port AXI pour tags
`endif

    input logic irq,
    
    input  logic debug_req,
    output logic debug_unavail
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

`ifdef DIFT
    // ========================================================================
    // SIGNAUX DIFT DEPUIS/VERS LE CORE
    // ========================================================================
    logic       data_we_tag;
    logic       data_wdata_tag;
    logic       data_gnt_tag;
    logic       data_rvalid_tag;
    logic [3:0] data_rdata_tag;
`endif

    assign debug_unavail = 1'b0;
    assign inst_rready = 1'b1;
    assign inst_be     = '0;
    assign inst_wdata  = '0;
    assign inst_we     = 1'b0;

    assign data_rready = 1'b1;


    // ========================================================================
    // CV32E40P CORE
    // ========================================================================
    
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
        // DIFT signals
        ,
        .data_we_tag_o     (data_we_tag),
        .data_wdata_tag_o  (data_wdata_tag),
        .data_rdata_tag_i  (data_rdata_tag),
        .data_gnt_tag_i    (data_gnt_tag),
        .data_rvalid_tag_i (data_rvalid_tag)
`endif
    );

    // ========================================================================
    // INSTRUCTIONS OBI → AXI (Inchangé)
    // ========================================================================
    
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
`ifdef DIFT
    // ========================================================================
    // DATA + TAGS : 2 CONVERTISSEURS OBI → AXI PARALLÈLES
    // ========================================================================

    // Signaux intermédiaires pour DATA converter
    logic  data_conv_req;
    logic  data_conv_gnt;
    logic  data_conv_rvalid;
    logic  data_conv_rready;
    DATA_T data_conv_rdata;

    // Signaux intermédiaires pour TAGS converter
    logic       tags_conv_req;
    logic       tags_conv_gnt;
    logic       tags_conv_rvalid;
    logic       tags_conv_rready;
    DATA_T      tags_conv_rdata;

    // ========================================================================
    // FSM ROBUSTE AVEC TRACKING INDÉPENDANT
    // ========================================================================
    
    typedef enum logic [2:0] {
        SYNC_IDLE,
        SYNC_WAIT_GNT,      // Attendre les 2 gnt
        SYNC_WAIT_RVALID    // Attendre les 2 rvalid
    } sync_state_t;

    sync_state_t sync_state_q;
    
    // Flags de tracking
    logic data_gnt_received;
    logic tags_gnt_received;
    logic data_rvalid_received;
    logic tags_rvalid_received;
    
    // Buffers de données
    DATA_T      data_buffer;
    logic [3:0] tags_buffer;

    always_ff @(posedge seq.clk) begin
        if (seq.rst) begin
            sync_state_q         <= SYNC_IDLE;
            data_gnt_received    <= 1'b0;
            tags_gnt_received    <= 1'b0;
            data_rvalid_received <= 1'b0;
            tags_rvalid_received <= 1'b0;
            data_buffer          <= '0;
            tags_buffer          <= '0;
        end else begin
            case (sync_state_q)
                SYNC_IDLE: begin
                    if (data_req) begin
                        // Accepter immédiatement et lancer les 2 transactions
                        sync_state_q         <= SYNC_WAIT_GNT;
                        data_gnt_received    <= 1'b0;
                        tags_gnt_received    <= 1'b0;
                        data_rvalid_received <= 1'b0;
                        tags_rvalid_received <= 1'b0;
                    end
                end
                
                SYNC_WAIT_GNT: begin
                    // Capturer les gnt indépendamment
                    if (data_conv_gnt) begin
                        data_gnt_received <= 1'b1;
                    end
                    
                    if (tags_conv_gnt) begin
                        tags_gnt_received <= 1'b1;
                    end
                    
                    // ✅ Passer à WAIT_RVALID quand BOTH gnt reçus
                    if (data_gnt_received && tags_gnt_received) begin
                        sync_state_q <= SYNC_WAIT_RVALID;
                    end
                end
                
                SYNC_WAIT_RVALID: begin
                    // Capturer data
                    if (data_conv_rvalid && !data_rvalid_received) begin
                        data_buffer          <= data_conv_rdata;
                        data_rvalid_received <= 1'b1;
                    end
                    
                    // Capturer tags
                    if (tags_conv_rvalid && !tags_rvalid_received) begin
                        tags_buffer          <= tags_conv_rdata[3:0];
                        tags_rvalid_received <= 1'b1;
                    end
                    
                    // ✅ Retour IDLE quand BOTH rvalid reçus
                    if (data_rvalid_received && tags_rvalid_received) begin
                        sync_state_q <= SYNC_IDLE;
                    end
                end
            endcase
        end
    end

    // ========================================================================
    // LANCEMENT DES CONVERTISSEURS
    // ========================================================================
    
    //  Lancer les deux dès qu'on accepte la requête
    assign data_conv_req = (sync_state_q == SYNC_WAIT_GNT) || 
                           (sync_state_q == SYNC_WAIT_RVALID && !data_gnt_received);
    
    assign tags_conv_req = (sync_state_q == SYNC_WAIT_GNT) || 
                           (sync_state_q == SYNC_WAIT_RVALID && !tags_gnt_received);
    
    assign data_conv_rready = 1'b1;
    assign tags_conv_rready = 1'b1;

    // Convertisseur DATA
    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),
        
        .axil (axil_data),
        
        .req    (data_conv_req),
        .gnt    (data_conv_gnt),
        .addr   (data_addr),
        .we     (data_we),
        .be     (data_be),
        .wdata  (data_wdata),
        .rvalid (data_conv_rvalid),
        .rready (data_conv_rready),
        .rdata  (data_conv_rdata)
    );

    // Convertisseur TAGS
    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) tags_obi_to_axil (
        .seq   (seq),
        .pause (pause_data),
        
        .axil (axil_tags),
        
        .req    (tags_conv_req),
        .gnt    (tags_conv_gnt),
        .addr   (data_addr),
        .we     (data_we_tag),
        .be     (data_be),
        .wdata  ({28'b0, {4{data_wdata_tag}}}),
        .rvalid (tags_conv_rvalid),
        .rready (tags_conv_rready),
        .rdata  (tags_conv_rdata)
    );

    // ========================================================================
    // SIGNAUX VERS CPU
    // ========================================================================

    // ✅ GNT : Accepter immédiatement si en IDLE
    assign data_gnt = (sync_state_q == SYNC_IDLE) && data_req;
    assign data_gnt_tag = data_gnt;

    // ✅ RVALID : Quand BOTH rvalid reçus
    assign data_rvalid = (sync_state_q == SYNC_WAIT_RVALID) && 
                         data_rvalid_received && 
                         tags_rvalid_received;
    assign data_rvalid_tag = data_rvalid;

    // ✅ RDATA : Depuis les buffers
    assign data_rdata = data_buffer;
    assign data_rdata_tag = tags_buffer;

`else
    // ========================================================================
    // SANS DIFT : UN SEUL CONVERTISSEUR DATA
    // ========================================================================
    
    adam_obi_to_axil #(
        `ADAM_CFG_PARAMS_MAP
    ) data_obi_to_axil (
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

    // ========================================================================
    // PAUSE
    // ========================================================================

    ADAM_PAUSE pause_null ();
    ADAM_PAUSE temp_pause [3] ();
    
    assign temp_pause[0].ack = pause_inst.ack;
    assign temp_pause[1].ack = pause_data.ack;
    assign temp_pause[2].ack = pause_null.ack;
    assign pause_inst.req    = temp_pause[0].req;
    assign pause_data.req    = temp_pause[1].req;
    assign pause_null.req    = temp_pause[2].req;

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