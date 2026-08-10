module mmio_uart #(
    parameter int CLK_HZ = 12_000_000,
    parameter int BAUD = 115_200
)(
    input logic clk,
    input logic reset_n,

    input logic req,
    input logic wr_en,
    input logic [31:0] addr,
    input logic [31:0] wr_data,
    output logic [31:0] rd_data,
    output logic busy,

    input logic uart_rx,
    output logic uart_tx
);

localparam logic [3:0] TXDATA_OFFSET = 4'h0;
localparam logic [3:0] STATUS_OFFSET = 4'h8;
localparam int CLKS_PER_BIT = CLK_HZ / BAUD;
localparam int BAUD_COUNTER_WIDTH = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

logic [9:0] tx_shift;
logic [3:0] tx_bits_remaining;
logic [BAUD_COUNTER_WIDTH-1:0] baud_counter;
logic rx_sync_1;
logic rx_sync_2;

wire tx_ready = (tx_bits_remaining == 4'd0);
wire tx_start = req && wr_en && tx_ready && (addr[3:0] == TXDATA_OFFSET);
wire read_start = req && !wr_en;

assign busy = read_start;

assign uart_tx = tx_ready ? 1'b1 : tx_shift[0]; // idle and shift is combinational but value changes in sync

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
            STATUS_OFFSET: rd_data <= {31'h0, tx_ready};
            default: rd_data <= 32'h0;
        endcase
    end
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        tx_shift <= 10'h3ff;
        tx_bits_remaining <= 4'd0;
        baud_counter <= '0;
    end else if (tx_start) begin
        tx_shift <= {1'b1, wr_data[7:0], 1'b0};
        tx_bits_remaining <= 4'd10;
        baud_counter <= '0;
    end else if (!tx_ready) begin
        if (baud_counter == CLKS_PER_BIT - 1) begin
            tx_shift <= {1'b1, tx_shift[9:1]};
            tx_bits_remaining <= tx_bits_remaining - 1'b1;
            baud_counter <= '0;
        end else begin
            baud_counter <= baud_counter + 1'b1;
        end
    end
end
endmodule
