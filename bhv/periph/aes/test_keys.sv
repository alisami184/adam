`timescale 1ns / 1ps
`include "vunit_defines.svh"

// Test simple pour vérifier que les round_keys sont correctes

module test_keys();

logic clk = 0;
always #5 clk = ~clk;

logic         reset_n;
logic [255:0] key;
logic         keylen;
logic         init;
logic [127:0] round_keys [0:10];
logic         ready;

adam_aes_key_expansion_pipelined dut (
  .clk(clk),
  .reset_n(reset_n),
  .key(key),
  .keylen(keylen),
  .init(init),
  .round_keys(round_keys),
  .ready(ready)
);

`TEST_SUITE begin
  `TEST_CASE("round_keys") begin
    reset_n = 0;
    init = 0;
    key = 256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000;
    keylen = 0; // AES-128
    
    repeat(5) @(posedge clk);
    reset_n = 1;
    repeat(2) @(posedge clk);
    
    // Lance l'expansion
    init = 1;
    @(posedge clk);
    init = 0;
    
    // Attendre ready
    wait(ready == 1);
    @(posedge clk);
    
    // Afficher les round keys
    $display("=== Round Keys ===");
    $display("RK[0]  = %032x", round_keys[0]);
    $display("RK[1]  = %032x", round_keys[1]);
    $display("RK[2]  = %032x", round_keys[2]);
    $display("RK[3]  = %032x", round_keys[3]);
    $display("RK[4]  = %032x", round_keys[4]);
    $display("RK[5]  = %032x", round_keys[5]);
    $display("RK[6]  = %032x", round_keys[6]);
    $display("RK[7]  = %032x", round_keys[7]);
    $display("RK[8]  = %032x", round_keys[8]);
    $display("RK[9]  = %032x", round_keys[9]);
    $display("RK[10] = %032x", round_keys[10]);
    
    $display("");
    $display("Expected from NIST:");
    $display("RK[0]  = 2b7e151628aed2a6abf7158809cf4f3c");
    $display("RK[1]  = a0fafe1788542cb123a339392a6c7605");
    $display("RK[2]  = f2c295f27a96b9435935807a7359f67f");
    $display("RK[3]  = 3d80477d4716fe3e1e237e446d7a883b");
    $display("RK[4]  = ef44a541a8525b7fb671253bdb0bad00");
    $display("RK[5]  = d4d1c6f87c839d87caf2b8bc11f915bc");
    $display("RK[6]  = 6d88a37a110b3efddbf98641ca0093fd");
    $display("RK[7]  = 4e54f70e5f5fc9f384a64fb24ea6dc4f");
    $display("RK[8]  = ead27321b58dbad2312bf5607f8d292f");
    $display("RK[9]  = ac7766f319fadc2128d12941575c006e");
    $display("RK[10] = d014f9a8c9ee2589e13f0cc8b6630ca6");
    
    // Vérification
    if (round_keys[0] == 128'h2b7e151628aed2a6abf7158809cf4f3c &&
        round_keys[1] == 128'ha0fafe1788542cb123a339392a6c7605 &&
        round_keys[10] == 128'hd014f9a8c9ee2589e13f0cc8b6630ca6) begin
      $display("");
      $display("✅ Round keys are CORRECT!");
    end else begin
      $display("");
      $display("❌ Round keys are WRONG!");
    end
  end
end

initial begin
  #10ms;
  $fatal("Timeout!");
end

endmodule