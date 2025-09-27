`timescale 1ns/1ps
`include "adam/macros_bhv.svh"
`include "apb/assign.svh"
`include "vunit_defines.svh"

module adam_aes_key_expansion_tb();

  //----------------------------------------------------------------
  // Parameters
  //----------------------------------------------------------------
  parameter DEBUG = 1;
  parameter SHOW_SBOX = 0;

  parameter CLK_HALF_PERIOD = 1;
  parameter CLK_PERIOD      = 2 * CLK_HALF_PERIOD;

  parameter AES_128_BIT_KEY    = 0;
  parameter AES_256_BIT_KEY    = 1;
  parameter AES_128_NUM_ROUNDS = 10;
  parameter AES_256_NUM_ROUNDS = 14;

  //----------------------------------------------------------------
  // Signals
  //----------------------------------------------------------------
  logic [31 : 0] cycle_ctr;
  logic [31 : 0] error_ctr;
  logic [31 : 0] tc_ctr;

  logic          tb_clk;
  logic          tb_reset_n;
  logic [255:0]  tb_key;
  logic          tb_keylen;
  logic          tb_init;
  logic [3:0]    tb_round;
  logic [127:0]  tb_round_key;
  logic          tb_ready;

  logic [31:0]   tb_sboxw;
  logic [31:0]   tb_new_sboxw;

  //----------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------
  aes_key_expansion dut (
    .clk      (tb_clk),
    .reset_n  (tb_reset_n),
    .key      (tb_key),
    .keylen   (tb_keylen),
    .init     (tb_init),
    .round    (tb_round),
    .round_key(tb_round_key),
    .ready    (tb_ready),
    .sboxw    (tb_sboxw),
    .new_sboxw(tb_new_sboxw)
  );

  aes_sbox sbox (
    .sboxw    (tb_sboxw),
    .new_sboxw(tb_new_sboxw)
  );

  //----------------------------------------------------------------
  // Clock
  //----------------------------------------------------------------
  always #CLK_HALF_PERIOD tb_clk = !tb_clk;

  //----------------------------------------------------------------
  // Monitor
  //----------------------------------------------------------------
  always begin
    cycle_ctr = cycle_ctr + 1;
    #(CLK_PERIOD);
    if (DEBUG) dump_dut_state();
  end

  //----------------------------------------------------------------
  // dump_dut_state()
  //
  // Dump the state of the dump when needed.
  //----------------------------------------------------------------
  task dump_dut_state;
    begin
      $display("State of DUT");
      $display("------------");
      $display("Inputs and outputs:");
      $display("key       = 0x%032x", dut.key);
      $display("keylen    = 0x%01x, init = 0x%01x, ready = 0x%01x",
               dut.keylen, dut.init, dut.ready);
      $display("round     = 0x%02x", dut.round);
      $display("round_key = 0x%016x", dut.round_key);
      $display("");

      $display("Internal states:");
      $display("key_mem_ctrl = 0x%01x, round_key_update = 0x%01x, round_ctr_reg = 0x%01x",
               dut.key_mem_ctrl_reg, dut.round_key_update, dut.round_ctr_reg);

      $display("prev_key0_reg = 0x%016x, prev_key0_new = 0x%016x, prev_key0_we = 0x%01x",
               dut.prev_key0_reg, dut.prev_key0_new, dut.prev_key0_we);
      $display("prev_key1_reg = 0x%016x, prev_key1_new = 0x%016x, prev_key1_we = 0x%01x",
               dut.prev_key1_reg, dut.prev_key1_new, dut.prev_key1_we);

      $display("rcon_reg = 0x%01x, rcon_new = 0x%01x,  rcon_set = 0x%01x,  rcon_next = 0x%01x, rcon_we = 0x%01x",
               dut.rcon_reg, dut.rcon_new, dut.rcon_set, dut.rcon_next, dut.rcon_we);

      $display("w0 = 0x%04x, w1 = 0x%04x, w2 = 0x%04x, w3 = 0x%04x",
               dut.round_key_gen.w0, dut.round_key_gen.w1,
               dut.round_key_gen.w2, dut.round_key_gen.w3);
      $display("w4 = 0x%04x, w5 = 0x%04x, w6 = 0x%04x, w7 = 0x%04x",
               dut.round_key_gen.w4, dut.round_key_gen.w5,
               dut.round_key_gen.w6, dut.round_key_gen.w7);
      $display("sboxw = 0x%04x, new_sboxw = 0x%04x, rconw = 0x%04x",
               dut.sboxw, dut.new_sboxw, dut.round_key_gen.rconw);
      $display("tw = 0x%04x, trw = 0x%04x", dut.round_key_gen.tw, dut.round_key_gen.trw);
      $display("key_mem_new = 0x%016x, key_mem_we = 0x%01x",
               dut.key_mem_new, dut.key_mem_we);
      $display("");

      /*if (SHOW_SBOX)
        begin
          $display("Sbox functionality:");
          $display("sboxw = 0x%08x", sbox.sboxw);
          $display("tmp_new_sbox0 = 0x%02x, tmp_new_sbox1 = 0x%02x, tmp_new_sbox2 = 0x%02x, tmp_new_sbox3",
                   sbox.tmp_new_sbox0, sbox.tmp_new_sbox1, sbox.tmp_new_sbox2, sbox.tmp_new_sbox3);
          $display("new_sboxw = 0x%08x", sbox.new_sboxw);
          $display("");
        end*/
    end
  endtask // dump_dut_state


  //----------------------------------------------------------------
  // reset_dut()
  //
  // Toggle reset to put the DUT into a well known state.
  //----------------------------------------------------------------
  task reset_dut;
    begin
      $display("*** Toggle reset.");
      tb_reset_n = 0;
      #(2 * CLK_PERIOD);
      tb_reset_n = 1;
    end
  endtask // reset_dut


  //----------------------------------------------------------------
  // init_sim()
  //
  // Initialize all counters and testbed functionality as well
  // as setting the DUT inputs to defined values.
  //----------------------------------------------------------------
  task init_sim;
    begin
      cycle_ctr = 0;
      error_ctr = 0;
      tc_ctr    = 0;

      tb_clk     = 0;
      tb_reset_n = 1;
      tb_key     = {8{32'h00000000}};
      tb_keylen  = 0;
      tb_init    = 0;
      tb_round   = 4'h0;
    end
  endtask // init_sim


  //----------------------------------------------------------------
  // wait_ready()
  //
  // Wait for the ready flag in the dut to be set.
  //
  // Note: It is the callers responsibility to call the function
  // when the dut is actively processing and will in fact at some
  // point set the flag.
  //----------------------------------------------------------------
  task wait_ready;
    begin
      while (!tb_ready)
        begin
          #(CLK_PERIOD);
        end
    end
  endtask // wait_ready


  //----------------------------------------------------------------
  // check_key()
  //
  // Check a given key in the dut key memory against a given
  // expected key.
  //----------------------------------------------------------------
  task check_key(input [3 : 0] key_nr, input [127 : 0] expected);
    begin
      tb_round = key_nr;
      #(CLK_PERIOD);
      if (tb_round_key == expected)
        begin
          $display("** key 0x%01x matched expected round key.", key_nr);
          $display("** Got:      0x%016x **", tb_round_key);
        end
      else
        begin
          $display("** Error: key 0x%01x did not match expected round key. **", key_nr);
          $display("** Expected: 0x%016x **", expected);
          $display("** Got:      0x%016x **", tb_round_key);
          error_ctr = error_ctr + 1;
        end
      $display("");
    end
  endtask // check_key


  //----------------------------------------------------------------
  // test_key_128()
  //
  // Test 128 bit keys. Due to array problems, the result check
  // is fairly ugly.
  //----------------------------------------------------------------
  task test_key_128(input [255 : 0] key,
                    input [127 : 0] expected00,
                    input [127 : 0] expected01,
                    input [127 : 0] expected02,
                    input [127 : 0] expected03,
                    input [127 : 0] expected04,
                    input [127 : 0] expected05,
                    input [127 : 0] expected06,
                    input [127 : 0] expected07,
                    input [127 : 0] expected08,
                    input [127 : 0] expected09,
                    input [127 : 0] expected10
                   );
    begin
      $display("** Testing with 128-bit key 0x%16x", key[255 : 128]);
      $display("");

      tb_key = key;
      tb_keylen = AES_128_BIT_KEY;
      tb_init = 1;
      #(2 * CLK_PERIOD);
      tb_init = 0;
      wait_ready();

      check_key(4'h0, expected00);
      check_key(4'h1, expected01);
      check_key(4'h2, expected02);
      check_key(4'h3, expected03);
      check_key(4'h4, expected04);
      check_key(4'h5, expected05);
      check_key(4'h6, expected06);
      check_key(4'h7, expected07);
      check_key(4'h8, expected08);
      check_key(4'h9, expected09);
      check_key(4'ha, expected10);

      tc_ctr = tc_ctr + 1;
    end
  endtask // test_key_128


  //----------------------------------------------------------------
  // test_key_256()
  //
  // Test 256 bit keys. Due to array problems, the result check
  // is fairly ugly.
  //----------------------------------------------------------------
  task test_key_256(input [255 : 0] key,
                    input [127 : 0] expected00,
                    input [127 : 0] expected01,
                    input [127 : 0] expected02,
                    input [127 : 0] expected03,
                    input [127 : 0] expected04,
                    input [127 : 0] expected05,
                    input [127 : 0] expected06,
                    input [127 : 0] expected07,
                    input [127 : 0] expected08,
                    input [127 : 0] expected09,
                    input [127 : 0] expected10,
                    input [127 : 0] expected11,
                    input [127 : 0] expected12,
                    input [127 : 0] expected13,
                    input [127 : 0] expected14
                   );
    begin
      $display("** Testing with 256-bit key 0x%32x", key[255 : 000]);
      $display("");

      tb_key = key;
      tb_keylen = AES_256_BIT_KEY;
      tb_init = 1;
      #(2 * CLK_PERIOD);
      tb_init = 0;

      wait_ready();

      check_key(4'h0, expected00);
      check_key(4'h1, expected01);
      check_key(4'h2, expected02);
      check_key(4'h3, expected03);
      check_key(4'h4, expected04);
      check_key(4'h5, expected05);
      check_key(4'h6, expected06);
      check_key(4'h7, expected07);
      check_key(4'h8, expected08);
      check_key(4'h9, expected09);
      check_key(4'ha, expected10);
      check_key(4'hb, expected11);
      check_key(4'hc, expected12);
      check_key(4'hd, expected13);
      check_key(4'he, expected14);

      tc_ctr = tc_ctr + 1;
    end
  endtask // test_key_256


  //----------------------------------------------------------------
  // display_test_result()
  //
  // Display the accumulated test results.
  //----------------------------------------------------------------
  task display_test_result;
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
  endtask // display_test_result


  //----------------------------------------------------------------
  // TEST SUITE
  //----------------------------------------------------------------
  `TEST_SUITE begin
    `TEST_CASE("aes_key_expansion_128") begin
      logic [255:0] key128;
      logic [127:0] expected_00, expected_01, expected_02,
                    expected_03, expected_04, expected_05,
                    expected_06, expected_07, expected_08,
                    expected_09, expected_10;

      init_sim();
      reset_dut();

      // AES-128
      key128      = 256'h6920e299a5202a6d656e636869746f2a00000000000000000000000000000000;
      expected_00 = 128'h6920e299a5202a6d656e636869746f2a;
      expected_01 = 128'hfa8807605fa82d0d3ac64e6553b2214f;
      expected_02 = 128'hcf75838d90ddae80aa1be0e5f9a9c1aa;
      expected_03 = 128'h180d2f1488d0819422cb6171db62a0db;
      expected_04 = 128'hbaed96ad323d173910f67648cb94d693;
      expected_05 = 128'h881b4ab2ba265d8baad02bc36144fd50;
      expected_06 = 128'hb34f195d096944d6a3b96f15c2fd9245;
      expected_07 = 128'ha7007778ae6933ae0dd05cbbcf2dcefe;
      expected_08 = 128'hff8bccf251e2ff5c5c32a3e7931f6d19;
      expected_09 = 128'h24b7182e7555e77229674495ba78298c;
      expected_10 = 128'hae127cdadb479ba8f220df3d4858f6b1;

      test_key_128(key128,
                   expected_00, expected_01, expected_02, expected_03,
                   expected_04, expected_05, expected_06, expected_07,
                   expected_08, expected_09, expected_10);

      display_test_result();
    end

    `TEST_CASE("aes_key_expansion_256") begin
      logic [255:0] key256;
      logic [127:0] expected_00, expected_01, expected_02, expected_03,
                    expected_04, expected_05, expected_06, expected_07,
                    expected_08, expected_09, expected_10, expected_11,
                    expected_12, expected_13, expected_14;

      init_sim();
      reset_dut();

      // AES-256
      key256      = 256'h603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4;
      expected_00 = 128'h603deb1015ca71be2b73aef0857d7781;
      expected_01 = 128'h1f352c073b6108d72d9810a30914dff4;
      expected_02 = 128'h9ba354118e6925afa51a8b5f2067fcde;
      expected_03 = 128'ha8b09c1a93d194cdbe49846eb75d5b9a;
      expected_04 = 128'hd59aecb85bf3c917fee94248de8ebe96;
      expected_05 = 128'hb5a9328a2678a647983122292f6c79b3;
      expected_06 = 128'h812c81addadf48ba24360af2fab8b464;
      expected_07 = 128'h98c5bfc9bebd198e268c3ba709e04214;
      expected_08 = 128'h68007bacb2df331696e939e46c518d80;
      expected_09 = 128'hc814e20476a9fb8a5025c02d59c58239;
      expected_10 = 128'hde1369676ccc5a71fa2563959674ee15;
      expected_11 = 128'h5886ca5d2e2f31d77e0af1fa27cf73c3;
      expected_12 = 128'h749c47ab18501ddae2757e4f7401905a;
      expected_13 = 128'hcafaaae3e4d59b349adf6acebd10190d;
      expected_14 = 128'hfe4890d1e6188d0b046df344706c631e;

      test_key_256(key256,
                   expected_00, expected_01, expected_02, expected_03,
                   expected_04, expected_05, expected_06, expected_07,
                   expected_08, expected_09, expected_10, expected_11,
                   expected_12, expected_13, expected_14);

      display_test_result();
    end
  end

  //----------------------------------------------------------------
  // Timeout
  //----------------------------------------------------------------
  initial begin
    #100us $fatal("Timeout in aes_key_expansion_tb");
  end

endmodule
