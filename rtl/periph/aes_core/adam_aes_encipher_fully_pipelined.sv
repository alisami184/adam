//======================================================================
// adam_aes_encipher_fully_pipelined.sv
// --------------------
// AES Encipher avec architecture fully pipelined
// - 10 rounds instanciés physiquement
// - Registres de pipeline entre chaque round
// - Latence: 11 cycles
// - Throughput: 1 bloc par cycle (après remplissage)
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
  localparam LATENCY = 11;  // 11 cycles de latence totale
  
  //----------------------------------------------------------------
  // Pipeline stages (12 stages: 0 à 11)
  // Stage 0: AddRoundKey initial
  // Stages 1-9: Rounds normaux
  // Stage 10: Round final
  // Stage 11: Output register
  //----------------------------------------------------------------
  logic [127:0] stage_reg [0:11];
  logic [127:0] stage_next [0:11];
  logic [11:0]  stage_we;
  
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
  // Stage 0: AddRoundKey initial (combinational + register)
  //----------------------------------------------------------------
  always_comb begin
    stage_next[0] = block ^ round_keys[0];
  end
  
  //----------------------------------------------------------------
  // Stages 1-9: Normal rounds (SubBytes + ShiftRows + MixColumns + AddRoundKey)
  //----------------------------------------------------------------
  genvar r;
  generate
    for (r = 1; r <= 9; r++) begin : gen_middle_rounds
      adam_aes_round_module #(
        .IS_FINAL_ROUND(0)
      ) round_inst (
        .state_in(stage_reg[r-1]),
        .round_key(round_keys[r]),
        .state_out(round_outputs[r])
      );
      
      always_comb begin
        stage_next[r] = round_outputs[r];
      end
    end
  endgenerate
  
  //----------------------------------------------------------------
  // Stage 10: Final round (SubBytes + ShiftRows + AddRoundKey, NO MixColumns)
  //----------------------------------------------------------------
  adam_aes_round_module #(
    .IS_FINAL_ROUND(1)
  ) final_round_inst (
    .state_in(stage_reg[9]),
    .round_key(round_keys[10]),
    .state_out(round_outputs[10])
  );
  
  always_comb begin
    stage_next[10] = round_outputs[10];
  end
  
  //----------------------------------------------------------------
  // Stage 11: Output register
  //----------------------------------------------------------------
  always_comb begin
    stage_next[11] = stage_reg[10];
  end
  
  //----------------------------------------------------------------
  // Pipeline register update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      for (int s = 0; s <= 11; s++)
        stage_reg[s] <= 128'h0;
    end else begin
      if (pipeline_active_reg) begin
        for (int s = 0; s <= 11; s++)
          stage_reg[s] <= stage_next[s];
      end
    end
  end
  
  //----------------------------------------------------------------
  // Output assignment
  //----------------------------------------------------------------
  assign result = stage_reg[11];
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