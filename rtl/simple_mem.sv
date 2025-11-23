`timescale 1ns/1ps

module simple_mem #(
    parameter SIZE      = 16384,                    // Memory size in bytes
    parameter INIT_FILE = ""                        // Hex file for initialization
) (
    input  logic        clk,
    input  logic        rst_n,
    
    // OBI interface
    input  logic        req,                        // Request
    output logic        gnt,                        // Grant
    output logic        rvalid,                     // Read valid
    input  logic [31:0] addr,                       // Address
    input  logic        we,                         // Write enable
    input  logic [3:0]  be,                         // Byte enable
    input  logic [31:0] wdata,                      // Write data
    output logic [31:0] rdata                       // Read data
);

    //==========================================================================
    // Local parameters
    //==========================================================================
    localparam ADDR_WIDTH      = 32;
    localparam DATA_WIDTH      = 32;
    localparam STRB_WIDTH      = 4;
    localparam UNALIGNED_WIDTH = 2;                 // log2(4 bytes)
    localparam ALIGNED_WIDTH   = $clog2(SIZE) - UNALIGNED_WIDTH;
    localparam ALIGNED_SIZE    = SIZE / STRB_WIDTH;

    //==========================================================================
    // Memory array
    //==========================================================================
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [ALIGNED_SIZE-1:0];

    //==========================================================================
    // Memory initialization
    //==========================================================================
    initial begin

        // Load hex file if specified
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
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
    // Simple 1-cycle latency model
    // Grant is always ready (no back-pressure)
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
    //==========================================================================
    always_ff @(posedge clk) begin

            if (we) begin
                // Write operation with byte enables
                for (int i = 0; i < STRB_WIDTH; i++) begin
                    if (be[i]) begin
                        mem[aligned_addr][i*8 +: 8] <= wdata[i*8 +: 8];
                    end
                end
                rdata <= mem[aligned_addr];
            end 
        else begin
            rdata <= mem[aligned_addr]; // Default read data when not requested
        end
    end
    


endmodule