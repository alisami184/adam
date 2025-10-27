//======================================================================
// adam_aes_core_fully_pipelined.sv
// --------------------
// AES Core avec architecture fully pipelined
// Interface 100% compatible avec l'ancien adam_aes_core.sv
//
// Architecture:
// - Key expansion pipelinée (3-4 cycles)
// - Encipher fully pipelined (11 cycles)
// - Total: ~15 cycles par bloc
// - Throughput: 1 bloc/cycle après remplissage
//======================================================================

module adam_aes_core_fully_pipelined (
    input  logic         clk,
    input  logic         reset_n,
    
    // Control (INTERFACE IDENTIQUE À L'ANCIEN CORE)
    input  logic         encdec,        // 1 = encrypt, 0 = decrypt
    input  logic         start,
    output logic         ready,
    output logic         result_valid,
    
    // Key (INTERFACE IDENTIQUE)
    input  logic [255:0] key,
    input  logic         keylen,        // 0 = 128-bit, 1 = 256-bit
    
    // Data (INTERFACE IDENTIQUE)
    input  logic [127:0] block,
    output logic [127:0] result
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------
  logic [127:0] round_keys [0:10];
  logic         key_ready;
  logic         key_init;
  
  logic         enc_start;
  logic         enc_ready;
  logic         enc_valid;
  logic [127:0] enc_result;
  
  logic [255:0] prev_key_reg;     
  logic         prev_keylen_reg;  
  logic         key_valid_reg;    
  logic         key_changed;
 
  // Détection combinatoire
  always_comb begin
    key_changed = 1'b0;
    if (!key_valid_reg)                 key_changed = 1'b1;
    else if (keylen != prev_keylen_reg) key_changed = 1'b1; 
    else if (key    != prev_key_reg)    key_changed = 1'b1;
  end

  //----------------------------------------------------------------
  // FSM States (IDENTIQUES À L'ANCIEN CORE)
  //----------------------------------------------------------------
  typedef enum logic [2:0] {
    CTRL_IDLE         = 3'h0,
    CTRL_KEY_INIT     = 3'h1,
    CTRL_KEY_WAIT     = 3'h2,
    CTRL_CIPHER_START = 3'h3,
    CTRL_CIPHER_WAIT  = 3'h4,
    CTRL_DONE         = 3'h5
  } state_t;
  
  state_t state_reg, state_next;
  
  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  logic result_valid_reg, result_valid_next;
  logic ready_reg, ready_next;
  
  //----------------------------------------------------------------
  // Submodules
  //----------------------------------------------------------------
  
  // Key Expansion (pipelined)
  adam_aes_key_expansion_pipelined key_exp (
    .clk(clk),
    .reset_n(reset_n),
    .key(key),
    .keylen(keylen),
    .init(key_init),
    .round_keys(round_keys),
    .ready(key_ready)
  );
  
  // Encipher (fully pipelined)
  adam_aes_encipher_fully_pipelined enc_block (
    .clk(clk),
    .reset_n(reset_n),
    .start(enc_start),
    .keylen(keylen),
    .ready(enc_ready),
    .valid(enc_valid),
    .block(block),
    .round_keys(round_keys),
    .result(enc_result)
  );
  
  // NOTE: Decipher pas encore implémenté (TODO pour phase 2)
  // Pour l'instant, seul l'encryption est supporté
  
  //----------------------------------------------------------------
  // Output assignments
  //----------------------------------------------------------------
  assign ready        = ready_reg;
  assign result       = enc_result;
  assign result_valid = result_valid_reg;
  
  //----------------------------------------------------------------
  // Register update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg        <= CTRL_IDLE;
      result_valid_reg <= 1'b0;
      ready_reg        <= 1'b1;
      prev_key_reg      <= '0;
      prev_keylen_reg   <= 1'b0;
      key_valid_reg     <= 1'b0;

    end else begin
      state_reg        <= state_next;
      result_valid_reg <= result_valid_next;
      ready_reg        <= ready_next;

      if (state_reg == CTRL_IDLE && start && key_changed) begin
        prev_key_reg    <= key;
        prev_keylen_reg <= keylen;
        key_valid_reg   <= 1'b0;
      end
      // Quand la key expansion est prête (toutes round_keys prêtes)
      if (state_reg == CTRL_KEY_WAIT && key_ready) begin
        key_valid_reg <= 1'b1;
      end

    end
  end
  
  //----------------------------------------------------------------
  // Control FSM 
  //----------------------------------------------------------------
  always_comb begin
    // Default values
    state_next        = state_reg;
    result_valid_next = result_valid_reg;
    ready_next        = ready_reg;
    key_init          = 1'b0;
    enc_start         = 1'b0;
    
    case (state_reg)
      //------------------------------------------------------------
      CTRL_IDLE: begin
        ready_next = 1'b1;
        
        if (start) begin
          key_init          = 1'b1;
          ready_next        = 1'b0;
          result_valid_next = 1'b0;
          state_next        = CTRL_KEY_INIT;
          ready_next         = 1'b0;
          result_valid_next  = 1'b0;
          if (key_changed) begin
            key_init   = 1'b1;
            state_next = CTRL_KEY_INIT;
          end else begin
            state_next = CTRL_CIPHER_START;
          end

        end
      end
      
      //------------------------------------------------------------
      CTRL_KEY_INIT: begin
        key_init   = 1'b1;
        state_next = CTRL_KEY_WAIT;
      end
      
      //------------------------------------------------------------
      CTRL_KEY_WAIT: begin
        if (key_ready) begin
          state_next = CTRL_CIPHER_START;
        end
      end
      
      //------------------------------------------------------------
      CTRL_CIPHER_START: begin
        enc_start  = 1'b1;
        state_next = CTRL_CIPHER_WAIT;
      end
      
      //------------------------------------------------------------
      CTRL_CIPHER_WAIT: begin
        if (enc_valid) begin
          state_next = CTRL_DONE;
        end
      end
      
      //------------------------------------------------------------
      CTRL_DONE: begin
        result_valid_next = 1'b1;
        ready_next        = 1'b1;
        state_next        = CTRL_IDLE;
      end
      
      //------------------------------------------------------------
      default: begin
        state_next = CTRL_IDLE;
      end
    endcase
  end

endmodule

//======================================================================
// EOF adam_aes_core_fully_pipelined.sv
//======================================================================