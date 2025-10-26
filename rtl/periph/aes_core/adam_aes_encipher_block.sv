//======================================================================
// adam_aes_encipher_block.sv
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
  // Constants
  //----------------------------------------------------------------
  localparam AES_128_BIT_KEY = 1'h0;
  localparam AES_256_BIT_KEY = 1'h1;
  localparam AES128_ROUNDS = 4'ha;

  //----------------------------------------------------------------
  // Pipeline registers (3 stages)
  //----------------------------------------------------------------
  logic [127:0] stage_sbox_reg;      // Après SubBytes
  logic [127:0] stage_shift_reg;     // Après ShiftRows
  logic [127:0] stage_mix_reg;       // Après MixColumns
  logic         stage_sbox_valid;
  logic         stage_shift_valid;
  logic         stage_mix_valid;

  logic [3:0]   round_ctr_reg;
  logic [3:0]   round_ctr_new;
  logic         round_ctr_we;
  logic         ready_reg;
  logic         ready_new;
  logic         ready_we;
  logic         busy_reg;

  //----------------------------------------------------------------
  // Functions
  //----------------------------------------------------------------
  function automatic [7:0] gm2(input [7:0] op);
    return {op[6:0], 1'b0} ^ (8'h1b & {8{op[7]}});
  endfunction

  function automatic [7:0] gm3(input [7:0] op);
    return gm2(op) ^ op;
  endfunction

  function automatic [31:0] mixw(input [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    logic [7:0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31:24];
      b1 = w[23:16];
      b2 = w[15:08];
      b3 = w[07:00];
      mb0 = gm2(b0) ^ gm3(b1) ^ b2 ^ b3;
      mb1 = b0 ^ gm2(b1) ^ gm3(b2) ^ b3;
      mb2 = b0 ^ b1 ^ gm2(b2) ^ gm3(b3);
      mb3 = gm3(b0) ^ b1 ^ b2 ^ gm2(b3);
      return {mb0, mb1, mb2, mb3};
    end
  endfunction

  function automatic [127:0] mixcolumns(input [127:0] data);
    logic [31:0] w0, w1, w2, w3;
    begin
      w0 = data[127:096];
      w1 = data[095:064];
      w2 = data[063:032];
      w3 = data[031:000];
      return {mixw(w0), mixw(w1), mixw(w2), mixw(w3)};
    end
  endfunction

  function automatic [127:0] shiftrows(input [127:0] data);
    logic [31:0] w0, w1, w2, w3;
    logic [31:0] ws0, ws1, ws2, ws3;
    begin
      w0 = data[127:096];
      w1 = data[095:064];
      w2 = data[063:032];
      w3 = data[031:000];
      ws0 = {w0[31:24], w1[23:16], w2[15:08], w3[07:00]};
      ws1 = {w1[31:24], w2[23:16], w3[15:08], w0[07:00]};
      ws2 = {w2[31:24], w3[23:16], w0[15:08], w1[07:00]};
      ws3 = {w3[31:24], w0[23:16], w1[15:08], w2[07:00]};
      return {ws0, ws1, ws2, ws3};
    end
  endfunction

  //----------------------------------------------------------------
  // S-boxes parallèles (16 instances)
  //----------------------------------------------------------------
  logic [7:0] sbox_in [0:15];
  logic [7:0] sbox_out [0:15];
  logic [127:0] subbytes_result;

  genvar i;
  generate
    for (i = 0; i < 16; i++) begin : gen_sboxes
      adam_aes_sbox_byte sbox_inst (
        .sbox_byte_in(sbox_in[i]),
        .sbox_byte_out(sbox_out[i])
      );
    end
  endgenerate

  // Connexions S-boxes
  logic [127:0] sbox_input;
  always_comb begin
    for (int j = 0; j < 16; j++) begin
      sbox_in[j] = sbox_input[(j*8) +: 8];
      subbytes_result[(j*8) +: 8] = sbox_out[j];
    end
  end

  //----------------------------------------------------------------
  // Pipeline datapath
  //----------------------------------------------------------------
  logic [127:0] init_block;
  logic [127:0] next_sbox, next_shift, next_mix;

  // AddRoundKey initial
  assign init_block = block ^ round_key;

  // Stage 1: SubBytes
  assign sbox_input = (round_ctr_reg == 4'h0) ? init_block : stage_mix_reg;
  assign next_sbox = subbytes_result;

  // Stage 2: ShiftRows
  assign next_shift = shiftrows(stage_sbox_reg);

  // Stage 3: MixColumns + AddRoundKey
  assign next_mix = (round_ctr_reg >= AES128_ROUNDS) ? 
                    (stage_shift_reg ^ round_key) :  // Final round (no MixColumns)
                    (mixcolumns(stage_shift_reg) ^ round_key);

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      stage_sbox_reg   <= 128'h0;
      stage_shift_reg  <= 128'h0;
      stage_mix_reg    <= 128'h0;
      stage_sbox_valid <= 1'b0;
      stage_shift_valid <= 1'b0;
      stage_mix_valid  <= 1'b0;
      round_ctr_reg    <= 4'h0;
      ready_reg        <= 1'b1;
      busy_reg         <= 1'b0;
    end else begin
      // Pipeline flow
      if (next && !busy_reg) begin
        // Start new encryption
        busy_reg         <= 1'b1;
        ready_reg        <= 1'b0;
        round_ctr_reg    <= 4'h1;
        stage_sbox_reg   <= next_sbox;
        stage_sbox_valid <= 1'b1;
      end else if (busy_reg) begin
        // Pipeline stages avancent
        stage_sbox_reg   <= next_sbox;
        stage_shift_reg  <= next_shift;
        stage_mix_reg    <= next_mix;
        
        stage_shift_valid <= stage_sbox_valid;
        stage_mix_valid   <= stage_shift_valid;

        // Incrément round counter
        if (stage_sbox_valid && round_ctr_reg <= AES128_ROUNDS) begin
          round_ctr_reg <= round_ctr_reg + 1'b1;
        end

        // Terminé quand round 10 sort du pipeline
        if (round_ctr_reg > AES128_ROUNDS && stage_mix_valid) begin
          ready_reg <= 1'b1;
          busy_reg  <= 1'b0;
          stage_sbox_valid  <= 1'b0;
          stage_shift_valid <= 1'b0;
          stage_mix_valid   <= 1'b0;
        end
      end
    end
  end

  //----------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------
  assign new_block = stage_mix_reg;
  assign ready     = ready_reg;
  assign round     = round_ctr_reg;
  assign sboxw     = 32'h0;  // Unused avec S-boxes parallèles

endmodule