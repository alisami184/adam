//======================================================================
// adam_aes_key_expansion_pipelined.sv (CORRECTED)
//======================================================================

module adam_aes_key_expansion_pipelined (
    input  logic         clk,
    input  logic         reset_n,
    
    input  logic [255:0] key,
    input  logic         keylen,
    input  logic         init,
    
    output logic [127:0] round_keys [0:10],
    output logic         ready
);

  localparam AES_128_ROUNDS = 10;
  
  function automatic [7:0] get_rcon(input [3:0] round_num);
    case (round_num)
      4'd1:  get_rcon = 8'h01;
      4'd2:  get_rcon = 8'h02;
      4'd3:  get_rcon = 8'h04;
      4'd4:  get_rcon = 8'h08;
      4'd5:  get_rcon = 8'h10;
      4'd6:  get_rcon = 8'h20;
      4'd7:  get_rcon = 8'h40;
      4'd8:  get_rcon = 8'h80;
      4'd9:  get_rcon = 8'h1B;
      4'd10: get_rcon = 8'h36;
      default: get_rcon = 8'h00;
    endcase
  endfunction
  
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
  
  typedef enum logic [2:0] {
    IDLE        = 3'h0,
    INIT_ROUND0 = 3'h1,
    GEN_ROUND   = 3'h2,
    APPLY_SBOX  = 3'h3,
    READY_STATE = 3'h4
  } keyexp_state_t;
  
  keyexp_state_t state_reg, state_next;
  logic [3:0]  round_ctr_reg, round_ctr_next;
  logic [31:0] words_reg [0:43];
  logic [31:0] words_next [0:43];
  logic        words_we;
  logic [31:0] temp_word_reg, temp_word_next;
  logic        temp_word_we;
  logic        ready_reg, ready_next;
  
  function automatic [31:0] rotword(input [31:0] w);
    rotword = {w[23:0], w[31:24]};
  endfunction
  
  //----------------------------------------------------------------
  // Register update - AJOUT: écriture des round_keys ici !
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg      <= IDLE;
      ready_reg      <= 1'b0;
      round_ctr_reg  <= 4'h0;
      temp_word_reg  <= 32'h0;
      
      for (int k = 0; k <= 10; k++)
        round_keys[k] <= 128'h0;
      
      for (int w = 0; w < 44; w++)
        words_reg[w] <= 32'h0;
        
    end else begin
      state_reg     <= state_next;
      ready_reg     <= ready_next;
      round_ctr_reg <= round_ctr_next;
      
      if (temp_word_we)
        temp_word_reg <= temp_word_next;
      
      if (words_we) begin
        for (int w = 0; w < 44; w++)
          words_reg[w] <= words_next[w];
      end
            // On utilise state_next pour savoir si on vient de terminer APPLY_SBOX
      if (state_reg == APPLY_SBOX && state_next == GEN_ROUND) begin
        automatic int base_idx;
        base_idx = round_ctr_reg * 4;
        
        // Utiliser words_next (qui vient d'être calculé) au lieu de words_reg
        round_keys[round_ctr_reg] <= {
          words_next[base_idx],
          words_next[base_idx + 1],
          words_next[base_idx + 2],
          words_next[base_idx + 3]
        };
      end
      
      // Pour round_key[0], on l'assigne dans INIT_ROUND0
      if (state_reg == INIT_ROUND0) begin
        round_keys[0] <= {words_reg[0], words_reg[1], words_reg[2], words_reg[3]};
      end
    end
  end
  
  assign ready = ready_reg;
  
  //----------------------------------------------------------------
  // FSM
  //----------------------------------------------------------------
  always_comb begin
    state_next     = state_reg;
    ready_next     = ready_reg;
    round_ctr_next = round_ctr_reg;
    temp_word_next = temp_word_reg;
    temp_word_we   = 1'b0;
    words_we       = 1'b0;
    
    for (int w = 0; w < 44; w++)
      words_next[w] = words_reg[w];
    
    for (int s = 0; s < 4; s++)
      sbox_in[s] = 8'h0;
    
    case (state_reg)
      IDLE: begin
        ready_next = 1'b0;
        
        if (init) begin
          state_next     = INIT_ROUND0;
          round_ctr_next = 4'h0;
          
          words_next[0] = key[255:224];
          words_next[1] = key[223:192];
          words_next[2] = key[191:160];
          words_next[3] = key[159:128];
          words_we      = 1'b1;
        end
      end
      
      INIT_ROUND0: begin
        state_next     = GEN_ROUND;
        round_ctr_next = 4'h1;
      end
      
      GEN_ROUND: begin
        if (round_ctr_reg <= AES_128_ROUNDS) begin
          automatic logic [31:0] last_word, rotated;
          automatic int base_idx;
          
          base_idx = round_ctr_reg * 4;
          last_word = words_reg[base_idx - 1];
          rotated   = rotword(last_word);
          
          sbox_in[0] = rotated[31:24];
          sbox_in[1] = rotated[23:16];
          sbox_in[2] = rotated[15:8];
          sbox_in[3] = rotated[7:0];
          
          temp_word_next = rotated;
          temp_word_we   = 1'b1;
          
          state_next = APPLY_SBOX;
        end else begin
          state_next = READY_STATE;
        end
      end
      
      APPLY_SBOX: begin
        automatic logic [31:0] subbed, rcon_word, w0_new, w1_new, w2_new, w3_new;
        automatic int base_idx;
        
        base_idx = round_ctr_reg * 4;
        subbed = {sbox_out[0], sbox_out[1], sbox_out[2], sbox_out[3]};
        rcon_word = {get_rcon(round_ctr_reg), 24'h0};
        
        w0_new = words_reg[base_idx - 4] ^ subbed ^ rcon_word;
        w1_new = words_reg[base_idx - 3] ^ w0_new;
        w2_new = words_reg[base_idx - 2] ^ w1_new;
        w3_new = words_reg[base_idx - 1] ^ w2_new;
        
        words_next[base_idx]     = w0_new;
        words_next[base_idx + 1] = w1_new;
        words_next[base_idx + 2] = w2_new;
        words_next[base_idx + 3] = w3_new;
        words_we = 1'b1;
        
        round_ctr_next = round_ctr_reg + 1;
        state_next     = GEN_ROUND;
      end
      
      READY_STATE: begin
        ready_next = 1'b1;
        state_next = IDLE;
      end
      
      default: begin
        state_next = IDLE;
      end
    endcase
  end

endmodule