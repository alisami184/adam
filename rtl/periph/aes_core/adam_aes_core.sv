//======================================================================
// AES Core - Logique de contrôle avec détection de changement de clé
// ✅ OPTIMISATION: Skip key expansion si la clé n'a pas changé
//======================================================================

module adam_aes_core (
    input  logic         clk,
    input  logic         reset_n,

    // Control
    input  logic         encdec,       // 1 = encrypt, 0 = decrypt
    input  logic         start,        // launch operation
    output logic         ready,        // core ready for new command
    output logic         result_valid, // result available

    // Key
    input  logic [255:0] key,
    input  logic         keylen,       // 0 = 128-bit, 1 = 256-bit

    // Data
    input  logic [127:0] block,
    output logic [127:0] result
);

  //----------------------------------------------------------------
  // FSM states
  //----------------------------------------------------------------
  typedef enum logic [2:0] {
    CTRL_IDLE         = 3'h0,
    CTRL_KEY_INIT     = 3'h1,
    CTRL_KEY_WAIT     = 3'h2,
    CTRL_CIPHER_START = 3'h3,
    CTRL_CIPHER_WAIT  = 3'h4,
    CTRL_DONE         = 3'h5
  } state_t;

  state_t state_reg, state_new;

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  logic       result_valid_reg, result_valid_new, result_valid_we;
  logic       ready_reg, ready_new, ready_we;
  logic       init_key_expansion;   // trigger key expansion
  logic       start_cipher;         // trigger cipher operation

  logic [255:0] prev_key_reg;       // Clé précédente
  logic         prev_keylen_reg;    // Longueur précédente
  logic         key_valid_reg;      // La key expansion est faite pour cette clé

  //----------------------------------------------------------------
  // Submodule connections
  //----------------------------------------------------------------
  logic [127:0] round_key;
  logic         key_ready;

  logic         enc_next;
  logic [3:0]   enc_round_nr;
  logic [127:0] enc_new_block;
  logic         enc_ready;
  logic [31:0]  enc_sboxw;

  logic         dec_next;
  logic [3:0]   dec_round_nr;
  logic [127:0] dec_new_block;
  logic         dec_ready;

  logic [127:0] muxed_new_block;
  logic [3:0]   muxed_round_nr;
  logic         muxed_ready;

  logic [31:0]  keymem_sboxw;
  logic [31:0]  muxed_sboxw;
  logic [31:0]  new_sboxw;

  //----------------------------------------------------------------
  //  Détection de changement de clé
  //----------------------------------------------------------------
  logic key_changed;
  
  always_comb begin
    key_changed = 1'b0;
    
    if (!key_valid_reg) begin
      // Première utilisation : key expansion nécessaire
      key_changed = 1'b1;
    end else if (keylen != prev_keylen_reg) begin
      // La longueur a changé : key expansion nécessaire
      key_changed = 1'b1;
    end else if (key != prev_key_reg) begin
      // La clé a changé : key expansion nécessaire
      key_changed = 1'b1;
    end
  end

  //----------------------------------------------------------------
  // Instantiations
  //----------------------------------------------------------------
  adam_aes_encipher_block enc_block (
    .clk(clk), .reset_n(reset_n),
    .next(enc_next),
    .keylen(keylen),
    .round(enc_round_nr),
    .round_key(round_key),
    .sboxw(enc_sboxw),
    .new_sboxw(new_sboxw),
    .block(block),
    .new_block(enc_new_block),
    .ready(enc_ready)
  );

  adam_aes_decipher_block dec_block (
    .clk(clk), .reset_n(reset_n),
    .next(dec_next),
    .keylen(keylen),
    .round(dec_round_nr),
    .round_key(round_key),
    .block(block),
    .new_block(dec_new_block),
    .ready(dec_ready)
  );

  adam_aes_key_expansion key_expansion (
    .clk(clk), .reset_n(reset_n),
    .key(key),
    .keylen(keylen),
    .init(init_key_expansion),
    .round(muxed_round_nr),
    .round_key(round_key),
    .ready(key_ready),
    .sboxw(keymem_sboxw),
    .new_sboxw(new_sboxw)
  );

  adam_aes_sbox sbox_inst (.sboxw(muxed_sboxw), .new_sboxw(new_sboxw));

  //----------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------
  assign ready        = ready_reg;
  assign result       = muxed_new_block;
  assign result_valid = result_valid_reg;

  //----------------------------------------------------------------
  // Register update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      result_valid_reg <= 1'b0;
      ready_reg        <= 1'b1;
      state_reg        <= CTRL_IDLE;
      
      // Reset des registres de clé
      prev_key_reg     <= 256'h0;
      prev_keylen_reg  <= 1'b0;
      key_valid_reg    <= 1'b0;
      
    end else begin
      if (result_valid_we)
        result_valid_reg <= result_valid_new;

      if (ready_we)
        ready_reg <= ready_new;

      state_reg <= state_new;
      
      // Mise à jour des registres de clé
      // Quand on démarre une key expansion
      if (state_reg == CTRL_IDLE && start && key_changed) begin
        prev_key_reg    <= key;
        prev_keylen_reg <= keylen;
        key_valid_reg   <= 1'b0;  // Marquer comme invalide
      end
      
      // Quand la key expansion est terminée
      if (state_reg == CTRL_KEY_WAIT && key_ready) begin
        key_valid_reg <= 1'b1;  // Marquer comme valide
      end
    end
  end

  //----------------------------------------------------------------
  // Sbox mux - Priorité à l'expansion de clé pendant l'init
  //----------------------------------------------------------------
  always_comb begin
    if (state_reg == CTRL_KEY_INIT || state_reg == CTRL_KEY_WAIT)
      muxed_sboxw = keymem_sboxw;
    else
      muxed_sboxw = enc_sboxw;
  end

  //----------------------------------------------------------------
  // Enc/Dec mux
  //----------------------------------------------------------------
  always_comb begin
    enc_next = 1'b0;
    dec_next = 1'b0;

    if (encdec) begin
      enc_next        = start_cipher;
      muxed_round_nr  = enc_round_nr;
      muxed_new_block = enc_new_block;
      muxed_ready     = enc_ready;
    end else begin
      dec_next        = start_cipher;
      muxed_round_nr  = dec_round_nr;
      muxed_new_block = dec_new_block;
      muxed_ready     = dec_ready;
    end
  end

  //----------------------------------------------------------------
  // Control FSM
  //----------------------------------------------------------------
  always_comb begin
    // Default values
    init_key_expansion = 1'b0;
    start_cipher       = 1'b0;
    ready_new          = ready_reg;
    ready_we           = 1'b0;
    result_valid_new   = result_valid_reg;
    result_valid_we    = 1'b0;
    state_new          = state_reg;

    case (state_reg)
      //------------------------------------------------------------
      CTRL_IDLE: begin
        if (start) begin
          ready_new        = 1'b0;
          ready_we         = 1'b1;
          result_valid_new = 1'b0;  // Clear previous result
          result_valid_we  = 1'b1;
          
          // Skip key expansion si clé n'a pas changé
          if (key_changed) begin
            // La clé a changé → faire key expansion
            init_key_expansion = 1'b1;
            state_new          = CTRL_KEY_INIT;
          end else begin
            // La clé n'a pas changé → chiffrer directement
            state_new = CTRL_CIPHER_START;
          end
        end
      end

      //------------------------------------------------------------
      CTRL_KEY_INIT: begin
        // Continuer l'expansion de clé
        init_key_expansion = 1'b1;
        state_new          = CTRL_KEY_WAIT;
      end

      //------------------------------------------------------------
      CTRL_KEY_WAIT: begin
        // Attendre que l'expansion soit terminée
        if (key_ready) begin
          state_new = CTRL_CIPHER_START;
        end
      end

      //------------------------------------------------------------
      CTRL_CIPHER_START: begin
        // Démarrer le chiffrement/déchiffrement
        start_cipher = 1'b1;
        state_new    = CTRL_CIPHER_WAIT;
      end

      //------------------------------------------------------------
      CTRL_CIPHER_WAIT: begin
        // Attendre que le chiffrement soit terminé
        if (muxed_ready) begin
          state_new = CTRL_DONE;
        end
      end

      //------------------------------------------------------------
      CTRL_DONE: begin
        // Résultat disponible
        result_valid_new = 1'b1;
        result_valid_we  = 1'b1;
        ready_new        = 1'b1;
        ready_we         = 1'b1;
        state_new        = CTRL_IDLE;
      end

      default: begin
        state_new = CTRL_IDLE;
      end
    endcase
  end

endmodule

//======================================================================
// EOF adam_aes_core.sv
//======================================================================