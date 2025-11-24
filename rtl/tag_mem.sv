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
    input  logic [3:0]       wdata_tag,             // Write tag (4 bits - replicated from CPU)
    output logic [3:0]       rdata_tag              // Read tag - 4 bits (1 bit per byte)
);

    //==========================================================================
    // Local parameters
    //==========================================================================
    localparam ADDR_WIDTH      = 32;
    localparam TAG_WIDTH       = 4;
    localparam UNALIGNED_WIDTH = 2;                 // log2(4 bytes)
    localparam STRB_WIDTH      = 4;
    localparam ALIGNED_WIDTH   = $clog2(SIZE) - UNALIGNED_WIDTH;
    localparam ALIGNED_SIZE    = SIZE / STRB_WIDTH;          // Number of 32-bit words

    //==========================================================================
    // Tag Memory Array
    // One 4-bit tag entry per 32-bit data word
    // Each bit corresponds to one byte: [3]=byte3, [2]=byte2, [1]=byte1, [0]=byte0
    //==========================================================================
    (* ram_style = "block" *)
    reg [TAG_WIDTH-1:0] tag_mem [ALIGNED_SIZE-1:0];

    //==========================================================================
    // Memory initialization
    //==========================================================================
    initial begin
        // Initialize all tags to 0 (untainted) by default
        for (int i = 0; i < ALIGNED_SIZE; i++) begin  // FIX: was ALIGNED_SIZE-1
            tag_mem[i] = 4'h0;
        end

        // Load hex file if specified (optional tag initialization)
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, tag_mem);
        end
    end

    //==========================================================================
    // Address alignment
    //==========================================================================
    logic [ALIGNED_WIDTH-1:0] aligned_addr;
    assign aligned_addr = addr[ALIGNED_WIDTH+UNALIGNED_WIDTH-1:UNALIGNED_WIDTH];

    //==========================================================================
    // OBI protocol
    //==========================================================================
    // Simple 1-cycle latency model (same as simple_mem)
    assign gnt = req;

    // Read valid delayed by 1 cycle after grant
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid <= 1'b0;
        end else begin
            rvalid <= req && gnt;
        end
    end

    //==========================================================================
    // Memory read/write
    //
    // Write: CPU sends wdata_tag[3:0] = {4{tag_bit}}
    //        Write to bytes according to be (byte enables)
    //
    // Read: Return tag_mem[addr][3:0] - one bit per byte
    //==========================================================================
    always_ff @(posedge clk) begin
        if (req) begin
            if (we) begin
                // Write operation with byte enables
                // Each bit of wdata_tag corresponds to one byte
                for (int i = 0; i < STRB_WIDTH; i++) begin
                    if (be[i]) begin
                        tag_mem[aligned_addr][i] <= wdata_tag[i];
                    end
                end
            end

            // Always read for proper OBI timing
            // (read data available when rvalid=1)
            rdata_tag <= tag_mem[aligned_addr];
        end
    end

endmodule
