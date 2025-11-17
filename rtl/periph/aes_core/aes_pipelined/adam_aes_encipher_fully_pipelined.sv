//======================================================================
// adam_aes_encipher_fully_pipelined.sv - OPTIMIZED VERSION
// --------------------
// AES Encipher avec architecture fully pipelined
// - 10 rounds instanciés physiquement
// - Registres de pipeline entre chaque round
// - Throughput: 1 bloc par cycle (après latence initiale)
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
  localparam LATENCY = 10;  
  
  //----------------------------------------------------------------
  // Pipeline stages (10 stages: 0 à 9)
  // Stage 0: AddRoundKey initial + Round 1 combinés
  // Stages 1-8: Rounds 2-9
  // Stage 9: Round final (10)
  //----------------------------------------------------------------
  logic [127:0] stage_reg [0:9];
  logic [127:0] stage_next [0:9];
  
  //----------------------------------------------------------------
  // Control signals
  //----------------------------------------------------------------
  logic [4:0]   cycle_counter_reg, cycle_counter_next;
  logic         pipeline_active_reg, pipeline_active_next;
  
  //----------------------------------------------------------------
  // FSM
  //----------------------------------------------------------------
  typedef enum logic [1:0] {
    IDLE       = 2'h0,
    PROCESSING = 2'h1,
    DONE       = 2'h2
  } state_t;
  
  state_t state_reg, state_next;
  logic   ready_reg, ready_next;
  logic   valid_reg, valid_next;
  
  //----------------------------------------------------------------
  // Round outputs (combinational)
  //----------------------------------------------------------------
  logic [127:0] round_outputs [1:10];
  
  //----------------------------------------------------------------
  // Stage 0: OPTIMISÉ - AddRoundKey initial + Round 1 fusionnés
  // Cela économise 1 cycle en combinant deux opérations séquentielles
  //----------------------------------------------------------------
  logic [127:0] initial_addroundkey;
  
  always_comb begin
    // AddRoundKey initial (combinatoire)
    initial_addroundkey = block ^ round_keys[0];
  end
  
  // Round 1 appliqué directement après AddRoundKey initial
  adam_aes_round_module #(
    .IS_FINAL_ROUND(0)
  ) round_1_inst (
    .state_in(initial_addroundkey),  // Utilise directement le résultat de AddRoundKey
    .round_key(round_keys[1]),
    .state_out(round_outputs[1])
  );
  
  always_comb begin
    stage_next[0] = round_outputs[1];
  end
  
  //----------------------------------------------------------------
  // Stages 1-8: Rounds 2-9 (SubBytes + ShiftRows + MixColumns + AddRoundKey)
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
  // Stage 9: Final round (SubBytes + ShiftRows + AddRoundKey, NO MixColumns)
  //----------------------------------------------------------------
  adam_aes_round_module #(
    .IS_FINAL_ROUND(1)
  ) final_round_inst (
    .state_in(stage_reg[8]),
    .round_key(round_keys[10]),
    .state_out(round_outputs[10])
  );
  
  always_comb begin
    stage_next[9] = round_outputs[10];
  end
  
  //----------------------------------------------------------------
  // Pipeline register update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (int s = 0; s <= 9; s++)
        stage_reg[s] <= 128'h0;
    end else begin
      if (pipeline_active_reg) begin
        for (int s = 0; s <= 9; s++)
          stage_reg[s] <= stage_next[s];
      end
    end
  end
  
  //----------------------------------------------------------------
  // Output assignment - OPTIMISÉ: sortie directe du dernier stage
  //----------------------------------------------------------------
  assign result = stage_reg[9];  // Plus de stage 11 redondant
  assign ready  = ready_reg;
  assign valid  = valid_reg;
  
  //----------------------------------------------------------------
  // Control FSM registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg           <= IDLE;
      cycle_counter_reg   <= 5'h0;
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
  // Control FSM logic
  //----------------------------------------------------------------
  always_comb begin
    // Default assignments
    state_next           = state_reg;
    cycle_counter_next   = cycle_counter_reg;
    pipeline_active_next = pipeline_active_reg;
    ready_next           = ready_reg;
    valid_next           = valid_reg;
    
    case (state_reg)
      //------------------------------------------------------------
      IDLE: begin
        ready_next = 1'b1;
        valid_next = 1'b0;
        
        if (start) begin
          state_next           = PROCESSING;
          cycle_counter_next   = 5'h0;
          pipeline_active_next = 1'b1;
          ready_next           = 1'b0;
        end
      end
      
      //------------------------------------------------------------
      PROCESSING: begin
        if (pipeline_active_reg) begin
          cycle_counter_next = cycle_counter_reg + 1;
          
          // After LATENCY cycles, result is valid
          if (cycle_counter_reg == (LATENCY - 1)) begin
            state_next = DONE;
            valid_next = 1'b1;
          end
        end
      end
      
      //------------------------------------------------------------
      DONE: begin
        pipeline_active_next = 1'b0;
        state_next           = IDLE;
      end
      
      //------------------------------------------------------------
      default: begin
        state_next = IDLE;
      end
    endcase
  end

endmodule

//======================================================================
// EOF adam_aes_encipher_fully_pipelined.sv
//======================================================================