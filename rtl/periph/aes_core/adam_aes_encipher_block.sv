//======================================================================
// adam_aes_encipher_block.sv - OPTIMISÉ avec S-Box Parallèle
//======================================================================

module adam_aes_encipher_block(
    input logic            clk,
    input logic            reset_n,

    input logic            next,

    input logic            keylen,
    output   [3 : 0]       round,
    input    [127 : 0]     round_key,

    output   [31 : 0]      sboxw,
    input    [31 : 0]      new_sboxw,

    input    [127 : 0]     block,
    output   [127 : 0]     new_block,
    output logic           ready
);

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam AES_128_BIT_KEY = 1'h0;
  localparam AES_256_BIT_KEY = 1'h1;

  localparam AES128_ROUNDS = 4'ha;
  localparam AES256_ROUNDS = 4'he;

  localparam NO_UPDATE    = 3'h0;
  localparam INIT_UPDATE  = 3'h1;
  localparam SBOX_UPDATE  = 3'h2;  
  localparam MAIN_UPDATE  = 3'h3;
  localparam FINAL_UPDATE = 3'h4;

  localparam CTRL_IDLE  = 2'h0;
  localparam CTRL_INIT  = 2'h1;
  localparam CTRL_SBOX  = 2'h2; 
  localparam CTRL_MAIN  = 2'h3;

  //----------------------------------------------------------------
  // Round functions with sub functions.
  //----------------------------------------------------------------
  function automatic [7 : 0] gm2(input [7 : 0] op);
    begin
      gm2 = {op[6 : 0], 1'b0} ^ (8'h1b & {8{op[7]}});
    end
  endfunction

  function automatic [7 : 0] gm3(input [7 : 0] op);
    begin
      gm3 = gm2(op) ^ op;
    end
  endfunction

  function automatic [31 : 0] mixw(input [31 : 0] w);
    logic [7 : 0] b0, b1, b2, b3;
    logic [7 : 0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31 : 24];
      b1 = w[23 : 16];
      b2 = w[15 : 08];
      b3 = w[07 : 00];

      mb0 = gm2(b0) ^ gm3(b1) ^ b2      ^ b3;
      mb1 = b0      ^ gm2(b1) ^ gm3(b2) ^ b3;
      mb2 = b0      ^ b1      ^ gm2(b2) ^ gm3(b3);
      mb3 = gm3(b0) ^ b1      ^ b2      ^ gm2(b3);

      mixw = {mb0, mb1, mb2, mb3};
    end
  endfunction

  function automatic [127 : 0] mixcolumns(input [127 : 0] data);
    logic [31 : 0] w0, w1, w2, w3;
    logic [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = mixw(w0);
      ws1 = mixw(w1);
      ws2 = mixw(w2);
      ws3 = mixw(w3);

      mixcolumns = {ws0, ws1, ws2, ws3};
    end
  endfunction

  function automatic [127 : 0] shiftrows(input [127 : 0] data);
    logic [31 : 0] w0, w1, w2, w3;
    logic [31 : 0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127 : 096];
      w1 = data[095 : 064];
      w2 = data[063 : 032];
      w3 = data[031 : 000];

      ws0 = {w0[31 : 24], w1[23 : 16], w2[15 : 08], w3[07 : 00]};
      ws1 = {w1[31 : 24], w2[23 : 16], w3[15 : 08], w0[07 : 00]};
      ws2 = {w2[31 : 24], w3[23 : 16], w0[15 : 08], w1[07 : 00]};
      ws3 = {w3[31 : 24], w0[23 : 16], w1[15 : 08], w2[07 : 00]};

      shiftrows = {ws0, ws1, ws2, ws3};
    end
  endfunction

  function automatic [127 : 0] addroundkey(input [127 : 0] data, input [127 : 0] rkey);
    begin
      addroundkey = data ^ rkey;
    end
  endfunction

  //----------------------------------------------------------------
  //  Fonction SubBytes parallèle avec 16 S-boxes
  //----------------------------------------------------------------
  logic [7:0] sbox_parallel_in [0:15];
  logic [7:0] sbox_parallel_out [0:15];
  logic [127:0] subbytes_result;

  // Instancier 16 S-boxes en parallèle
  genvar sb_idx;
  generate
    for (sb_idx = 0; sb_idx < 16; sb_idx++) begin : gen_parallel_sboxes
      adam_aes_sbox_byte sbox_inst (
        .sbox_byte_in(sbox_parallel_in[sb_idx]),
        .sbox_byte_out(sbox_parallel_out[sb_idx])
      );
    end
  endgenerate

  // Fonction pour extraire les bytes et appliquer SubBytes
  function automatic [127:0] subbytes_parallel(input [127:0] data);
    logic [127:0] result;
    integer i;
    begin
      // Cette fonction sera utilisée de manière combinatoire
      // Les S-boxes sont déjà instanciées ci-dessus
      result = data;  // Placeholder, les vraies connexions sont dans round_logic
      subbytes_parallel = result;
    end
  endfunction

  //----------------------------------------------------------------
  // Registers including update variables and write enable.
  //----------------------------------------------------------------
  logic [1 : 0]   sword_ctr_reg; 
  logic [1 : 0]   sword_ctr_new;
  logic           sword_ctr_we;
  logic           sword_ctr_inc;
  logic           sword_ctr_rst;

  logic [3 : 0]   round_ctr_reg;
  logic [3 : 0]   round_ctr_new;
  logic           round_ctr_we;
  logic           round_ctr_rst;
  logic           round_ctr_inc;

  logic [127 : 0] block_new;
  logic [31 : 0]  block_w0_reg;
  logic [31 : 0]  block_w1_reg;
  logic [31 : 0]  block_w2_reg;
  logic [31 : 0]  block_w3_reg;
  logic           block_w0_we;
  logic           block_w1_we;
  logic           block_w2_we;
  logic           block_w3_we;

  logic           ready_reg;
  logic           ready_new;
  logic           ready_we;

  logic [1 : 0]   enc_ctrl_reg;
  logic [1 : 0]   enc_ctrl_new;
  logic           enc_ctrl_we;

  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  logic [31 : 0]  muxed_sboxw;
  logic [2 : 0]   update_type;

  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign round     = round_ctr_reg;
  assign new_block = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
  assign ready     = ready_reg;
  assign sboxw     = muxed_sboxw;

  //----------------------------------------------------------------
  // reg_update
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n)
    begin: reg_update
      if (!reset_n)
        begin
          block_w0_reg  <= 32'h0;
          block_w1_reg  <= 32'h0;
          block_w2_reg  <= 32'h0;
          block_w3_reg  <= 32'h0;
          sword_ctr_reg <= 2'h0;
          round_ctr_reg <= 4'h0;
          ready_reg     <= 1'b1;
          enc_ctrl_reg  <= CTRL_IDLE;
        end
      else
        begin
          if (block_w0_we)
            block_w0_reg <= block_new[127 : 096];

          if (block_w1_we)
            block_w1_reg <= block_new[095 : 064];

          if (block_w2_we)
            block_w2_reg <= block_new[063 : 032];

          if (block_w3_we)
            block_w3_reg <= block_new[031 : 000];

          if (sword_ctr_we)
            sword_ctr_reg <= sword_ctr_new;

          if (round_ctr_we)
            round_ctr_reg <= round_ctr_new;

          if (ready_we)
            ready_reg <= ready_new;

          if (enc_ctrl_we)
            enc_ctrl_reg <= enc_ctrl_new;
        end
    end

  //----------------------------------------------------------------
  // Connexion des S-boxes parallèles
  //----------------------------------------------------------------
  logic [127:0] old_block_for_sbox;
  assign old_block_for_sbox = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};

  // Connecter les 16 bytes aux S-boxes
  always_comb begin
    for (int i = 0; i < 16; i++) begin
      sbox_parallel_in[i] = old_block_for_sbox[(i*8) +: 8];
    end
  end

  // Récupérer les résultats
  always_comb begin
    for (int i = 0; i < 16; i++) begin
      subbytes_result[(i*8) +: 8] = sbox_parallel_out[i];
    end
  end

  //----------------------------------------------------------------
  // round_logic
  //----------------------------------------------------------------
  always_comb
    begin : round_logic
      logic [127 : 0] old_block, shiftrows_block, mixcolumns_block;
      logic [127 : 0] addkey_init_block, addkey_main_block, addkey_final_block;

      block_new   = 128'h0;
      muxed_sboxw = 32'h0;
      block_w0_we = 1'b0;
      block_w1_we = 1'b0;
      block_w2_we = 1'b0;
      block_w3_we = 1'b0;

      old_block          = {block_w0_reg, block_w1_reg, block_w2_reg, block_w3_reg};
      
      // shiftrows_block utilise directement subbytes_result
      shiftrows_block    = shiftrows(subbytes_result);  // SubBytes déjà fait!
      mixcolumns_block   = mixcolumns(shiftrows_block);
      
      addkey_init_block  = addroundkey(block, round_key);
      addkey_main_block  = addroundkey(mixcolumns_block, round_key);
      addkey_final_block = addroundkey(shiftrows_block, round_key);

      case (update_type)
        INIT_UPDATE:
          begin
            block_new    = addkey_init_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        SBOX_UPDATE:
          begin
            block_new = subbytes_result;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        MAIN_UPDATE:
          begin
            block_new    = addkey_main_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        FINAL_UPDATE:
          begin
            block_new    = addkey_final_block;
            block_w0_we  = 1'b1;
            block_w1_we  = 1'b1;
            block_w2_we  = 1'b1;
            block_w3_we  = 1'b1;
          end

        default:
          begin
          end
      endcase
    end

  //----------------------------------------------------------------
  // sword_ctr 
  //----------------------------------------------------------------
  always_comb
    begin : sword_ctr
      sword_ctr_new = 2'h0;
      sword_ctr_we  = 1'b0;

      if (sword_ctr_rst)
        begin
          sword_ctr_new = 2'h0;
          sword_ctr_we  = 1'b1;
        end
      else if (sword_ctr_inc)
        begin
          sword_ctr_new = sword_ctr_reg + 1'b1;
          sword_ctr_we  = 1'b1;
        end
    end

  //----------------------------------------------------------------
  // round_ctr
  //----------------------------------------------------------------
  always_comb
    begin : round_ctr
      round_ctr_new = 4'h0;
      round_ctr_we  = 1'b0;

      if (round_ctr_rst)
        begin
          round_ctr_new = 4'h0;
          round_ctr_we  = 1'b1;
        end
      else if (round_ctr_inc)
        begin
          round_ctr_new = round_ctr_reg + 4'h1;
          round_ctr_we  = 1'b1;
        end
    end

  //----------------------------------------------------------------
  // encipher_ctrl 
  //----------------------------------------------------------------
  always_comb
    begin: encipher_ctrl
      logic [3 : 0] num_rounds;

      // Default assignments.
      sword_ctr_inc = 1'b0;
      sword_ctr_rst = 1'b0;
      round_ctr_inc = 1'b0;
      round_ctr_rst = 1'b0;
      ready_new     = 1'b0;
      ready_we      = 1'b0;
      update_type   = NO_UPDATE;
      enc_ctrl_new  = CTRL_IDLE;
      enc_ctrl_we   = 1'b0;

      if (keylen == AES_256_BIT_KEY)
        num_rounds = AES256_ROUNDS;
      else
        num_rounds = AES128_ROUNDS;

      case(enc_ctrl_reg)
        CTRL_IDLE:
          begin
            if (next)
              begin
                round_ctr_rst = 1'b1;
                ready_new     = 1'b0;
                ready_we      = 1'b1;
                enc_ctrl_new  = CTRL_INIT;
                enc_ctrl_we   = 1'b1;
              end
          end

        CTRL_INIT:
          begin
            round_ctr_inc = 1'b1;
            update_type   = INIT_UPDATE;
            enc_ctrl_new  = CTRL_SBOX;  // Aller direct à SBOX
            enc_ctrl_we   = 1'b1;
          end

        //  SBOX fait tout en 1 cycle, puis direct à MAIN
        CTRL_SBOX:
          begin
            update_type   = SBOX_UPDATE; 
            enc_ctrl_new  = CTRL_MAIN;   
            enc_ctrl_we   = 1'b1;
          end

        CTRL_MAIN:
          begin
            round_ctr_inc = 1'b1;
            if (round_ctr_reg < num_rounds)
              begin
                update_type   = MAIN_UPDATE;
                enc_ctrl_new  = CTRL_SBOX;  // Retour à SBOX (1 cycle)
                enc_ctrl_we   = 1'b1;
              end
            else
              begin
                update_type  = FINAL_UPDATE;
                ready_new    = 1'b1;
                ready_we     = 1'b1;
                enc_ctrl_new = CTRL_IDLE;
                enc_ctrl_we  = 1'b1;
              end
          end

        default:
          begin
          end
      endcase
    end

endmodule

//======================================================================
// EOF adam_aes_encipher_block.sv
//======================================================================