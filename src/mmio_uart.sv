module mmio_uart #(
    parameter int CLK_HZ = 12_000_000,
    parameter int BAUD = 115_200,
    parameter int RX_FIFO_DEPTH = 16
)(
    input logic clk,
    input logic reset_n,

    input logic req,
    input logic wr_en,
    input logic [31:0] addr,
    input logic [31:0] wr_data,
    output logic [31:0] rd_data,
    output logic busy,
    output logic irq,

    input logic uart_rx,
    output logic uart_tx
);

localparam logic [3:0] TXDATA_OFFSET = 4'h0;
localparam logic [3:0] RXDATA_OFFSET = 4'h4;
localparam logic [3:0] STATUS_OFFSET = 4'h8;
localparam logic [3:0] CONTROL_OFFSET = 4'hc;
localparam int CLKS_PER_BIT = CLK_HZ / BAUD;
localparam int HALF_CLKS_PER_BIT = CLKS_PER_BIT / 2;
localparam int BAUD_COUNTER_WIDTH = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);
localparam int RX_FIFO_PTR_WIDTH = (RX_FIFO_DEPTH <= 1) ? 1 : $clog2(RX_FIFO_DEPTH);
localparam int RX_FIFO_COUNT_WIDTH = $clog2(RX_FIFO_DEPTH + 1);

typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
} rx_state_t;

logic [9:0] tx_shift;
logic [3:0] tx_bits_remaining;
logic [BAUD_COUNTER_WIDTH-1:0] tx_baud_counter;
logic rx_sync_1;
logic rx_sync_2;
rx_state_t rx_state_q;
logic [BAUD_COUNTER_WIDTH-1:0] rx_baud_counter_q;
logic [2:0] rx_bit_index_q;
logic [7:0] rx_shift_q;
logic [7:0] rx_fifo [0:RX_FIFO_DEPTH-1];
logic [RX_FIFO_PTR_WIDTH-1:0] rx_read_ptr_q;
logic [RX_FIFO_PTR_WIDTH-1:0] rx_write_ptr_q;
logic [RX_FIFO_COUNT_WIDTH-1:0] rx_count_q;
logic rx_irq_enable_q;
logic rx_overrun_q;
logic rx_framing_error_q;

