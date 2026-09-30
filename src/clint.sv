module clint #(
  parameter logic [31:0] BASE_ADDR = 32'h0200_0000
)(
  input  logic        clk,
  input  logic        reset_n,

  input  logic        req,
  input  logic        wr_en,
  input  logic [31:0] addr,
  input  logic [31:0] wr_data,
  output logic [31:0] rd_data,
  output logic        busy,

  output logic        msip,
  output logic        mtip,
  output logic [63:0] mtime
);

localparam logic [31:0] MSIP_ADDR        = BASE_ADDR + 32'h0000_0000;
localparam logic [31:0] MTIMECMP_LO_ADDR = BASE_ADDR + 32'h0000_4000;
localparam logic [31:0] MTIMECMP_HI_ADDR = BASE_ADDR + 32'h0000_4004;
localparam logic [31:0] MTIME_LO_ADDR    = BASE_ADDR + 32'h0000_BFF8;
localparam logic [31:0] MTIME_HI_ADDR    = BASE_ADDR + 32'h0000_BFFC;

logic        msip_q;
logic [63:0] mtime_q;
logic [63:0] mtimecmp_q;

assign busy = req && !wr_en;
assign msip = msip_q;
assign mtip = (mtime_q >= mtimecmp_q);
assign mtime = mtime_q;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    msip_q <= 1'b0;
    mtime_q <= 64'h0;
    mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
    rd_data <= 32'h0;
  end else begin
    mtime_q <= mtime_q + 1'b1;

    if (req && wr_en) begin
      unique case (addr)
        MSIP_ADDR:        msip_q <= wr_data[0];
        MTIMECMP_LO_ADDR: mtimecmp_q <= {mtimecmp_q[63:32], wr_data};
        MTIMECMP_HI_ADDR: mtimecmp_q <= {wr_data, mtimecmp_q[31:0]};
        MTIME_LO_ADDR:    mtime_q <= {mtime_q[63:32], wr_data};
        MTIME_HI_ADDR:    mtime_q <= {wr_data, mtime_q[31:0]};
        default: begin
        end
      endcase
    end

    if (req && !wr_en) begin
      unique case (addr)
        MSIP_ADDR:        rd_data <= {31'h0, msip_q};
        MTIMECMP_LO_ADDR: rd_data <= mtimecmp_q[31:0];
        MTIMECMP_HI_ADDR: rd_data <= mtimecmp_q[63:32];
        MTIME_LO_ADDR:    rd_data <= mtime_q[31:0];
        MTIME_HI_ADDR:    rd_data <= mtime_q[63:32];
        default:          rd_data <= 32'h0;
      endcase
    end
  end
end

endmodule
