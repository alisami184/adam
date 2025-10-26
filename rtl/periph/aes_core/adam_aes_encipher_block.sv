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
  localparam AES256_ROUNDS = 4'he;

  //----------------------------------------------------------------
  // States
  //----------------------------------------------------------------
  typedef enum logic [1:0] {
    IDLE       = 2'h0,
    PROCESSING = 2'h1,
    DONE       = 2'h2
  } state_t;

  state_t state_reg, state_new;

  //----------------------------------------------------------------
  // Pipeline registers (3 stages)
  //----------------------------------------------------------------
  logic [127:0] stage_sbox_reg;      // Après SubBytes
  logic [127:0] stage_shift_reg;     // Après ShiftRows  
  logic [127:0] stage_mix_reg;       // Après MixColumns
  
  logic [3:0]   round_ctr_reg;
  logic [3:0]   num_rounds;
  logic         ready_reg;

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
  // Datapath combinatoire
  //----------------------------------------------------------------
  logic [127:0] init_block;
  logic [127:0] next_sbox, next_shift, next_mix;
  logic [127:0] final_result;

  // AddRoundKey initial
  assign init_block = block ^ round_key;

  // Stage 1: SubBytes input
  assign sbox_input = (state_reg == IDLE) ? init_block : 
                      (round_ctr_reg == 1) ? init_block : stage_mix_reg;

  // Stage 2: ShiftRows
  assign next_shift = shiftrows(stage_sbox_reg);

  // Stage 3: MixColumns + AddRoundKey (ou juste AddRoundKey pour round final)
  assign next_mix = (round_ctr_reg >= num_rounds) ? 
                    (stage_shift_reg ^ round_key) :
                    (mixcolumns(stage_shift_reg) ^ round_key);

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_reg       <= IDLE;
      stage_sbox_reg  <= 128'h0;
      stage_shift_reg <= 128'h0;
      stage_mix_reg   <= 128'h0;
      round_ctr_reg   <= 4'h0;
      ready_reg       <= 1'b1;
    end else begin
      case (state_reg)
        IDLE: begin
          if (next) begin
            state_reg      <= PROCESSING;
            round_ctr_reg  <= 4'h1;
            ready_reg      <= 1'b0;
            // Premier round : charge init_block dans pipeline
            stage_sbox_reg <= subbytes_result;
          end
        end

        PROCESSING: begin
          // Pipeline avance chaque cycle
          stage_sbox_reg  <= subbytes_result;
          stage_shift_reg <= next_shift;
          stage_mix_reg   <= next_mix;
          
          // Incrément compteur
          if (round_ctr_reg <= num_rounds) begin
            round_ctr_reg <= round_ctr_reg + 1;
          end

          // Terminé après que le dernier round sorte du pipeline
          if (round_ctr_reg > num_rounds + 2) begin
            state_reg <= DONE;
            ready_reg <= 1'b1;
          end
        end

        DONE: begin
          state_reg <= IDLE;
        end

        default: state_reg <= IDLE;
      endcase
    end
  end

  //----------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------
  assign num_rounds = (keylen == AES_256_BIT_KEY) ? AES256_ROUNDS : AES128_ROUNDS;
  assign new_block  = stage_mix_reg;
  assign ready      = ready_reg;
  assign round      = round_ctr_reg;
  assign sboxw      = 32'h0;  // Unused

endmodule