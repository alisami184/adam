`timescale 1ns/1ps

module tag_mem #(
    parameter SIZE      = 8192,                     // Memory size in bytes (same as data RAM)
    parameter INIT_FILE = ""                        // Hex file for initialization
) (
    input  logic        clk,
    input  logic        rst_n,

    // OBI-like interface for tags
    input  logic             req,                   // Request
    output logic             gnt,                   // Grant
    output logic             rvalid,                // Read valid
    input  logic [31:0]      addr,                  // Address (same as data memory)
    input  logic             we,                    // Write enable
    input  logic [3:0]       be,                    // Byte enable (4 bytes)
    input  logic             wdata_tag,             // Write tag - 1 bit (0=untainted, 1=tainted)
    output logic [3:0]       rdata_tag              // Read tag - 4 bits (1 bit per byte)
);

    //==========================================================================
    // Local parameters
    //==========================================================================
    localparam ADDR_WIDTH      = 32;
    localparam UNALIGNED_WIDTH = 2;                 // log2(4 bytes)
    localparam ALIGNED_WIDTH   = $clog2(SIZE) - UNALIGNED_WIDTH;
    localparam ALIGNED_SIZE    = SIZE / 4;          // Number of 32-bit words

    //==========================================================================
    // Tag memory array
    // Each 32-bit word stores tags for 8 words (8 tags x 4 bits = 32 bits)
    // Organization: 4 bits per data word (1 bit per byte)
    //
    // mem[i][3:0]   = tags for word i*8 + 0  (bits [3:0] = byte3,byte2,byte1,byte0)
    // mem[i][7:4]   = tags for word i*8 + 1
    // mem[i][11:8]  = tags for word i*8 + 2
    // ...
    // mem[i][31:28] = tags for word i*8 + 7
    //==========================================================================
    (* ram_style = "block" *)
    reg [31:0] mem [ALIGNED_SIZE/8-1:0];            // 8 words worth of tags per mem entry

    //==========================================================================
    // Memory initialization
    //==========================================================================
    initial begin
        // Initialize all tags to 0 (untainted) by default
        for (int i = 0; i < ALIGNED_SIZE/8; i++) begin
            mem[i] = 32'h0;
        end

        // Load hex file if specified (optional tag initialization)
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    //==========================================================================
    // Address decoding
    // We need to map 32-bit word address to tag memory location
    //==========================================================================
    logic [ALIGNED_WIDTH-1:0] aligned_addr;
    logic [ALIGNED_WIDTH-4:0] tag_mem_addr;         // Which tag memory word
    logic [2:0] tag_word_offset;                    // Which 4-bit tag within mem word (0-7)

    assign aligned_addr    = addr[ALIGNED_WIDTH+UNALIGNED_WIDTH-1:UNALIGNED_WIDTH];
    assign tag_mem_addr    = aligned_addr[ALIGNED_WIDTH-1:3];  // Divide by 8
    assign tag_word_offset = aligned_addr[2:0];                // Modulo 8

    //==========================================================================
    // OBI protocol
    //==========================================================================
    // Simple 1-cycle latency model (same as simple_mem)
    assign gnt = req;

    // Read valid delayed by 1 cycle after grant
    logic req_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid  <= 1'b0;
            req_reg <= 1'b0;
        end else begin
            req_reg <= req && gnt;
            rvalid  <= req_reg;
        end
    end

    //==========================================================================
    // Tag read/write logic
    //
    // DIFT Policy: If ANY byte of a word is tainted, the WHOLE word is tainted
    //
    // Write: wdata_tag (1 bit) is replicated to all enabled bytes
    //        If wdata_tag=1 and ANY byte is enabled → set ALL 4 tag bits to 1
    //        If wdata_tag=0 → set enabled byte tags to 0
    //
    // Read: Return 4 bits (1 bit per byte of the word)
    //==========================================================================

    logic [31:0] current_tag_word;                  // Current tag memory word (8 x 4-bit tags)
    logic [3:0]  current_tags;                      // Current 4-bit tag for target word
    logic [3:0]  updated_tags;                      // Updated tags after write
    logic [31:0] updated_tag_word;                  // Updated tag memory word

    logic [2:0] tag_offset_reg;                     // Registered for read

    always_ff @(posedge clk) begin
        if (req) begin
            // Read current tag memory word
            current_tag_word = mem[tag_mem_addr];

            // Extract the 4-bit tag for the target data word
            current_tags = current_tag_word[tag_word_offset*4 +: 4];

            if (we) begin
                // Write operation
                updated_tags = current_tags;

                // DIFT Policy Implementation:
                if (wdata_tag == 1'b1) begin
                    // If writing tainted data, taint ALL bytes of the word
                    // (conservative approach - if any byte is tainted, whole word is tainted)
                    updated_tags = 4'b1111;
                end else begin
                    // If writing untainted data, clear tags for enabled bytes only
                    for (int i = 0; i < 4; i++) begin
                        if (be[i]) begin
                            updated_tags[i] = 1'b0;
                        end
                    end
                end

                // Update the tag memory word
                updated_tag_word = current_tag_word;
                updated_tag_word[tag_word_offset*4 +: 4] = updated_tags;
                mem[tag_mem_addr] <= updated_tag_word;
            end

            // Register the offset for read data
            tag_offset_reg <= tag_word_offset;
        end
    end

    // Read operation - return 4 bits (1 per byte)
    always_ff @(posedge clk) begin
        if (req_reg) begin
            current_tag_word = mem[tag_mem_addr];
            rdata_tag <= current_tag_word[tag_offset_reg*4 +: 4];
        end
    end

endmodule
