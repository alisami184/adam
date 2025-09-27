`timescale 1ns / 1ps
`include "adam/macros_bhv.svh"
`include "apb/assign.svh"
`include "vunit_defines.svh"
//======================================================================
//
// adam_aes_tb.v - Version avec polling status
//======================================================================

`default_nettype none

module adam_aes_tb();

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  parameter DEBUG     = 0;

  parameter CLK_HALF_PERIOD = 1;
  parameter CLK_PERIOD      = 2 * CLK_HALF_PERIOD;

  // The DUT address map.
  parameter ADDR_NAME0       = 8'h00;
  parameter ADDR_NAME1       = 8'h01;
  parameter ADDR_VERSION     = 8'h02;

  parameter ADDR_CTRL        = 8'h08;
  parameter CTRL_START_BIT   = 0;

  parameter CTRL_ENCDEC_BIT  = 2;
  parameter CTRL_KEYLEN_BIT  = 3;

  parameter ADDR_STATUS      = 8'h09;
  parameter STATUS_READY_BIT = 0;
  parameter STATUS_VALID_BIT = 1;

  parameter ADDR_CONFIG      = 8'h0a;

  parameter ADDR_KEY0        = 8'h10;
  parameter ADDR_KEY1        = 8'h11;
  parameter ADDR_KEY2        = 8'h12;
  parameter ADDR_KEY3        = 8'h13;
  parameter ADDR_KEY4        = 8'h14;
  parameter ADDR_KEY5        = 8'h15;
  parameter ADDR_KEY6        = 8'h16;
  parameter ADDR_KEY7        = 8'h17;

  parameter ADDR_BLOCK0      = 8'h20;
  parameter ADDR_BLOCK1      = 8'h21;
  parameter ADDR_BLOCK2      = 8'h22;
  parameter ADDR_BLOCK3      = 8'h23;

  parameter ADDR_RESULT0     = 8'h30;
  parameter ADDR_RESULT1     = 8'h31;
  parameter ADDR_RESULT2     = 8'h32;
  parameter ADDR_RESULT3     = 8'h33;

  parameter AES_128_BIT_KEY = 0;
  parameter AES_256_BIT_KEY = 1;

  parameter AES_DECIPHER = 1'b0;
  parameter AES_ENCIPHER = 1'b1;

  // Timeout pour éviter les boucles infinies
  parameter MAX_POLL_CYCLES = 10000;

  //----------------------------------------------------------------
  // Register and Wire declarations.
  //----------------------------------------------------------------
  logic [31 : 0]  cycle_ctr;
  logic [31 : 0]  error_ctr;
  logic [31 : 0]  tc_ctr;

  logic [31 : 0]  read_data;
  logic [127 : 0] result_data;

  logic           tb_clk;
  logic           tb_reset_n;
  logic           tb_cs;
  logic           tb_we;
  logic [7  : 0]  tb_address;
  logic [31 : 0]  tb_write_data;
  logic [31 : 0] tb_read_data;

  //----------------------------------------------------------------
  // Device Under Test.
  //----------------------------------------------------------------
  adam_aes_top dut(
           .clk(tb_clk),
           .reset_n(tb_reset_n),
           .cs(tb_cs),
           .we(tb_we),
           .address(tb_address),
           .write_data(tb_write_data),
           .read_data(tb_read_data)
          );

  //----------------------------------------------------------------
  // clk_gen
  //----------------------------------------------------------------
  always
    begin : clk_gen
      #CLK_HALF_PERIOD;
      tb_clk = !tb_clk;
    end // clk_gen

  //----------------------------------------------------------------
  // sys_monitor()
  //----------------------------------------------------------------
  always
    begin : sys_monitor
      cycle_ctr = cycle_ctr + 1;
      #(CLK_PERIOD);
      if (DEBUG)
        begin
          dump_dut_state();
        end
    end

  //----------------------------------------------------------------
  // dump_dut_state()
  //----------------------------------------------------------------
  task dump_dut_state;
    begin
      $display("cycle: 0x%016x", cycle_ctr);
      $display("State of DUT");
      $display("------------");
      $display("config_reg: encdec = 0x%01x, length = 0x%01x ", dut.encdec_reg, dut.keylen_reg);
      $display("status: ready = %b, valid = %b", dut.ready_reg, dut.valid_reg);
      $display("block: 0x%08x, 0x%08x, 0x%08x, 0x%08x",
               dut.block_reg[0], dut.block_reg[1], dut.block_reg[2], dut.block_reg[3]);
      $display("");
    end
  endtask // dump_dut_state

  //----------------------------------------------------------------
  // reset_dut()
  //----------------------------------------------------------------
  task reset_dut;
    begin
      $display("*** Toggle reset.");
      tb_reset_n = 0;
      #(2 * CLK_PERIOD);
      tb_reset_n = 1;
      $display("");
    end
  endtask // reset_dut

  //----------------------------------------------------------------
  // display_test_results()
  //----------------------------------------------------------------
  task display_test_results;
    begin
      if (error_ctr == 0)
        begin
          $display("*** All %02d test cases completed successfully", tc_ctr);
        end
      else
        begin
          $display("*** %02d tests completed - %02d test cases did not complete successfully.",
                   tc_ctr, error_ctr);
        end
    end
  endtask // display_test_results

  //----------------------------------------------------------------
  // init_sim()
  //----------------------------------------------------------------
  task init_sim;
    begin
      cycle_ctr     = 0;
      error_ctr     = 0;
      tc_ctr        = 0;

      tb_clk        = 0;
      tb_reset_n    = 1;

      tb_cs         = 0;
      tb_we         = 0;
      tb_address    = 8'h0;
      tb_write_data = 32'h0;
    end
  endtask // init_sim

  //----------------------------------------------------------------
  // write_word()
  //----------------------------------------------------------------
  task write_word(input [11 : 0] address,
                  input [31 : 0] word);
    begin
      if (DEBUG)
        begin
          $display("*** Writing 0x%08x to 0x%02x.", word, address);
          $display("");
        end

      tb_address = address;
      tb_write_data = word;
      tb_cs = 1;
      tb_we = 1;
      #(2 * CLK_PERIOD);
      tb_cs = 0;
      tb_we = 0;
    end
  endtask // write_word

  //----------------------------------------------------------------
  // write_block()
  //----------------------------------------------------------------
  task write_block(input [127 : 0] block);
    begin
      write_word(ADDR_BLOCK0, block[127  :  96]);
      write_word(ADDR_BLOCK1, block[95   :  64]);
      write_word(ADDR_BLOCK2, block[63   :  32]);
      write_word(ADDR_BLOCK3, block[31   :   0]);
    end
  endtask // write_block

  //----------------------------------------------------------------
  // read_word()
  //----------------------------------------------------------------
  task read_word(input [11 : 0]  address);
    begin
      tb_address = address;
      tb_cs = 1;
      tb_we = 0;
      #(CLK_PERIOD);
      read_data = tb_read_data;
      tb_cs = 0;

      if (DEBUG)
        begin
          $display("*** Reading 0x%08x from 0x%02x.", read_data, address);
          $display("");
        end
    end
  endtask // read_word

  //----------------------------------------------------------------
  // read_result()
  //----------------------------------------------------------------
  task read_result;
    begin
      read_word(ADDR_RESULT0);
      result_data[127 : 096] = read_data;
      read_word(ADDR_RESULT1);
      result_data[095 : 064] = read_data;
      read_word(ADDR_RESULT2);
      result_data[063 : 032] = read_data;
      read_word(ADDR_RESULT3);
      result_data[031 : 000] = read_data;
    end
  endtask // read_result

  //----------------------------------------------------------------
  // NOUVEAU: poll_for_ready() - Attendre que ready = 1
  //----------------------------------------------------------------
  task poll_for_ready();
    logic [31:0] status;
    logic ready_bit;
    integer poll_count;
    begin
      poll_count = 0;
      ready_bit = 0;
      
      $display("[%0t] Polling for READY bit...", $time);
      
      while (!ready_bit && poll_count < MAX_POLL_CYCLES) begin
        read_word(ADDR_STATUS);
        status = read_data;
        ready_bit = status[STATUS_READY_BIT];
        
        if (DEBUG && (poll_count % 100 == 0))
          $display("[%0t] Poll %0d: STATUS=0x%08x, ready=%b", 
                   $time, poll_count, status, ready_bit);
        
        poll_count = poll_count + 1;
        #(CLK_PERIOD);
      end
      
      if (!ready_bit) begin
        $display("*** ERROR: Timeout waiting for READY bit after %0d cycles", poll_count);
        error_ctr = error_ctr + 1;
      end else begin
        $display("[%0t] READY detected after %0d poll cycles", $time, poll_count);
      end
    end
  endtask

  //----------------------------------------------------------------
  // NOUVEAU: poll_for_valid() - Attendre que result_valid = 1
  //----------------------------------------------------------------
  task poll_for_valid();
    logic [31:0] status;
    logic valid_bit;
    integer poll_count;
    begin
      poll_count = 0;
      valid_bit = 0;
      
      $display("[%0t] Polling for VALID bit...", $time);
      
      while (!valid_bit && poll_count < MAX_POLL_CYCLES) begin
        read_word(ADDR_STATUS);
        status = read_data;
        valid_bit = status[STATUS_VALID_BIT];
        
        if (DEBUG && (poll_count % 100 == 0))
          $display("[%0t] Poll %0d: STATUS=0x%08x, valid=%b", 
                   $time, poll_count, status, valid_bit);
        
        poll_count = poll_count + 1;
        #(CLK_PERIOD);
      end
      
      if (!valid_bit) begin
        $display("*** ERROR: Timeout waiting for VALID bit after %0d cycles", poll_count);
        error_ctr = error_ctr + 1;
      end else begin
        $display("[%0t] VALID detected after %0d poll cycles", $time, poll_count);
      end
    end
  endtask

  //----------------------------------------------------------------
  // init_key() - Version avec polling
  //----------------------------------------------------------------
  task init_key(input [255 : 0] key, input key_length);
    begin
      if (DEBUG)
        begin
          $display("key length: 0x%01x", key_length);
          $display("Initializing key expansion for key: 0x%016x", key);
        end

      write_word(ADDR_KEY0, key[255  : 224]);
      write_word(ADDR_KEY1, key[223  : 192]);
      write_word(ADDR_KEY2, key[191  : 160]);
      write_word(ADDR_KEY3, key[159  : 128]);
      write_word(ADDR_KEY4, key[127  :  96]);
      write_word(ADDR_KEY5, key[95   :  64]);
      write_word(ADDR_KEY6, key[63   :  32]);
      write_word(ADDR_KEY7, key[31   :   0]);

      if (key_length)
        begin
          write_word(ADDR_CONFIG, 8'h02);
        end
      else
        begin
          write_word(ADDR_CONFIG, 8'h00);
        end
    end
  endtask

  //----------------------------------------------------------------
  // MODIFIÉ: ecb_mode_single_block_test() avec polling
  //----------------------------------------------------------------
  task ecb_mode_single_block_test(input [7 : 0]   tc_number,
                                  input           encdec,
                                  input [255 : 0] key,
                                  input           key_length,
                                  input [127 : 0] block,
                                  input [127 : 0] expected);
    begin
      $display("");
      $display("*** TC %0d ECB mode test started.", tc_number);
      $display("    Mode: %s, Key length: %0d bits", 
               encdec ? "ENCRYPT" : "DECRYPT", 
               key_length ? 256 : 128);
      tc_ctr = tc_ctr + 1;

      // 1. Attendre que le core soit prêt
      poll_for_ready();

      // 2. Configurer la clé et les paramètres
      init_key(key, key_length);
      write_block(block);
      write_word(ADDR_CONFIG, (8'h00 + (key_length << 1) + encdec));

      // 3. Démarrer l'opération
      $display("[%0t] Starting AES operation...", $time);
      write_word(ADDR_CTRL, 32'h1 << CTRL_START_BIT);

      // 4. Attendre que les résultats soient valides
      poll_for_valid();

      // 5. Lire les résultats
      read_result();

      // 6. Vérifier
      if (result_data == expected)
        begin
          $display("*** TC %0d SUCCESSFUL.", tc_number);
          $display("    Result: 0x%032x", result_data);
        end
      else
        begin
          $display("*** ERROR: TC %0d FAILED.", tc_number);
          $display("    Expected: 0x%032x", expected);
          $display("    Got:      0x%032x", result_data);
          error_ctr = error_ctr + 1;
        end
    end
  endtask // ecb_mode_single_block_test

  //----------------------------------------------------------------
  // aes_test() - Inchangé
  //----------------------------------------------------------------
  task aes_test;
    logic [255 : 0] nist_aes128_key1;
    logic [255 : 0] nist_aes128_key2;
    logic [255 : 0] nist_aes256_key1;
    logic [255 : 0] nist_aes256_key2;

    logic [127 : 0] nist_plaintext0;
    logic [127 : 0] nist_plaintext1;
    logic [127 : 0] nist_plaintext2;
    logic [127 : 0] nist_plaintext3;
    logic [127 : 0] nist_plaintext4;

    logic [127 : 0] nist_ecb_128_enc_expected0;
    logic [127 : 0] nist_ecb_128_enc_expected1;
    logic [127 : 0] nist_ecb_128_enc_expected2;
    logic [127 : 0] nist_ecb_128_enc_expected3;
    logic [127 : 0] nist_ecb_128_enc_expected4;

    logic [127 : 0] nist_ecb_256_enc_expected0;
    logic [127 : 0] nist_ecb_256_enc_expected1;
    logic [127 : 0] nist_ecb_256_enc_expected2;
    logic [127 : 0] nist_ecb_256_enc_expected3;
    logic [127 : 0] nist_ecb_256_enc_expected4;

    begin
      nist_aes128_key1 = 256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000;
      nist_aes128_key2 = 256'h000102030405060708090a0b0c0d0e0f00000000000000000000000000000000;
      nist_aes256_key1 = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
      nist_aes256_key2 = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;

      nist_plaintext0 = 128'h6bc1bee22e409f96e93d7e117393172a;
      nist_plaintext1 = 128'hae2d8a571e03ac9c9eb76fac45af8e51;
      nist_plaintext2 = 128'h30c81c46a35ce411e5fbc1191a0a52ef;
      nist_plaintext3 = 128'hf69f2445df4f9b17ad2b417be66c3710;
      nist_plaintext4 = 128'h00112233445566778899aabbccddeeff;

      nist_ecb_128_enc_expected0 = 128'h3ad77bb40d7a3660a89ecaf32466ef97;
      nist_ecb_128_enc_expected1 = 128'hf5d3d58503b9699de785895a96fdbaaf;
      nist_ecb_128_enc_expected2 = 128'h43b1cd7f598ece23881b00e3ed030688;
      nist_ecb_128_enc_expected3 = 128'h7b0c785e27e8ad3f8223207104725dd4;
      nist_ecb_128_enc_expected4 = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;

      nist_ecb_256_enc_expected0 = 128'hf3eed1bdb5d2a03c064b5a7e3db181f8;
      nist_ecb_256_enc_expected1 = 128'h591ccb10d410ed26dc5ba74a31362870;
      nist_ecb_256_enc_expected2 = 128'hb6ed21b99ca6f4f9f153e7b1beafed1d;
      nist_ecb_256_enc_expected3 = 128'h23304b7a39f9f3ff067d8d8f9e24ecc7;
      nist_ecb_256_enc_expected4 = 128'h8ea2b7ca516745bfeafc49904b496089;

      $display("ECB 128 bit key tests");
      $display("---------------------");
      ecb_mode_single_block_test(8'h01, AES_ENCIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_plaintext0, nist_ecb_128_enc_expected0);

      ecb_mode_single_block_test(8'h02, AES_ENCIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                nist_plaintext1, nist_ecb_128_enc_expected1);

      ecb_mode_single_block_test(8'h03, AES_ENCIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_plaintext2, nist_ecb_128_enc_expected2);

      ecb_mode_single_block_test(8'h04, AES_ENCIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_plaintext3, nist_ecb_128_enc_expected3);

      ecb_mode_single_block_test(8'h05, AES_DECIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_ecb_128_enc_expected0, nist_plaintext0);

      ecb_mode_single_block_test(8'h06, AES_DECIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_ecb_128_enc_expected1, nist_plaintext1);

      ecb_mode_single_block_test(8'h07, AES_DECIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_ecb_128_enc_expected2, nist_plaintext2);

      ecb_mode_single_block_test(8'h08, AES_DECIPHER, nist_aes128_key1, AES_128_BIT_KEY,
                                 nist_ecb_128_enc_expected3, nist_plaintext3);

      ecb_mode_single_block_test(8'h09, AES_ENCIPHER, nist_aes128_key2, AES_128_BIT_KEY,
                                 nist_plaintext4, nist_ecb_128_enc_expected4);

      ecb_mode_single_block_test(8'h0a, AES_DECIPHER, nist_aes128_key2, AES_128_BIT_KEY,
                                 nist_ecb_128_enc_expected4, nist_plaintext4);

      $display("");
      $display("ECB 256 bit key tests");
      $display("---------------------");
      ecb_mode_single_block_test(8'h10, AES_ENCIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_plaintext0, nist_ecb_256_enc_expected0);

      ecb_mode_single_block_test(8'h11, AES_ENCIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_plaintext1, nist_ecb_256_enc_expected1);

      ecb_mode_single_block_test(8'h12, AES_ENCIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_plaintext2, nist_ecb_256_enc_expected2);

      ecb_mode_single_block_test(8'h13, AES_ENCIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_plaintext3, nist_ecb_256_enc_expected3);

      ecb_mode_single_block_test(8'h14, AES_DECIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_ecb_256_enc_expected0, nist_plaintext0);

      ecb_mode_single_block_test(8'h15, AES_DECIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_ecb_256_enc_expected1, nist_plaintext1);

      ecb_mode_single_block_test(8'h16, AES_DECIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_ecb_256_enc_expected2, nist_plaintext2);

      ecb_mode_single_block_test(8'h17, AES_DECIPHER, nist_aes256_key1, AES_256_BIT_KEY,
                                 nist_ecb_256_enc_expected3, nist_plaintext3);

      ecb_mode_single_block_test(8'h18, AES_ENCIPHER, nist_aes256_key2, AES_256_BIT_KEY,
                                 nist_plaintext4, nist_ecb_256_enc_expected4);

      ecb_mode_single_block_test(8'h19, AES_DECIPHER, nist_aes256_key2, AES_256_BIT_KEY,
                                 nist_ecb_256_enc_expected4, nist_plaintext4);
    end
  endtask // aes_test

  //----------------------------------------------------------------
  // main
  //----------------------------------------------------------------
  `TEST_SUITE begin
    `TEST_CASE("aes") begin
          $display("   -= Testbench for AES started (with status polling) =-");
          $display("    =====================================================");
          $display("");

          init_sim();
          dump_dut_state();
          reset_dut();
          dump_dut_state();

          aes_test();

          display_test_results();

          $display("");
          $display("*** AES simulation done. ***");
    end
  end

  //----------------------------------------------------------------
  // Timeout
  //----------------------------------------------------------------
  initial begin
    #100us $fatal("Timeout in aes_tb");
  end

endmodule

//======================================================================
// EOF adam_aes_tb.sv
//======================================================================