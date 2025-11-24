`timescale 1ns/1ps

module tag_mem #(
    parameter SIZE      = 8192,                     // Memory size in bytes (same as data RAM)
    parameter TAG_WIDTH = 4,                        // Tag width in bits
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
    input  logic [TAG_WIDTH-1:0]  wdata_tag,        // Write tag (4 bits per access)
    output logic [TAG_WIDTH-1:0]  rdata_tag         // Read tag (4 bits per access)
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
    // Each 32-bit word stores 8 tags of 4 bits each
    // This allows us to store tags for 8 bytes in each memory word
    //==========================================================================
    (* ram_style = "block" *)
    reg [31:0] mem [ALIGNED_SIZE-1:0];              // Same organization as data memory

    //==========================================================================
    // Memory initialization
    //==========================================================================
    initial begin
        // Initialize all tags to 0 (untainted) by default
        for (int i = 0; i < ALIGNED_SIZE; i++) begin
            mem[i] = 32'h0;
        end

        // Load hex file if specified (optional tag initialization)
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    //==========================================================================
    // Address alignment
    //==========================================================================
    logic [ALIGNED_WIDTH-1:0] aligned_addr;
    logic [1:0] byte_offset;                        // Which byte within the word (0-3)

    assign aligned_addr = addr[ALIGNED_WIDTH+UNALIGNED_WIDTH-1:UNALIGNED_WIDTH];
    assign byte_offset  = addr[1:0];                // Byte offset within 32-bit word

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
    // Tag read/write logic
    // Each 32-bit word stores 8 tags of 4 bits:
    // mem[addr][31:28] = tag for byte 3
    // mem[addr][27:24] = tag for byte 2
    // mem[addr][23:20] = tag for byte 1
    // mem[addr][19:16] = tag for byte 0
    // mem[addr][15:12] = tag for byte 3 of previous word (if packed differently)
    //
    // We use byte_offset to select which 4-bit tag to access
    //==========================================================================

    logic [31:0] current_tags;                      // Current tag word
    logic [31:0] updated_tags;                      // Updated tag word after write

    always_ff @(posedge clk) begin
        if (req) begin
            current_tags = mem[aligned_addr];

            if (we) begin
                // Write operation - update tags based on byte enables
                updated_tags = current_tags;

                // Update tag for each enabled byte
                for (int i = 0; i < 4; i++) begin
                    if (be[i]) begin
                        // Each byte gets the same 4-bit tag from wdata_tag
                        // Position the tag in the correct 4-bit slice
                        updated_tags[i*8 +: 4] = wdata_tag;
                    end
                end

                mem[aligned_addr] <= updated_tags;
            end
        end
    end

    // Read operation - extract tag based on byte offset
    // For simplicity, return tag of the first enabled byte
    always_comb begin
        rdata_tag = 4'b0;

        // Select tag based on byte offset or first enabled byte
        case (byte_offset)
            2'b00: rdata_tag = current_tags[3:0];      // Byte 0
            2'b01: rdata_tag = current_tags[11:8];     // Byte 1
            2'b10: rdata_tag = current_tags[19:16];    // Byte 2
            2'b11: rdata_tag = current_tags[27:24];    // Byte 3
        endcase
    end

endmodule
