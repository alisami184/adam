//======================================================================
// adam_aes_top.sv - AES Top Module with Interrupt Support
//======================================================================
module adam_aes_top(
    // Clock and reset
    input  logic           clk,
    input  logic           reset_n,

    // Control interface
    input  logic           cs,
    input  logic           we,

    // Data ports
    input  logic  [7 : 0]  address,
    input  logic  [31 : 0] write_data,
    output logic [31 : 0]  read_data,
    
    // Interrupt output
    output logic           irq
);

  //----------------------------------------------------------------
  // Internal constant and parameter definitions
  //----------------------------------------------------------------
  localparam ADDR_CTRL        = 8'h00;
  localparam CTRL_START_BIT   = 0;
  localparam CTRL_ENABLE_BIT  = 1;

  localparam ADDR_STATUS      = 8'h04;
  localparam STATUS_READY_BIT = 0;
  localparam STATUS_VALID_BIT = 1;

  localparam ADDR_CONFIG      = 8'h08;
  localparam CTRL_ENCDEC_BIT  = 0;
  localparam CTRL_KEYLEN_BIT  = 1;

  localparam ADDR_ER          = 8'h0C;
  localparam ER_DONE_BIT      = 0;

  localparam ADDR_IER         = 8'h10;
  localparam IER_DONEIE_BIT   = 0;

  localparam ADDR_KEY0        = 8'h14;
  localparam ADDR_KEY1        = 8'h18;
  localparam ADDR_KEY2        = 8'h1C;
  localparam ADDR_KEY3        = 8'h20;
  localparam ADDR_KEY4        = 8'h24;
  localparam ADDR_KEY5        = 8'h28;
  localparam ADDR_KEY6        = 8'h2C;
  localparam ADDR_KEY7        = 8'h30;

  localparam ADDR_BLOCK0      = 8'h34;
  localparam ADDR_BLOCK1      = 8'h38;
  localparam ADDR_BLOCK2      = 8'h3C;
  localparam ADDR_BLOCK3      = 8'h40;

  localparam ADDR_RESULT0     = 8'h44;
  localparam ADDR_RESULT1     = 8'h48;
  localparam ADDR_RESULT2     = 8'h4C;
  localparam ADDR_RESULT3     = 8'h50;

  //----------------------------------------------------------------
  // Registers
  //----------------------------------------------------------------
  logic              periph_enable_reg;
  logic              start_pulse;

  logic              encdec_reg;
  logic              keylen_reg;

  logic [31 : 0]     block_reg [0 : 3];
  logic [31 : 0]     key_reg [0 : 7];

  logic [127 : 0]    result_reg;
  logic              valid_reg;
  logic              ready_reg;

  // Interrupt registers
  logic [31 : 0]     events_reg;
  logic [31 : 0]     interrupt_enable_reg;

  //----------------------------------------------------------------
  // Wires
  //----------------------------------------------------------------
  logic [31 : 0]     tmp_read_data;
  
  logic              core_encdec;
  logic              core_start;
  logic              core_ready;
  logic [255 : 0]    core_key;
  logic              core_keylen;
  logic [127 : 0]    core_block;
  logic [127 : 0]    core_result;
  logic              core_valid;
  logic              core_valid_q;
  logic              valid_posedge;
  
  logic              done_event;
  logic              done_event_ie;

  //----------------------------------------------------------------
  // Core instantiation
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
  // Concurrent assignments
  //----------------------------------------------------------------
  assign core_encdec = encdec_reg;
  assign core_start  = start_pulse;
  assign core_keylen = keylen_reg;
  assign core_key    = {key_reg[7], key_reg[6], key_reg[5], key_reg[4],
                        key_reg[3], key_reg[2], key_reg[1], key_reg[0]};
  assign core_block  = {block_reg[3], block_reg[2], block_reg[1], block_reg[0]};

  // Detect rising edge of valid signal for event generation
  assign valid_posedge = core_valid && !core_valid_q;

  // Extract interrupt control signals
  assign done_event    = events_reg[ER_DONE_BIT];
  assign done_event_ie = interrupt_enable_reg[IER_DONEIE_BIT];

  // IRQ generation: interrupt when peripheral enabled, event set, and interrupt enabled
  assign irq = periph_enable_reg && done_event && done_event_ie;

  //----------------------------------------------------------------
  // Register update logic
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all registers
      periph_enable_reg     <= 1'b0;
      start_pulse           <= 1'b0;
      encdec_reg            <= 1'b0;
      keylen_reg            <= 1'b0;
      result_reg            <= 128'h0;
      valid_reg             <= 1'b0;
      ready_reg             <= 1'b0;
      core_valid_q          <= 1'b0;
      events_reg            <= 32'h0;
      interrupt_enable_reg  <= 32'h0;
      
      for (int i = 0; i < 4; i++) begin
        block_reg[i] <= 32'h0;
      end
      
      for (int i = 0; i < 8; i++) begin
        key_reg[i] <= 32'h0;
      end
      
    end else begin
      // Update previous valid state for edge detection
      core_valid_q <= core_valid;
      
      // Start pulse is single-cycle
      start_pulse <= 1'b0;
      
      // Update status from core
      ready_reg <= core_ready;
      valid_reg <= core_valid;
      
      // Capture result when valid
      if (core_valid) begin
        result_reg <= core_result;
      end

      // Set event flag on operation completion (rising edge of valid)
      if (valid_posedge) begin
        events_reg[ER_DONE_BIT] <= 1'b1;
      end

      // Register write access
      if (cs && we) begin
        case (address)
          
          ADDR_CTRL: begin
            // Bit 0: Start (pulse)
            if (write_data[CTRL_START_BIT]) begin
              start_pulse <= 1'b1;
            end
            // Bit 1: Peripheral enable
            periph_enable_reg <= write_data[CTRL_ENABLE_BIT];
          end
          
          ADDR_CONFIG: begin
            encdec_reg <= write_data[CTRL_ENCDEC_BIT];
            keylen_reg <= write_data[CTRL_KEYLEN_BIT];
          end

          // Event Register - Write 1 to clear
          ADDR_ER: begin
            if (write_data[ER_DONE_BIT]) begin
              events_reg[ER_DONE_BIT] <= 1'b0;
            end
          end

          // Interrupt Enable Register
          ADDR_IER: begin
            interrupt_enable_reg <= write_data;
          end
          
          // KEY registers
          ADDR_KEY0: key_reg[0] <= write_data;
          ADDR_KEY1: key_reg[1] <= write_data;
          ADDR_KEY2: key_reg[2] <= write_data;
          ADDR_KEY3: key_reg[3] <= write_data;
          ADDR_KEY4: key_reg[4] <= write_data;
          ADDR_KEY5: key_reg[5] <= write_data;
          ADDR_KEY6: key_reg[6] <= write_data;
          ADDR_KEY7: key_reg[7] <= write_data;
          
          // BLOCK registers
          ADDR_BLOCK0: block_reg[0] <= write_data;
          ADDR_BLOCK1: block_reg[1] <= write_data;
          ADDR_BLOCK2: block_reg[2] <= write_data;
          ADDR_BLOCK3: block_reg[3] <= write_data;
          
          default: ; // Read-only or invalid registers
        endcase
      end
    end
  end

  //----------------------------------------------------------------
  // Read logic
  //----------------------------------------------------------------
  always_comb begin
    tmp_read_data = 32'h0;
    
    if (cs && !we) begin
      case (address)
        
        ADDR_CTRL: begin
          tmp_read_data[CTRL_ENABLE_BIT] = periph_enable_reg;
          // Start bit always reads as 0 (write-only pulse)
        end
        
        ADDR_STATUS: begin
          tmp_read_data[STATUS_READY_BIT] = ready_reg;
          tmp_read_data[STATUS_VALID_BIT] = valid_reg;
        end
        
        ADDR_CONFIG: begin
          tmp_read_data[CTRL_ENCDEC_BIT] = encdec_reg;
          tmp_read_data[CTRL_KEYLEN_BIT] = keylen_reg;
        end

        ADDR_ER: begin
          tmp_read_data = events_reg;
        end

        ADDR_IER: begin
          tmp_read_data = interrupt_enable_reg;
        end
        
        // KEY registers (readable)
        ADDR_KEY0: tmp_read_data = key_reg[0];
        ADDR_KEY1: tmp_read_data = key_reg[1];
        ADDR_KEY2: tmp_read_data = key_reg[2];
        ADDR_KEY3: tmp_read_data = key_reg[3];
        ADDR_KEY4: tmp_read_data = key_reg[4];
        ADDR_KEY5: tmp_read_data = key_reg[5];
        ADDR_KEY6: tmp_read_data = key_reg[6];
        ADDR_KEY7: tmp_read_data = key_reg[7];
        
        // BLOCK registers (readable)
        ADDR_BLOCK0: tmp_read_data = block_reg[0];
        ADDR_BLOCK1: tmp_read_data = block_reg[1];
        ADDR_BLOCK2: tmp_read_data = block_reg[2];
        ADDR_BLOCK3: tmp_read_data = block_reg[3];
        
        // RESULT registers (read-only)
        ADDR_RESULT0: tmp_read_data = result_reg[127:96];
        ADDR_RESULT1: tmp_read_data = result_reg[95:64];
        ADDR_RESULT2: tmp_read_data = result_reg[63:32];
        ADDR_RESULT3: tmp_read_data = result_reg[31:0];
        
        default: tmp_read_data = 32'h0;
      endcase
    end
  end

  assign read_data = tmp_read_data;

endmodule

//======================================================================
// EOF adam_aes_top.sv
//======================================================================