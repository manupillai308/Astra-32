module mmio_led #(
  parameter LED_WIDTH = 3
)(
  input  logic                 clk,
  input  logic                 reset_n,
  input  logic                 req,
  input  logic                 wr_en,
  input  logic [31:0]          wr_data,
  output logic [31:0]          rd_data,
  output logic [LED_WIDTH-1:0] led
);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    led     <= '0;
    rd_data <= 32'h0;
  end else begin
    if (req && wr_en) begin
      led <= wr_data[LED_WIDTH-1:0];
    end

    if (req && !wr_en) begin
      rd_data <= {{(32-LED_WIDTH){1'b0}}, led}; // zero-extend
    end
  end
end

endmodule
