//======================================================================
// adam_aes_top.sv
//======================================================================
module adam_aes_top(
           // Clock and reset.
           input  logic           clk,
           input  logic           reset_n,

           // Control.
           input  logic           cs,
           input  logic           we,

           // Data ports.
           input  logic  [7 : 0]  address,
           input  logic  [31 : 0] write_data,
           output logic [31 : 0]  read_data,
           output logic           irq
          );

  //----------------------------------------------------------------
  // Internal constant and parameter definitions.
  //----------------------------------------------------------------
  localparam ADDR_NAME0       = 8'h00;
  localparam ADDR_NAME1       = 8'h04;
  localparam ADDR_VERSION     = 8'h08;

  localparam ADDR_CTRL        = 8'h20;
  localparam CTRL_START_BIT   = 0;   

  localparam ADDR_STATUS      = 8'h24;
  localparam STATUS_READY_BIT = 0;
  localparam STATUS_VALID_BIT = 1;

  localparam ADDR_CONFIG      = 8'h28;
  localparam CTRL_ENCDEC_BIT  = 0;
  localparam CTRL_KEYLEN_BIT  = 1;

  localparam ADDR_KEY0        = 8'h40;
  localparam ADDR_KEY7        = 8'h5C;

  localparam ADDR_BLOCK0      = 8'h80;
  localparam ADDR_BLOCK3      = 8'h8C;

  localparam ADDR_RESULT0     = 8'hC0;
  localparam ADDR_RESULT3     = 8'hCC;

  localparam CORE_NAME0       = 32'h61657320; // "aes "
  localparam CORE_NAME1       = 32'h20202020; // "    "
  localparam CORE_VERSION     = 32'h302e3830; // "0.80" (version mise à jour)

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  logic start_pulse;    // CHANGEMENT: pulse au lieu de registre

  logic encdec_reg;
  logic keylen_reg;
  logic config_we;

  logic [31 : 0] block_reg [0 : 3];
  logic          block_we;

  logic [31 : 0] key_reg [0 : 7];
  logic          key_we;

  logic [127 : 0] result_reg;
  logic           valid_reg;
  logic           ready_reg;

  //----------------------------------------------------------------
  // Wires.
  //----------------------------------------------------------------
  logic [31 : 0]   tmp_read_data;

  logic           core_encdec;
  logic           core_start;
  logic           core_ready;
  logic [255 : 0] core_key;
  logic           core_keylen;
  logic [127 : 0] core_block;
  logic [127 : 0] core_result;
  logic           core_valid;
  logic           core_valid_q;

  //----------------------------------------------------------------
  // Concurrent connectivity for ports etc.
  //----------------------------------------------------------------
  assign read_data = tmp_read_data;

  assign core_key = {key_reg[0], key_reg[1], key_reg[2], key_reg[3],
                     key_reg[4], key_reg[5], key_reg[6], key_reg[7]};

  assign core_block  = {block_reg[0], block_reg[1], block_reg[2], block_reg[3]};
  assign core_start  = start_pulse;  // CHANGEMENT: utilise le pulse
  assign core_encdec = encdec_reg;
  assign core_keylen = keylen_reg;
  assign irq         = core_valid & ~ core_valid_q;

  //----------------------------------------------------------------
  // core instantiation
  //----------------------------------------------------------------
  adam_aes_core core(
                .clk(clk),
                .reset_n(reset_n),

                .encdec(core_encdec),
                .start(core_start),
                .ready(core_ready),
                .result_valid(core_valid),

                .key(core_key),
                .keylen(core_keylen),

                .block(core_block),
                .result(core_result)
               );

  //----------------------------------------------------------------
  // latch core_valid
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n)
    begin
      if (!reset_n)
        core_valid_q <= 1'b0;
      else
        core_valid_q <= core_valid;
    end

  //----------------------------------------------------------------
  // reg_update
  //----------------------------------------------------------------
  always_ff @ (posedge clk or negedge reset_n)
    begin : reg_update
      integer i;

      if (!reset_n)
        begin
          for (i = 0 ; i < 4 ; i = i + 1)
            block_reg[i] <= 32'h0;

          for (i = 0 ; i < 8 ; i = i + 1)
            key_reg[i] <= 32'h0;

          encdec_reg <= 1'b0;
          keylen_reg <= 1'b0;

          result_reg <= 128'h0;
          valid_reg  <= 1'b0;
          ready_reg  <= 1'b0;
        end
      else
        begin
          ready_reg  <= core_ready;
          valid_reg  <= core_valid;
          result_reg <= core_result;

          if (config_we)
            begin
              encdec_reg <= write_data[CTRL_ENCDEC_BIT];
              keylen_reg <= write_data[CTRL_KEYLEN_BIT];
            end

          if (key_we) begin
            case (address)
                8'h40: key_reg[0] <= write_data;
                8'h44: key_reg[1] <= write_data;
                8'h48: key_reg[2] <= write_data;
                8'h4C: key_reg[3] <= write_data;
                8'h50: key_reg[4] <= write_data;
                8'h54: key_reg[5] <= write_data;
                8'h58: key_reg[6] <= write_data;
                8'h5C: key_reg[7] <= write_data;
                default: ;
            endcase
          end

          if (block_we) begin
            case (address)
              8'h80: block_reg[0] <= write_data;
              8'h84: block_reg[1] <= write_data;
              8'h88: block_reg[2] <= write_data;
              8'h8C: block_reg[3] <= write_data;
              default;
            endcase
        end
    end // reg_update
    end 

  //----------------------------------------------------------------
  // api
  //----------------------------------------------------------------
  always_comb
    begin : api
      start_pulse   = 1'b0; 
      config_we     = 1'b0;
      key_we        = 1'b0;
      block_we      = 1'b0;
      tmp_read_data = 32'h0;

      if (cs)
        begin
          if (we)
            begin
              if (address == ADDR_CTRL)
                start_pulse = write_data[CTRL_START_BIT];  //pulse de start

              if (address == ADDR_CONFIG)
                config_we = 1'b1;

              if ((address >= ADDR_KEY0) && (address <= ADDR_KEY7))
                key_we = 1'b1;

              if ((address >= ADDR_BLOCK0) && (address <= ADDR_BLOCK3))
                block_we = 1'b1;
            end // if (we)

          else
            begin
              case (address)
                ADDR_NAME0:   tmp_read_data = CORE_NAME0;
                ADDR_NAME1:   tmp_read_data = CORE_NAME1;
                ADDR_VERSION: tmp_read_data = CORE_VERSION;
                ADDR_CTRL:    tmp_read_data = 32'h0;  // toujours 0 en lecture
                ADDR_STATUS:  tmp_read_data = {30'h0, valid_reg, ready_reg};

                default: ;
              endcase

              if ((address >= ADDR_RESULT0) && (address <= ADDR_RESULT3)) begin
              case (address)  
                8'hC0 : tmp_read_data = result_reg[127:96];
                8'hC4 : tmp_read_data = result_reg[95:64];
                8'hC8 : tmp_read_data = result_reg[63:32];
                8'hCC : tmp_read_data = result_reg[31:0];
                default;
              endcase
            end
        end
    end // api
    end
endmodule

//======================================================================
// EOF adam_aes_top.sv
//======================================================================