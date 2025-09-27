`timescale 1ns/1ps
`include "adam/macros_bhv.svh"
`include "axi/assign.svh"
`include "vunit_defines.svh"

module adam_axil_aes_tb;
    import adam_axil_mst_bhv::*;

    // Configuration parameters
    `ADAM_BHV_CFG_LOCALPARAMS;
    
    localparam MAX_TRANS = 10;
    
    // AES Register addresses
    localparam ADDR_NAME0    = 32'h00;
    localparam ADDR_VERSION  = 32'h02;
    localparam ADDR_CTRL     = 32'h08;
    localparam ADDR_STATUS   = 32'h09;
    localparam ADDR_CONFIG   = 32'h0a;
    localparam ADDR_KEY0     = 32'h10;
    localparam ADDR_KEY7     = 32'h17;
    localparam ADDR_BLOCK0   = 32'h20;
    localparam ADDR_BLOCK3   = 32'h23;
    localparam ADDR_RESULT0  = 32'h30;
    localparam ADDR_RESULT3  = 32'h33;

    // AES Test vectors
    localparam [255:0] AES128_KEY = 256'h2b7e151628aed2a6abf7158809cf4f3c00000000000000000000000000000000;
    localparam [127:0] PLAINTEXT = 128'h6bc1bee22e409f96e93d7e117393172a;
    localparam [127:0] EXPECTED_CIPHER = 128'h3ad77bb40d7a3660a89ecaf32466ef97;

    // Test infrastructure
    integer test_count = 0;
    integer error_count = 0;

    //----------------------------------------------------------------
    // Framework instantiation 
    //----------------------------------------------------------------
    ADAM_SEQ seq();
    ADAM_PAUSE pause();  // AJOUT OBLIGATOIRE

    `ADAM_AXIL_I axil ();
    `ADAM_AXIL_DV_I axil_dv (seq.clk);
    `AXI_LITE_ASSIGN(axil, axil_dv);

    adam_axil_mst_bhv #(
        `ADAM_BHV_CFG_PARAMS_MAP,
        .MAX_TRANS (MAX_TRANS)
    ) mst_bhv;

    adam_seq_bhv #(
        `ADAM_BHV_CFG_PARAMS_MAP
    ) adam_seq_bhv (
        .seq(seq)
    );

    //----------------------------------------------------------------
    // DUT instantiation
    //----------------------------------------------------------------
    adam_axil_aes #(
        `ADAM_CFG_PARAMS_MAP
    ) dut (
        .seq(seq),
        .pause(pause),        
        .axil(axil.Slave)     
    );

    //----------------------------------------------------------------
    // Master BHV initialization
    //----------------------------------------------------------------
    initial begin
        mst_bhv = new(axil_dv);
        mst_bhv.loop();
    end

    //----------------------------------------------------------------
    // High-level AES test tasks
    //----------------------------------------------------------------
    
    // Task pour écriture AXI avec BHV
    task axi_write_bhv(input ADDR_T addr, input DATA_T data);
        automatic RESP_T resp;
        begin
            test_count++;
            
            // Send write address and data
            fork
                mst_bhv.send_aw(addr, 3'b000);
                mst_bhv.send_w(data, 4'b1111);
            join
            
            // Receive response
            mst_bhv.recv_b(resp);
            
            if (resp != axi_pkg::RESP_OKAY) begin
                $display("ERROR: Write to 0x%08x failed with response 0x%02x", addr, resp);
                error_count++;
            end
        end
    endtask

    // Task pour lecture AXI avec BHV
    task axi_read_bhv(input ADDR_T addr, output DATA_T data);
        automatic RESP_T resp;
        begin
            test_count++;
            
            // Send read address
            mst_bhv.send_ar(addr, 3'b000);
            
            // Receive data and response
            mst_bhv.recv_r(data, resp);
            
            if (resp != axi_pkg::RESP_OKAY) begin
                $display("ERROR: Read from 0x%08x failed with response 0x%02x", addr, resp);
                error_count++;
            end
        end
    endtask

    // Task pour polling de status avec BHV
    task poll_status_bhv(input integer bit_pos, input logic expected_value);
        automatic DATA_T status;
        automatic integer poll_count = 0;
        begin
            $display("[%0t] Polling for status bit %0d = %0d", $time, bit_pos, expected_value);
            
            do begin
                axi_read_bhv(ADDR_STATUS, status);
                poll_count++;
                if (poll_count > 10000) begin
                    $display("ERROR: Timeout waiting for status bit %0d", bit_pos);
                    error_count++;
                    return;
                end
            end while (status[bit_pos] != expected_value);
            
            $display("[%0t] Status bit %0d reached %0d after %0d polls", 
                     $time, bit_pos, expected_value, poll_count);
        end
    endtask

    // Task complète pour test AES avec BHV
    task test_aes_encryption_bhv();
        automatic DATA_T temp_data;
        automatic logic [127:0] result;
        begin
            $display("\n=== AES-128 Encryption Test with Uniform Framework ===");
            
            // 1. Wait for ready
            poll_status_bhv(0, 1); // STATUS_READY_BIT = 0
            
            // 2. Write key (8 words) using BHV
            axi_write_bhv(ADDR_KEY0 + 0, AES128_KEY[255:224]);
            axi_write_bhv(ADDR_KEY0 + 1, AES128_KEY[223:192]);
            axi_write_bhv(ADDR_KEY0 + 2, AES128_KEY[191:160]);
            axi_write_bhv(ADDR_KEY0 + 3, AES128_KEY[159:128]);
            axi_write_bhv(ADDR_KEY0 + 4, AES128_KEY[127:96]);
            axi_write_bhv(ADDR_KEY0 + 5, AES128_KEY[95:64]);
            axi_write_bhv(ADDR_KEY0 + 6, AES128_KEY[63:32]);
            axi_write_bhv(ADDR_KEY0 + 7, AES128_KEY[31:0]);
            
            // 3. Write plaintext block using BHV
            axi_write_bhv(ADDR_BLOCK0 + 0, PLAINTEXT[127:96]);
            axi_write_bhv(ADDR_BLOCK0 + 1, PLAINTEXT[95:64]);
            axi_write_bhv(ADDR_BLOCK0 + 2, PLAINTEXT[63:32]);
            axi_write_bhv(ADDR_BLOCK0 + 3, PLAINTEXT[31:0]);
            
            // 4. Configure: AES-128, Encrypt
            axi_write_bhv(ADDR_CONFIG, 32'h01); // encdec=1, keylen=0
            
            // 5. Start operation
            $display("[%0t] Starting AES encryption...", $time);
            axi_write_bhv(ADDR_CTRL, 32'h01);
            
            // 6. Poll for completion
            poll_status_bhv(1, 1); // STATUS_VALID_BIT = 1
            
            // 7. Read result using BHV
            axi_read_bhv(ADDR_RESULT0 + 0, temp_data);
            result[127:96] = temp_data;
            axi_read_bhv(ADDR_RESULT0 + 1, temp_data);
            result[95:64] = temp_data;
            axi_read_bhv(ADDR_RESULT0 + 2, temp_data);
            result[63:32] = temp_data;
            axi_read_bhv(ADDR_RESULT0 + 3, temp_data);
            result[31:0] = temp_data;
            
            // 8. Verify result
            if (result == EXPECTED_CIPHER) begin
                $display("SUCCESS: AES encryption result matches expected value");
                $display("Result: 0x%032x", result);
            end else begin
                $display("ERROR: AES encryption failed");
                $display("Expected: 0x%032x", EXPECTED_CIPHER);
                $display("Got:      0x%032x", result);
                error_count++;
            end
        end
    endtask

    // Task pour test des registres basiques
    task test_basic_registers_bhv();
        automatic DATA_T data;
        begin
            $display("\n=== Testing Basic Registers with Uniform Framework ===");
            
            // Test reading ID registers
            axi_read_bhv(ADDR_NAME0, data);
            if (data != 32'h61657320) begin // "aes "
                $display("ERROR: NAME0 register mismatch");
                error_count++;
            end else begin
                $display("SUCCESS: NAME0 register = 0x%08x", data);
            end
            
            axi_read_bhv(ADDR_VERSION, data);
            $display("Version register: 0x%08x", data);
            
            // Test status register
            axi_read_bhv(ADDR_STATUS, data);
            $display("Initial status: 0x%08x", data);
        end
    endtask

    //----------------------------------------------------------------
    // Main test sequence
    //----------------------------------------------------------------
    `TEST_SUITE begin
        `TEST_CASE("aes") begin
            $display("=== AXI4-Lite AES Testbench ===");
            
            // Wait for reset deassertion
            @(negedge seq.rst);
            repeat (10) @(posedge seq.clk);
            
            // Run tests
            test_basic_registers_bhv();
            test_aes_encryption_bhv();
            
            // Final report
            repeat (10) @(posedge seq.clk);
            $display("\n=== Test Summary ===");
            $display("Tests run: %0d", test_count);
            $display("Errors: %0d", error_count);
            
            if (error_count == 0) begin
                $display("*** ALL TESTS PASSED ***");
            end else begin
                $display("*** %0d TESTS FAILED ***", error_count);
            end
        end
    end

    //----------------------------------------------------------------
    // Timeout 
    //----------------------------------------------------------------
    initial begin
        #1000us;
        $display("ERROR: Testbench timeout");
        $finish;
    end

endmodule