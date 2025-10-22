//======================================================================
// adam_axil_aes.sv 
//======================================================================

`include "adam/macros.svh"
`include "axi/assign.svh"
`include "axi/typedef.svh"

module adam_axil_aes #(
    `ADAM_CFG_PARAMS,
    
    parameter MAX_TRANS = FAB_MAX_TRANS
) (
    ADAM_SEQ.Slave   seq,
    ADAM_PAUSE.Slave pause,

    AXI_LITE.Slave   axil,

    output logic irq
);

    //----------------------------------------------------------------
    // AXI4-Lite Channel Typedef
    //----------------------------------------------------------------
    `AXI_LITE_TYPEDEF_AW_CHAN_T(aw_chan_t, ADDR_T);
    `AXI_LITE_TYPEDEF_W_CHAN_T(w_chan_t, DATA_T, STRB_T);
    `AXI_LITE_TYPEDEF_B_CHAN_T(b_chan_t);
    `AXI_LITE_TYPEDEF_AR_CHAN_T(ar_chan_t, ADDR_T);
    `AXI_LITE_TYPEDEF_R_CHAN_T(r_chan_t, DATA_T);

    //----------------------------------------------------------------
    // Channel structs pour interface avec AXI
    //----------------------------------------------------------------
    aw_chan_t aw_chan;
    w_chan_t  w_chan;
    b_chan_t  b_chan;
    ar_chan_t ar_chan;
    r_chan_t  r_chan;

    // Assignation des structs aux signaux d'interface
    `AXI_LITE_ASSIGN_TO_AW(aw_chan, axil);
    `AXI_LITE_ASSIGN_TO_W(w_chan, axil);
    `AXI_LITE_ASSIGN_FROM_B(axil, b_chan);
    `AXI_LITE_ASSIGN_TO_AR(ar_chan, axil);
    `AXI_LITE_ASSIGN_FROM_R(axil, r_chan);

    //----------------------------------------------------------------
    // FSM States
    //----------------------------------------------------------------
    typedef enum logic [1:0] {
        W_IDLE = 2'b00,
        W_ADDR = 2'b01,
        W_DATA = 2'b10,
        W_RESP = 2'b11
    } write_state_t;

    typedef enum logic [1:0] {
        R_IDLE = 2'b00,
        R_ADDR = 2'b01,
        R_DATA = 2'b10
    } read_state_t;

    //----------------------------------------------------------------
    // Internal registers
    //----------------------------------------------------------------
    write_state_t write_state, write_state_next;
    read_state_t  read_state, read_state_next;
    
    ADDR_T awaddr_reg;
    DATA_T wdata_reg;
    STRB_T wstrb_reg;
    ADDR_T araddr_reg;

    // AES Core interface signals
    logic         aes_cs;
    logic         aes_we;
    logic [7:0]   aes_address;
    DATA_T        aes_write_data;
    DATA_T        aes_read_data;

    // Control signals
    logic addr_valid, data_valid;
    logic write_active, read_active;
    logic [7:0] write_addr, read_addr;
    DATA_T write_data_internal;
    logic aes_irq;

    assign irq = aes_irq;

    //----------------------------------------------------------------
    // AES Core instantiation
    //----------------------------------------------------------------
    adam_aes_top aes_core_inst (
        .clk(seq.clk),
        .reset_n(!seq.rst),
        .cs(aes_cs),
        .we(aes_we),
        .address(aes_address),
        .write_data(aes_write_data),
        .read_data(aes_read_data),
        .irq(aes_irq)
    );

    //----------------------------------------------------------------
    // Address validation function
    //----------------------------------------------------------------
    function automatic logic addr_is_valid(input ADDR_T addr);
        case (addr[7:0])
            8'h00, 8'h04, 8'h08,8'h0C,8'h10,
            8'h14,
            8'h18, 
            8'h1C:   
                return 1'b1;
            default:
                return 1'b0;
        endcase
    endfunction

    //----------------------------------------------------------------
    // Register update
    //----------------------------------------------------------------
    always_ff @(posedge seq.clk) begin
        if (seq.rst) begin
            write_state <= W_IDLE;
            read_state  <= R_IDLE;
            awaddr_reg  <= '0;
            wdata_reg   <= '0;
            wstrb_reg   <= '0;
            araddr_reg  <= '0;
        end else begin
            write_state <= write_state_next;
            read_state  <= read_state_next;

            // Capture Write Address
            if (axil.aw_valid && axil.aw_ready) begin
                awaddr_reg <= aw_chan.addr;
            end

            // Capture Write Data
            if (axil.w_valid && axil.w_ready) begin
                wdata_reg <= w_chan.data;
                wstrb_reg <= w_chan.strb;
            end

            // Capture Read Address
            if (axil.ar_valid && axil.ar_ready) begin
                araddr_reg <= ar_chan.addr;
            end
        end
    end

    //----------------------------------------------------------------
    // Write FSM
    //----------------------------------------------------------------
    always_comb begin
        // Default values
        write_state_next = write_state;
        axil.aw_ready = 1'b0;
        axil.w_ready  = 1'b0;
        axil.b_valid  = 1'b0;
        b_chan.resp   = axi_pkg::RESP_OKAY;
        
        // Internal write control
        write_active = 1'b0;
        write_addr = 8'h00;
        write_data_internal = '0;
        
        addr_valid = addr_is_valid(awaddr_reg);
        data_valid = (wstrb_reg == '1); // All bytes must be written

        case (write_state)
            W_IDLE: begin
                axil.aw_ready = 1'b1;
                axil.w_ready  = 1'b1;
                
                if (axil.aw_valid && axil.w_valid) begin
                    // Address and Data arrive simultaneously
                    write_state_next = W_RESP;
                end else if (axil.aw_valid) begin
                    // Address first
                    axil.w_ready = 1'b0;
                    write_state_next = W_DATA;
                end else if (axil.w_valid) begin
                    // Data first
                    axil.aw_ready = 1'b0;
                    write_state_next = W_ADDR;
                end
            end

            W_ADDR: begin
                axil.aw_ready = 1'b1;
                if (axil.aw_valid) begin
                    write_state_next = W_RESP;
                end
            end

            W_DATA: begin
                axil.w_ready = 1'b1;
                if (axil.w_valid) begin
                    write_state_next = W_RESP;
                end
            end

            W_RESP: begin
                // Execute write to AES core
                if (addr_valid && data_valid) begin
                    write_active = 1'b1;
                    write_addr = awaddr_reg[7:0];
                    write_data_internal = wdata_reg;
                    b_chan.resp = axi_pkg::RESP_OKAY;
                end else begin
                    b_chan.resp = axi_pkg::RESP_SLVERR;
                end
                
                axil.b_valid = 1'b1;
                if (axil.b_ready) begin
                    write_state_next = W_IDLE;
                end
            end
        endcase
    end

    //----------------------------------------------------------------
    // Read FSM
    //----------------------------------------------------------------
    always_comb begin
        // Default values
        read_state_next = read_state;
        axil.ar_ready = 1'b0;
        axil.r_valid  = 1'b0;
        r_chan.data   = '0;
        r_chan.resp   = axi_pkg::RESP_OKAY;
        
        // Internal read control
        read_active = 1'b0;
        read_addr = 8'h00;

        case (read_state)
            R_IDLE: begin
                axil.ar_ready = 1'b1;
                if (axil.ar_valid) begin
                    read_state_next = R_DATA;
                end
            end

            R_DATA: begin
                // Execute read from AES core
                if (addr_is_valid(araddr_reg)) begin
                    read_active = 1'b1;
                    read_addr = araddr_reg[7:0];
                    
                    r_chan.data = aes_read_data;
                    r_chan.resp = axi_pkg::RESP_OKAY;
                end else begin
                    r_chan.data = '0;
                    r_chan.resp = axi_pkg::RESP_SLVERR;
                end
                
                axil.r_valid = 1'b1;
                if (axil.r_ready) begin
                    read_state_next = R_IDLE;
                end
            end
        endcase
    end

    //----------------------------------------------------------------
    // AES Core signal multiplexing
    //----------------------------------------------------------------
    always_comb begin
        if (write_active) begin
            // Write has priority
            aes_cs = 1'b1;
            aes_we = 1'b1;
            aes_address = write_addr;
            aes_write_data = write_data_internal;
        end else if (read_active) begin
            // Read when no write
            aes_cs = 1'b1;
            aes_we = 1'b0;
            aes_address = read_addr;
            aes_write_data = '0;
        end else begin
            // Inactive by default
            aes_cs = 1'b0;
            aes_we = 1'b0;
            aes_address = 8'h00;
            aes_write_data = '0;
        end
    end

endmodule

//======================================================================
// EOF adam_axil_aes.sv
//======================================================================