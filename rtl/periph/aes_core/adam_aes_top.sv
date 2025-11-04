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

  localparam ADDR_KEY         = 8'h14;
  localparam ADDR_BLOCK       = 8'h18;
  localparam ADDR_RESULT      = 8'h1C;

  //----------------------------------------------------------------
  // Registers 
  //----------------------------------------------------------------
  logic [31 : 0]     ctrl_reg;
  logic [31 : 0]     status_reg;
  logic [31 : 0]     config_reg;
  logic [31 : 0]     events_reg;
  logic [31 : 0]     interrupt_enable_reg;

  logic [31 : 0]     block_reg [0 : 3];
  logic [31 : 0]     key_reg [0 : 7];
  logic [127 : 0]    result_reg;

  // Counters
  logic [2 : 0]      key_write_counter;
  logic [2 : 0]      block_write_counter;
  logic [2 : 0]      result_read_counter;

  // Internal signals
  logic              start_pulse;
  logic              core_valid_q;
  logic [31 : 0]     tmp_read_data;

  //----------------------------------------------------------------
  // Core interface signals
  //----------------------------------------------------------------
  logic              core_encdec;
  logic              core_start;
  logic              core_keylen;
  logic [255 : 0]    core_key;
  logic [127 : 0]    core_block;
  logic              core_ready;
  logic              core_valid;
  logic [127 : 0]    core_result;

  //----------------------------------------------------------------
  // Extract bit fields from registers
  //----------------------------------------------------------------
  logic periph_enable;
  logic encdec;
  logic keylen;
  logic ready_bit;
  logic valid_bit;
  logic done_event;
  logic done_event_ie;

  assign periph_enable = ctrl_reg[CTRL_ENABLE_BIT];
  assign encdec        = config_reg[CTRL_ENCDEC_BIT];
  assign keylen        = config_reg[CTRL_KEYLEN_BIT];
  assign ready_bit     = status_reg[STATUS_READY_BIT];
  assign valid_bit     = status_reg[STATUS_VALID_BIT];
  assign done_event    = events_reg[ER_DONE_BIT];
  assign done_event_ie = interrupt_enable_reg[IER_DONEIE_BIT];

  //----------------------------------------------------------------
  // Core interface connections
  //----------------------------------------------------------------
  assign core_encdec = encdec;
  assign core_start  = start_pulse;
  assign core_keylen = keylen;
  assign core_key    = {key_reg[0], key_reg[1], key_reg[2], key_reg[3],
                        key_reg[4], key_reg[5], key_reg[6], key_reg[7]};
  assign core_block  = {block_reg[0], block_reg[1], block_reg[2], block_reg[3]};

  // Detect rising edge for event generation
  logic valid_posedge;
  assign valid_posedge = core_valid && !core_valid_q;

  // IRQ generation
  assign irq = periph_enable && done_event && done_event_ie;

  //----------------------------------------------------------------
  // Core instantiation 
  //----------------------------------------------------------------
  adam_aes_core_fully_pipelined core(          // instantiate adam_aes_core_fully_pipelined for the pipelined version
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
  // Register update logic
  //----------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      // Reset all 32-bit registers
      ctrl_reg              <= 32'h0;
      status_reg            <= 32'h0;
      config_reg            <= 32'h0;
      events_reg            <= 32'h0;
      interrupt_enable_reg  <= 32'h0;
      result_reg            <= 128'h0;
      
      // Reset counters
      key_write_counter     <= 3'd0;
      block_write_counter   <= 3'd0;
      result_read_counter   <= 3'd0;
      
      // Reset internal signals
      start_pulse           <= 1'b0;
      core_valid_q          <= 1'b0;
      
      // Reset arrays
      for (int i = 0; i < 4; i++) begin
        block_reg[i] <= 32'h0;
      end
      
      for (int i = 0; i < 8; i++) begin
        key_reg[i] <= 32'h0;
      end
      
    end else begin
      // Update edge detection
      core_valid_q <= core_valid;
      
      if (start_pulse) begin
        start_pulse <= 1'b0;
      end
      
      // Update STATUS register from core (continuous update)
      status_reg[STATUS_READY_BIT] <= core_ready;
      status_reg[STATUS_VALID_BIT] <= core_valid;
      
      // Capture result when valid
      if (core_valid) begin
        result_reg <= core_result;
      end

      // Set event flag on operation completion
      if (valid_posedge) begin
        events_reg[ER_DONE_BIT] <= 1'b1;
      end

      // Register WRITE access
      if (cs && we) begin
        case (address)
          
          ADDR_CTRL: begin
            if (write_data[CTRL_START_BIT]) begin
              start_pulse <= 1'b1;
              // Reset counters for new operation
              key_write_counter   <= 3'd0;
              block_write_counter <= 3'd0;
              result_read_counter <= 3'd0;
            end
            
            // Write CTRL register (ENABLE bit principalement)
            ctrl_reg[CTRL_ENABLE_BIT] <= write_data[CTRL_ENABLE_BIT];
          end
          
          ADDR_CONFIG: begin
            // Write entire CONFIG register
            config_reg <= write_data;
          end

          ADDR_ER: begin
            // Write 1 to clear (W1C) for event bits
            events_reg <= events_reg & ~write_data;
          end

          ADDR_IER: begin
            // Write entire IER register
            interrupt_enable_reg <= write_data;
          end
          
          ADDR_KEY: begin
            // Auto-increment write for KEY
            key_reg[key_write_counter] <= write_data;
            key_write_counter <= (key_write_counter == 3'd7) ? 3'd0 : key_write_counter + 3'd1;
          end

          ADDR_BLOCK: begin
            // Auto-increment write for BLOCK
            block_reg[block_write_counter] <= write_data;
            block_write_counter <= (block_write_counter == 3'd3) ? 3'd0 : block_write_counter + 3'd1;
          end
          
          default: ;
        endcase
      end
      
      // Register READ access - increment RESULT counter
      if (cs && !we && address == ADDR_RESULT) begin
        result_read_counter <= (result_read_counter == 3'd3) ? 3'd0 : result_read_counter + 3'd1;
      end
    end
  end

  //----------------------------------------------------------------
  // Read logic (combinational)
  //----------------------------------------------------------------
  always_comb begin
    tmp_read_data = 32'h0;
    
    if (cs && !we) begin
      case (address)
        
        ADDR_CTRL: begin
          // Return full CTRL register, but START bit always reads as 0
          tmp_read_data = ctrl_reg;
          tmp_read_data[CTRL_START_BIT] = 1'b0;  // Start is write-only pulse
        end
        
        ADDR_STATUS: begin
          // Return full STATUS register (read-only)
          tmp_read_data = status_reg;
        end
        
        ADDR_CONFIG: begin
          // Return full CONFIG register
          tmp_read_data = config_reg;
        end

        ADDR_ER: begin
          // Return full Event Register
          tmp_read_data = events_reg;
        end

        ADDR_IER: begin
          // Return full Interrupt Enable Register
          tmp_read_data = interrupt_enable_reg;
        end
        
        ADDR_KEY: begin
          // KEY not readable (return 0 for security)
          tmp_read_data = 32'h0;
        end
        
        ADDR_BLOCK: begin
          // BLOCK not readable (return 0)
          tmp_read_data = 32'h0;
        end
        
        ADDR_RESULT: begin
          // Auto-increment read for RESULT
          case (result_read_counter)
            3'd0: tmp_read_data = result_reg[127:96];
            3'd1: tmp_read_data = result_reg[95:64];
            3'd2: tmp_read_data = result_reg[63:32];
            3'd3: tmp_read_data = result_reg[31:0];
            default: tmp_read_data = 32'h0;
          endcase
        end
        
        default: tmp_read_data = 32'h0;
      endcase
    end
  end

  assign read_data = tmp_read_data;

endmodule

//======================================================================
// EOF adam_aes_top.sv
//======================================================================