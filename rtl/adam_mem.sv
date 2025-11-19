/*
 * Copyright 2025 LIRMM
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

`include "adam/macros.svh"

module adam_mem #(
    `ADAM_CFG_PARAMS,

    parameter SIZE = 4096
// `ifdef DIFT
//     ,   
//     parameter TAG_WIDTH = 4
// `endif

`ifndef SYNTHESIS
    , parameter string HEXFILE = ""
    // `ifdef DIFT
    // , parameter string TAG_HEXFILE = ""
    // `endif
`endif
) (
    ADAM_SEQ.Slave seq,

    input  logic  req,
    input  ADDR_T addr,
    input  logic  we,
    input  STRB_T be,
    input  DATA_T wdata,
    output DATA_T rdata
// `ifdef DIFT
//     ,
//     input logic   we_tag,
//     input logic   wdata_tag,
//     output logic [TAG_WIDTH-1:0] rdata_tag
// `endif
);

    localparam UNALIGNED_WIDTH = $clog2(STRB_WIDTH);
    localparam ALIGNED_WIDTH   = ADDR_WIDTH - UNALIGNED_WIDTH;
    localparam ALIGNED_SIZE    = SIZE / STRB_WIDTH;

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [ALIGNED_SIZE-1:0];
// `ifdef DIFT
//     (* ram_style = "block" *)
//     reg [TAG_WIDTH-1:0] tag_mem [ALIGNED_SIZE-1:0];
// `endif

`ifndef SYNTHESIS
    initial $readmemh(HEXFILE, mem);
    // `ifdef DIFT
    //     initial $readmemh(TAG_HEXFILE, tag_mem);
    // `endif
`endif

    logic [ALIGNED_WIDTH-1:0] aligned;

    assign aligned = addr[ADDR_WIDTH-1:UNALIGNED_WIDTH];

    always_ff @(posedge seq.clk) begin
        if (we) begin
            for (int i = 0; i < STRB_WIDTH; i++) begin
                if (be[i]) begin
                    mem[aligned][i*8 +: 8] <= wdata[i*8 +: 8];
                end
            end
            rdata <= mem[aligned];
        end
        else begin
            rdata <= mem[aligned];
        end
    end
    
// `ifdef DIFT
//     always_ff @(posedge seq.clk) begin
//         if (we_tag) begin
//             for (int i = 0; i < STRB_WIDTH; i++) begin
//                 if (be[i]) begin
//                     tag_mem[aligned][i] <= wdata_tag;
//                 end
//             end
//             rdata_tag <= tag_mem[aligned];
//         end
//         else begin
//             rdata_tag <= tag_mem[aligned];
//         end
//     end
// `endif

endmodule