wire tx_ready = (tx_bits_remaining == 4'd0);
wire rx_available = (rx_count_q != 0);
wire rx_full = (rx_count_q == RX_FIFO_DEPTH);
wire tx_start = req && wr_en && tx_ready && (addr[3:0] == TXDATA_OFFSET);
wire rx_pop = req && !wr_en && (addr[3:0] == RXDATA_OFFSET) && rx_available;
wire read_start = req && !wr_en;
wire rx_stop_sample = (rx_state_q == RX_STOP) &&
                      (rx_baud_counter_q == CLKS_PER_BIT - 1);
wire rx_push = rx_stop_sample && rx_sync_2 && (!rx_full || rx_pop);

assign busy = read_start;
assign irq = rx_irq_enable_q && rx_available;

assign uart_tx = tx_ready ? 1'b1 : tx_shift[0];

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_sync_1 <= 1'b1;
        rx_sync_2 <= 1'b1;
    end else begin
        rx_sync_1 <= uart_rx;
        rx_sync_2 <= rx_sync_1;
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rd_data <= 32'h0;
    end else if (req && !wr_en) begin
        unique case (addr[3:0])
            TXDATA_OFFSET: rd_data <= 32'h0;
            RXDATA_OFFSET: rd_data <= rx_available ?
                                      {24'h0, rx_fifo[rx_read_ptr_q]} : 32'h0;
            STATUS_OFFSET: rd_data <= {27'h0, rx_framing_error_q,
                                      rx_overrun_q, rx_full, rx_available, tx_ready};
            CONTROL_OFFSET: rd_data <= {31'h0, rx_irq_enable_q};
            default: rd_data <= 32'h0;
        endcase
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        tx_shift <= 10'h3ff;
        tx_bits_remaining <= 4'd0;
        tx_baud_counter <= '0;
    end else if (tx_start) begin
        tx_shift <= {1'b1, wr_data[7:0], 1'b0};
        tx_bits_remaining <= 4'd10;
        tx_baud_counter <= '0;
    end else if (!tx_ready) begin
        if (tx_baud_counter == CLKS_PER_BIT - 1) begin
            tx_shift <= {1'b1, tx_shift[9:1]};
            tx_bits_remaining <= tx_bits_remaining - 1'b1;
            tx_baud_counter <= '0;
        end else begin
            tx_baud_counter <= tx_baud_counter + 1'b1;
        end
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_state_q <= RX_IDLE;
        rx_baud_counter_q <= '0;
        rx_bit_index_q <= '0;
        rx_shift_q <= '0;
    end else begin
        unique case (rx_state_q)
            RX_IDLE: begin
                rx_baud_counter_q <= '0;
                if (!rx_sync_2) begin
                    rx_state_q <= RX_START;
                end
            end

            RX_START: begin
                if (rx_baud_counter_q == HALF_CLKS_PER_BIT - 1) begin
                    rx_baud_counter_q <= '0;
                    if (!rx_sync_2) begin
                        rx_bit_index_q <= '0;
                        rx_state_q <= RX_DATA;
                    end else begin
                        rx_state_q <= RX_IDLE;
                    end
                end else begin
                    rx_baud_counter_q <= rx_baud_counter_q + 1'b1;
                end
            end

            RX_DATA: begin
                if (rx_baud_counter_q == CLKS_PER_BIT - 1) begin
                    rx_baud_counter_q <= '0;
                    rx_shift_q[rx_bit_index_q] <= rx_sync_2;
                    if (rx_bit_index_q == 3'd7) begin
                        rx_state_q <= RX_STOP;
                    end else begin
                        rx_bit_index_q <= rx_bit_index_q + 1'b1;
                    end
                end else begin
                    rx_baud_counter_q <= rx_baud_counter_q + 1'b1;
                end
            end

            RX_STOP: begin
                if (rx_stop_sample) begin
                    rx_baud_counter_q <= '0;
                    rx_state_q <= RX_IDLE;
                end else begin
                    rx_baud_counter_q <= rx_baud_counter_q + 1'b1;
                end
            end

            default: rx_state_q <= RX_IDLE;
        endcase
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rx_read_ptr_q <= '0;
        rx_write_ptr_q <= '0;
        rx_count_q <= '0;
        rx_irq_enable_q <= 1'b0;
        rx_overrun_q <= 1'b0;
        rx_framing_error_q <= 1'b0;
    end else begin
        if (req && wr_en && (addr[3:0] == CONTROL_OFFSET)) begin
            rx_irq_enable_q <= wr_data[0];
        end

        if (req && wr_en && (addr[3:0] == STATUS_OFFSET)) begin
            if (wr_data[3]) rx_overrun_q <= 1'b0;
            if (wr_data[4]) rx_framing_error_q <= 1'b0;
        end

        if (rx_stop_sample && !rx_sync_2) begin
            rx_framing_error_q <= 1'b1;
        end
        if (rx_stop_sample && rx_sync_2 && rx_full && !rx_pop) begin
            rx_overrun_q <= 1'b1;
        end

        if (rx_push) begin
            rx_fifo[rx_write_ptr_q] <= rx_shift_q;
            rx_write_ptr_q <= (rx_write_ptr_q == RX_FIFO_DEPTH - 1) ?
                              '0 : rx_write_ptr_q + 1'b1;
        end
        if (rx_pop) begin
            rx_read_ptr_q <= (rx_read_ptr_q == RX_FIFO_DEPTH - 1) ?
                             '0 : rx_read_ptr_q + 1'b1;
        end

        unique case ({rx_push, rx_pop})
            2'b10: rx_count_q <= rx_count_q + 1'b1;
            2'b01: rx_count_q <= rx_count_q - 1'b1;
            default: begin
            end
        endcase
    end
end
endmodule
