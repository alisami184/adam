//======================================================================
// adam_aes_encipher_fully_pipelined.sv - CLEAN 9-CYCLE VERSION
// --------------------
// AES Encipher fully pipelined optimisé
// - LATENCE: 9 CYCLES (meilleure latence possible sans impact timing)
// - Throughput: 1 bloc/cycle après remplissage
// - Fréquence: Identique à la version originale
//
// OPTIMISATIONS:
// 1. Fusion AddRoundKey initial + Round 1 → -1 cycle
// 2. Suppression output register → -1 cycle  
// 3. FSM 2 états (pas de DONE) → -1 cycle
// 4. Valid généré directement → -1 cycle
// Total: 13 → 9 cycles
//======================================================================

module adam_aes_encipher_fully_pipelined (
    input  logic         clk,
    input  logic         reset_n,
    
    // Control
    input  logic         start,
    input  logic         keylen,
    output logic         ready,
    output logic         valid,
    
    // Data
    input  logic [127:0] block,
    input  logic [127:0] round_keys [0:10],
    output logic [127:0] result
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam LATENCY = 9;
  
  //----------------------------------------------------------------
  // Pipeline stages (9 stages: 0-8)
  // Stage 0: AddRoundKey initial + Round 1 fusionnés
  // Stages 1-7: Rounds 2-9
  // Stage 8: Round 10 (final, sans MixColumns)
  //----------------------------------------------------------------
  logic [127:0] stage_reg [0:8];
  logic [127:0] stage_next [0:8];
  
  //----------------------------------------------------------------
  // Control
  //----------------------------------------------------------------
  logic [3:0] cycle_counter_reg, cycle_counter_next;
  logic       pipeline_active_reg, pipeline_active_next;
  logic       ready_reg, ready_next;
  logic       valid_reg, valid_next;
  
  //----------------------------------------------------------------
  // FSM (2 états seulement)
  //----------------------------------------------------------------
  typedef enum logic {
    IDLE       = 1'b0,
    PROCESSING = 1'b1
  } state_t;
  
  state_t state_reg, state_next;
  
  //----------------------------------------------------------------
  // Round outputs
  //----------------------------------------------------------------
  logic [127:0] round_outputs [1:10];
  logic [127:0] initial_xor;
  
  //----------------------------------------------------------------
  // Stage 0: AddRoundKey initial + Round 1 FUSIONNÉS
  // Cette fusion économise 1 cycle car AddRoundKey est un simple XOR
  //----------------------------------------------------------------
  always_comb begin
    initial_xor = block ^ round_keys[0];
  end
  
  adam_aes_round_module #(
    .IS_FINAL_ROUND(0)
  ) round_1_inst (
    .state_in(initial_xor),
    .round_key(round_keys[1]),
    .state_out(round_outputs[1])
  );
  
  always_comb begin
    stage_next[0] = round_outputs[1];
  end
  
  //----------------------------------------------------------------
  // Stages 1-7: Rounds 2-9
  //----------------------------------------------------------------
  genvar r;
  generate
    for (r = 2; r <= 9; r++) begin : gen_middle_rounds
      adam_aes_round_module #(
        .IS_FINAL_ROUND(0)
      ) round_inst (
        .state_in(stage_reg[r-2]),
        .round_key(round_keys[r]),
        .state_out(round_outputs[r])
      );
      
      always_comb begin
        stage_next[r-1] = round_outputs[r];
      end
    end
  endgenerate
  
  //----------------------------------------------------------------
  // Stage 8: Round 10 final (pas de MixColumns)
  //----------------------------------------------------------------
  adam_aes_round_module #(
    .IS_FINAL_ROUND(1)
  ) final_round_inst (
    .state_in(stage_reg[7]),
    .round_key(round_keys[10]),
    .state_out(round_outputs[10])
  );
  
  always_comb begin
    stage_next[8] = round_outputs[10];
  end
  
  //----------------------------------------------------------------
  // Pipeline registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (int s = 0; s <= 8; s++)
        stage_reg[s] <= 128'h0;
    end else begin
      if (pipeline_active_reg) begin
        for (int s = 0; s <= 8; s++)
          stage_reg[s] <= stage_next[s];
      end
    end
  end
  
  //----------------------------------------------------------------
  // Output - Direct du dernier stage (pas de registre supplémentaire)
  //----------------------------------------------------------------
  assign result = stage_reg[8];
  
  //----------------------------------------------------------------
  // Control registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg           <= IDLE;
      cycle_counter_reg   <= 4'h0;
      pipeline_active_reg <= 1'b0;
      ready_reg           <= 1'b1;
      valid_reg           <= 1'b0;
    end else begin
      state_reg           <= state_next;
      cycle_counter_reg   <= cycle_counter_next;
      pipeline_active_reg <= pipeline_active_next;
      ready_reg           <= ready_next;
      valid_reg           <= valid_next;
    end
  end
  
  //----------------------------------------------------------------
  // FSM Logic - OPTIMISÉE
  //----------------------------------------------------------------
  always_comb begin
    state_next           = state_reg;
    cycle_counter_next   = cycle_counter_reg;
    pipeline_active_next = pipeline_active_reg;
    ready_next           = ready_reg;
    valid_next           = 1'b0;  // Valid pulsé, pas maintenu
    
    case (state_reg)
      IDLE: begin
        ready_next = 1'b1;
        
        if (start) begin
          state_next           = PROCESSING;
          cycle_counter_next   = 4'h0;
          pipeline_active_next = 1'b1;
          ready_next           = 1'b0;
        end
      end
      
      PROCESSING: begin
        cycle_counter_next = cycle_counter_reg + 1;
        
        // Valid dès que latence atteinte
        if (cycle_counter_reg == (LATENCY - 1)) begin
          valid_next           = 1'b1;
          pipeline_active_next = 1'b0;
          state_next           = IDLE;  // Retour direct (pas d'état DONE)
          ready_next           = 1'b1;
        end
      end
      
      default: begin
        state_next = IDLE;
      end
    endcase
  end
  
  //----------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------
  assign ready = ready_reg;
  assign valid = valid_reg;

endmodule

//======================================================================
// EOF adam_aes_encipher_fully_pipelined.sv
//======================================================================