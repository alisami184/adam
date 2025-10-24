`timescale 1ns / 1ps
`include "vunit_defines.svh"

//======================================================================
// adam_aes_core_simple_tb.sv
// Testbench SIMPLE pour tester directement adam_aes_core_fully_pipelined
// Sans wrapper, sans AXI, juste les signaux directs du core
//======================================================================

module adam_aes_core_simple_tb();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter CLK_HALF_PERIOD = 5;
  parameter CLK_PERIOD = 2 * CLK_HALF_PERIOD;
  
  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  logic         clk;
  logic         reset_n;
  
  // Control
  logic         encdec;
  logic         start;
  logic         ready;
  logic         result_valid;
  
  // Key
  logic [255:0] key;
  logic         keylen;
  
  // Data
  logic [127:0] block;
  logic [127:0] result;
  
  // Test variables
  integer       cycle_count;
  integer       error_count;
  integer       test_count;
  
  //----------------------------------------------------------------
  // DUT - Instance du core AES
  //----------------------------------------------------------------
  adam_aes_core_fully_pipelined dut (
    .clk(clk),
    .reset_n(reset_n),
    .encdec(encdec),
    .start(start),
    .ready(ready),
    .result_valid(result_valid),
    .key(key),
    .keylen(keylen),
    .block(block),
    .result(result)
  );
  
  //----------------------------------------------------------------
  // Clock generator
  //----------------------------------------------------------------
  initial begin
    clk = 0;
    forever #CLK_HALF_PERIOD clk = ~clk;
  end
  
  //----------------------------------------------------------------
  // Cycle counter
  //----------------------------------------------------------------
  always @(posedge clk) begin
    if (reset_n)
      cycle_count <= cycle_count + 1;
    else
      cycle_count <= 0;
  end
  
  //----------------------------------------------------------------
  // Test task: Single AES encryption
  //----------------------------------------------------------------
  task test_aes_encrypt(
    input [255:0] test_key,
    input         key_128_or_256,  // 0=128-bit, 1=256-bit
    input [127:0] plaintext,
    input [127:0] expected_cipher
  );
    integer wait_cycles;
    begin
      $display("");
      $display("=== Starting AES Encryption Test ===");
      $display("Key (128-bit):  %032x", test_key[255:128]);
      $display("Plaintext:      %032x", plaintext);
      $display("Expected:       %032x", expected_cipher);
      
      test_count = test_count + 1;
      
      // 1. Attendre que ready = 1
      wait(ready == 1'b1);
      @(posedge clk);
      
      // 2. Charger key et block
      key    = test_key;
      keylen = key_128_or_256;
      block  = plaintext;
      encdec = 1'b1;  // Encrypt
      
      @(posedge clk);
      
      // 3. Pulse start
      start = 1'b1;
      @(posedge clk);
      start = 1'b0;
      
      $display("[Cycle %0d] Start signal pulsed", cycle_count);
      
      // 4. Attendre result_valid
      wait_cycles = 0;
      while (!result_valid && wait_cycles < 100) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      
      if (!result_valid) begin
        $display("❌ ERROR: Timeout waiting for result_valid!");
        error_count = error_count + 1;
        return;
      end
      
      $display("[Cycle %0d] Result valid after %0d cycles", cycle_count, wait_cycles);
      
      // 5. Lire et vérifier le résultat
      @(posedge clk);
      $display("Result:         %032x", result);
      
      if (result == expected_cipher) begin
        $display("✅ SUCCESS: Result matches expected cipher!");
      end else begin
        $display("❌ FAILURE: Result does NOT match!");
        $display("   Difference:  %032x", result ^ expected_cipher);
        error_count = error_count + 1;
      end
      
      // 6. Attendre retour à ready
      @(posedge clk);
      wait(ready == 1'b1);
      @(posedge clk);
      @(posedge clk);
    end
  endtask
  
  //----------------------------------------------------------------
  // Main test
  //----------------------------------------------------------------
  `TEST_SUITE begin
    `TEST_CASE("aes") begin
      $display("========================================");
      $display("  AES Core Simple Testbench");
      $display("========================================");
      
      // Initialize
      error_count = 0;
      test_count = 0;
      cycle_count = 0;
      
      reset_n = 0;
      start = 0;
      encdec = 1;
      key = 256'h0;
      keylen = 0;
      block = 128'h0;
      
      // Reset
      repeat(5) @(posedge clk);
      reset_n = 1;
      repeat(5) @(posedge clk);
      
      // Test 1: NIST AES-128 Test Vector
      $display("");
      $display("----------------------------------------");
      $display("TEST 1: NIST AES-128 ECB Vector");
      $display("----------------------------------------");
      test_aes_encrypt(
        .test_key(256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000),
        .key_128_or_256(1'b0),
        .plaintext(128'h6bc1bee22e409f96e93d7e117393172a),
        .expected_cipher(128'h3ad77bb40d7a3660a89ecaf32466ef97)
      );
      
      // Test 2: Deuxième vecteur
      $display("");
      $display("----------------------------------------");
      $display("TEST 2: NIST AES-128 ECB Vector #2");
      $display("----------------------------------------");
      test_aes_encrypt(
        .test_key(256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000),
        .key_128_or_256(1'b0),
        .plaintext(128'hae2d8a571e03ac9c9eb76fac45af8e51),
        .expected_cipher(128'hf5d3d58503b9699de785895a96fdbaaf)
      );
      
      // Test 3: Troisième vecteur (celui qui échoue dans ton soft)
      $display("");
      $display("----------------------------------------");
      $display("TEST 3: Software Test Vector");
      $display("----------------------------------------");
      test_aes_encrypt(
        .test_key(256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000),
        .key_128_or_256(1'b0),
        .plaintext(128'h6bc1bee22e409f96e93d7e117393172a),
        .expected_cipher(128'h3ad77bb40d7a3660a89ecaf32466ef97)
      );
      
      // Final report
      repeat(10) @(posedge clk);
      $display("");
      $display("========================================");
      $display("  TEST SUMMARY");
      $display("========================================");
      $display("Tests run:    %0d", test_count);
      $display("Tests failed: %0d", error_count);
      
      if (error_count == 0) begin
        $display("✅ ALL TESTS PASSED!");
      end else begin
        $display("❌ SOME TESTS FAILED!");
      end
      $display("========================================");
    end
  end
  
  //----------------------------------------------------------------
  // Timeout
  //----------------------------------------------------------------
  initial begin
    #10ms;
    $fatal("ERROR: Testbench timeout!");
  end

endmodule