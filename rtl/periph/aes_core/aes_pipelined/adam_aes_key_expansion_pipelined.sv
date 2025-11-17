//======================================================================
// adam_aes_key_expansion_pipelined.sv
// --------------------
// AES-128 Key Expansion Pipeline
// Génère les 11 round keys (round 0 à 10) pour AES-128
//
// Architecture :
// - FSM  : IDLE -> INIT -> COMPUTE (x10) -> READY
// - Latency : ~13-14 cycles
//======================================================================

module adam_aes_key_expansion_pipelined (
    input  logic         clk,
    input  logic         reset_n,
    
    input  logic [255:0] key,
    input  logic         keylen,        // 0 = AES-128 (seul mode supporté)
    input  logic         init,
    
    output logic [127:0] round_keys [0:10],
    output logic         ready
);

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  localparam AES_128_NUM_ROUNDS = 10;
  
  //----------------------------------------------------------------
  // Functions : Rcon
  //----------------------------------------------------------------
  function automatic [7:0] get_rcon(input [3:0] round_num);
    case (round_num)
      4'd1:  return 8'h01;
      4'd2:  return 8'h02;
      4'd3:  return 8'h04;
      4'd4:  return 8'h08;
      4'd5:  return 8'h10;
      4'd6:  return 8'h20;
      4'd7:  return 8'h40;
      4'd8:  return 8'h80;
      4'd9:  return 8'h1b;
      4'd10: return 8'h36;
      default: return 8'h00;
    endcase
  endfunction
  
  //----------------------------------------------------------------
  // Functions : RotWord
  //----------------------------------------------------------------
  function automatic [31:0] rotword(input [31:0] w);
    // Rotation : [b0 b1 b2 b3] -> [b1 b2 b3 b0]
    return {w[23:0], w[31:24]};
  endfunction
  
  //----------------------------------------------------------------
  // S-box instances (4 S-box pour SubWord)
  //----------------------------------------------------------------
  logic [7:0] sbox_in [0:3];
  logic [7:0] sbox_out [0:3];
  
  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : gen_sboxes
      adam_aes_sbox_byte sbox_inst (
        .sbox_byte_in(sbox_in[i]),
        .sbox_byte_out(sbox_out[i])
      );
    end
  endgenerate
  
  //----------------------------------------------------------------
  // FSM States
  //----------------------------------------------------------------
  typedef enum logic [2:0] {
    IDLE    = 3'h0,
    INIT    = 3'h1,
    COMPUTE = 3'h2,
    DONE    = 3'h3
  } state_t;
  
  state_t state_reg, state_next;
  
  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  logic [3:0]  round_ctr_reg, round_ctr_next;
  logic [31:0] words_reg [0:43];      // Stockage de tous les words
  logic        ready_reg, ready_next;
  
  // Variables de calcul (pipeline)
  logic [31:0] last_word;
  logic [31:0] rotated_word;
  logic [31:0] subbed_word;
  logic [31:0] rcon_word;
  logic [31:0] temp_word;
  logic [31:0] w0, w1, w2, w3;
  
  //----------------------------------------------------------------
  // Register update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg     <= IDLE;
      round_ctr_reg <= 4'h0;
      ready_reg     <= 1'b0;
      
      // Clear all words
      for (int w = 0; w < 44; w++)
        words_reg[w] <= 32'h0;
      
      // Clear all round keys
      for (int k = 0; k <= 10; k++)
        round_keys[k] <= 128'h0;
        
    end else begin
      state_reg     <= state_next;
      round_ctr_reg <= round_ctr_next;
      ready_reg     <= ready_next;
      
      // Update words when in INIT or COMPUTE state
      if (state_reg == INIT) begin
        // Charger les 4 premiers words (round 0)
        words_reg[0] <= key[255:224];
        words_reg[1] <= key[223:192];
        words_reg[2] <= key[191:160];
        words_reg[3] <= key[159:128];
        
        // Round key 0 = clé initiale
        round_keys[0] <= key[255:128];
      end
      
      if (state_reg == COMPUTE) begin
        // Calculer les 4 nouveaux words pour ce round
        automatic int base_idx;
        automatic logic [31:0] w0_new, w1_new, w2_new, w3_new;
        
        base_idx = round_ctr_reg * 4;
        
        // Les calculs sont faits en combinatoire dans always_comb
        // On récupère juste les résultats
        w0_new = w0;
        w1_new = w1;
        w2_new = w2;
        w3_new = w3;
        
        // Stocker les nouveaux words
        words_reg[base_idx]     <= w0_new;
        words_reg[base_idx + 1] <= w1_new;
        words_reg[base_idx + 2] <= w2_new;
        words_reg[base_idx + 3] <= w3_new;
        
        // Stocker la round key
        round_keys[round_ctr_reg] <= {w0_new, w1_new, w2_new, w3_new};
      end
    end
  end
  
  //----------------------------------------------------------------
  // Combinatorial logic : Key expansion computation
  //----------------------------------------------------------------
  always_comb begin
    // Defaults
    state_next     = state_reg;
    round_ctr_next = round_ctr_reg;
    ready_next     = ready_reg;
    
    // S-box inputs default
    for (int s = 0; s < 4; s++)
      sbox_in[s] = 8'h0;
    
    // Word computation defaults
    last_word    = 32'h0;
    rotated_word = 32'h0;
    subbed_word  = 32'h0;
    rcon_word    = 32'h0;
    temp_word    = 32'h0;
    w0 = 32'h0;
    w1 = 32'h0;
    w2 = 32'h0;
    w3 = 32'h0;
    
    //----------------------------------------------------------------
    // FSM Logic
    //----------------------------------------------------------------
    case (state_reg)
      
      //--------------------------------------------------------------
      IDLE: begin
        ready_next = 1'b0;
        
        if (init) begin
          state_next     = INIT;
          round_ctr_next = 4'h0;
        end
      end
      
      //--------------------------------------------------------------
      INIT: begin
        // Les words[0:3] sont chargés dans le always_ff
        // Round key 0 est aussi assignée
        state_next     = COMPUTE;
        round_ctr_next = 4'h1;  // Commencer au round 1
      end
      
      //--------------------------------------------------------------
      COMPUTE: begin
        if (round_ctr_reg <= AES_128_NUM_ROUNDS) begin
          // Index du dernier word du round précédent
          automatic int prev_base;
          prev_base = (round_ctr_reg - 1) * 4;
          
          // 1. Prendre le dernier word du round précédent
          last_word = words_reg[prev_base + 3];
          
          // 2. RotWord
          rotated_word = rotword(last_word);
          
          // 3. SubWord via S-box (combinatoire)
          sbox_in[0] = rotated_word[31:24];
          sbox_in[1] = rotated_word[23:16];
          sbox_in[2] = rotated_word[15:8];
          sbox_in[3] = rotated_word[7:0];
          
          // La sortie S-box est disponible en combinatoire
          subbed_word = {sbox_out[0], sbox_out[1], sbox_out[2], sbox_out[3]};
          
          // 4. XOR avec Rcon
          rcon_word = {get_rcon(round_ctr_reg), 24'h0};
          temp_word = subbed_word ^ rcon_word;
          
          // 5. Calculer les 4 nouveaux words
          w0 = words_reg[prev_base] ^ temp_word;
          w1 = words_reg[prev_base + 1] ^ w0;
          w2 = words_reg[prev_base + 2] ^ w1;
          w3 = words_reg[prev_base + 3] ^ w2;
          
          // Passer au round suivant
          round_ctr_next = round_ctr_reg + 1;
          
          // Si c'était le dernier round, passer à DONE
          if (round_ctr_reg == AES_128_NUM_ROUNDS)
            state_next = DONE;
          else
            state_next = COMPUTE;
            
        end else begin
          state_next = DONE;
        end
      end
      
      //--------------------------------------------------------------
      DONE: begin
        ready_next = 1'b1;
        state_next = IDLE;
      end
      
      //--------------------------------------------------------------
      default: begin
        state_next = IDLE;
      end
      
    endcase
  end
  
  //----------------------------------------------------------------
  // Output assignment
  //----------------------------------------------------------------
  assign ready = ready_reg;

endmodule

//======================================================================
// EOF adam_aes_key_expansion_pipelined.sv
//======================================================================