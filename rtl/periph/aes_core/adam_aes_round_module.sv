//======================================================================
// adam_aes_round_module.sv
// --------------------
// Un round AES complet : SubBytes + ShiftRows + MixColumns + AddRoundKey
// Conçu pour être instancié 10 fois dans une architecture fully pipelined
//
// Ce module est PUREMENT COMBINATOIRE (pas de registres)
// Les registres de pipeline sont dans le module parent
//======================================================================

module adam_aes_round_module #(
    parameter IS_FINAL_ROUND = 0  // 1 pour round 10 (pas de MixColumns)
)(
    input  logic [127:0] state_in,
    input  logic [127:0] round_key,
    output logic [127:0] state_out
);

  //----------------------------------------------------------------
  // Internal signals
  //----------------------------------------------------------------
  logic [127:0] subbytes_out;
  logic [127:0] shiftrows_out;
  logic [127:0] mixcolumns_out;
  
  //----------------------------------------------------------------
  // SubBytes: 16 S-Boxes parallèles (combinatoire)
  //----------------------------------------------------------------
  logic [7:0] sbox_in [0:15];
  logic [7:0] sbox_out [0:15];
  
  // Extract bytes from state (big-endian order)
  always_comb begin
    for (int i = 0; i < 16; i++) begin
      sbox_in[i] = state_in[(i*8) +: 8];  // Little-endian, comme l'ancien code
    end
  end
  
  // Instantiate 16 S-Boxes
  genvar i;
  generate
    for (i = 0; i < 16; i++) begin : gen_sboxes
      adam_aes_sbox_byte sbox_inst (
        .sbox_byte_in(sbox_in[i]),
        .sbox_byte_out(sbox_out[i])
      );
    end
  endgenerate
  
  // Reconstruct state after SubBytes
  always_comb begin
    for (int j = 0; j < 16; j++) begin
      subbytes_out[(j*8) +: 8] = sbox_out[j];
    end
  end
  
  //----------------------------------------------------------------
  // ShiftRows (combinatoire)
  //----------------------------------------------------------------
  function automatic [127:0] shiftrows(input [127:0] data);
    logic [31:0] w0, w1, w2, w3;
    logic [31:0] ws0, ws1, ws2, ws3;
    begin
      // Extract columns
      w0 = data[127:96];
      w1 = data[95:64];
      w2 = data[63:32];
      w3 = data[31:0];
      
      // Shift rows:
      // Row 0: no shift
      // Row 1: shift left by 1
      // Row 2: shift left by 2
      // Row 3: shift left by 3
      ws0 = {w0[31:24], w1[23:16], w2[15:8],  w3[7:0]};
      ws1 = {w1[31:24], w2[23:16], w3[15:8],  w0[7:0]};
      ws2 = {w2[31:24], w3[23:16], w0[15:8],  w1[7:0]};
      ws3 = {w3[31:24], w0[23:16], w1[15:8],  w2[7:0]};
      
      shiftrows = {ws0, ws1, ws2, ws3};
    end
  endfunction
  
  assign shiftrows_out = shiftrows(subbytes_out);
  
  //----------------------------------------------------------------
  // MixColumns (combinatoire, sauf dernier round)
  //----------------------------------------------------------------
  
  // Galois Field multiplication by 2
  function automatic [7:0] gm2(input [7:0] op);
    begin
      gm2 = {op[6:0], 1'b0} ^ (8'h1b & {8{op[7]}});
    end
  endfunction
  
  // Galois Field multiplication by 3
  function automatic [7:0] gm3(input [7:0] op);
    begin
      gm3 = gm2(op) ^ op;
    end
  endfunction
  
  // Mix a single column (word)
  function automatic [31:0] mixw(input [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    logic [7:0] mb0, mb1, mb2, mb3;
    begin
      b0 = w[31:24];
      b1 = w[23:16];
      b2 = w[15:8];
      b3 = w[7:0];
      
      // MixColumns matrix multiplication
      mb0 = gm2(b0) ^ gm3(b1) ^ b2      ^ b3;
      mb1 = b0      ^ gm2(b1) ^ gm3(b2) ^ b3;
      mb2 = b0      ^ b1      ^ gm2(b2) ^ gm3(b3);
      mb3 = gm3(b0) ^ b1      ^ b2      ^ gm2(b3);
      
      mixw = {mb0, mb1, mb2, mb3};
    end
  endfunction
  
  // MixColumns on all 4 columns
  function automatic [127:0] mixcolumns(input [127:0] data);
    logic [31:0] w0, w1, w2, w3;
    begin
      w0 = data[127:96];
      w1 = data[95:64];
      w2 = data[63:32];
      w3 = data[31:0];
      
      mixcolumns = {mixw(w0), mixw(w1), mixw(w2), mixw(w3)};
    end
  endfunction
  
  // Conditional MixColumns (skip for final round)
  generate
    if (IS_FINAL_ROUND) begin : gen_no_mixcol
      assign mixcolumns_out = shiftrows_out;
    end else begin : gen_mixcol
      assign mixcolumns_out = mixcolumns(shiftrows_out);
    end
  endgenerate
  
  //----------------------------------------------------------------
  // AddRoundKey (combinatoire)
  //----------------------------------------------------------------
  assign state_out = mixcolumns_out ^ round_key;

endmodule

//======================================================================
// EOF adam_aes_round_module.sv
//======================================================================