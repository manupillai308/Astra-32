module plic #(
  parameter logic [31:0] BASE_ADDR = 32'h0c00_0000,
  parameter int SOURCE_COUNT = 8,
  parameter int PRIORITY_WIDTH = 3
)(
  input  logic                    clk,
  input  logic                    reset_n,

  input  logic                    req,
  input  logic                    wr_en,
  input  logic [31:0]             addr,
  input  logic [31:0]             wr_data,
  output logic [31:0]             rd_data,
  output logic                    busy,

  input  logic [SOURCE_COUNT-1:0] source_irq,
  output logic                    meip,
  output logic                    seip
);

localparam int SOURCE_ID_WIDTH = (SOURCE_COUNT <= 1) ? 1 :
                                 $clog2(SOURCE_COUNT + 1);

localparam logic [31:0] PENDING_ADDR = BASE_ADDR + 32'h0000_1000;
localparam logic [31:0] M_ENABLE_ADDR = BASE_ADDR + 32'h0000_2000;
localparam logic [31:0] S_ENABLE_ADDR = BASE_ADDR + 32'h0000_2080;
localparam logic [31:0] M_THRESHOLD_ADDR = BASE_ADDR + 32'h0020_0000;
localparam logic [31:0] M_CLAIM_ADDR = BASE_ADDR + 32'h0020_0004;
localparam logic [31:0] S_THRESHOLD_ADDR = BASE_ADDR + 32'h0020_1000;
localparam logic [31:0] S_CLAIM_ADDR = BASE_ADDR + 32'h0020_1004;

logic [PRIORITY_WIDTH-1:0] priority_q [1:SOURCE_COUNT];
logic [SOURCE_COUNT:1] pending_q;
logic [SOURCE_COUNT:1] claimed_q;
logic [SOURCE_COUNT:1] claimed_by_supervisor_q;
logic [SOURCE_COUNT:1] machine_enable_q;
logic [SOURCE_COUNT:1] supervisor_enable_q;
logic [PRIORITY_WIDTH-1:0] machine_threshold_q;
logic [PRIORITY_WIDTH-1:0] supervisor_threshold_q;

logic [SOURCE_ID_WIDTH-1:0] machine_claim_id;
logic [SOURCE_ID_WIDTH-1:0] supervisor_claim_id;
logic [PRIORITY_WIDTH-1:0] machine_claim_priority;
logic [PRIORITY_WIDTH-1:0] supervisor_claim_priority;
logic [31:0] pending_word;
logic [31:0] machine_enable_word;
logic [31:0] supervisor_enable_word;
logic priority_addr_valid;
logic [31:0] priority_source_id;

integer pack_index;
integer claim_index;
integer sequential_index;

assign busy = req && !wr_en;
assign priority_source_id = (addr - BASE_ADDR) >> 2;
assign priority_addr_valid = (addr > BASE_ADDR) &&
                             (priority_source_id <= SOURCE_COUNT) &&
                             (addr[1:0] == 2'b00);

always_comb begin
  pending_word = 32'h0;
  machine_enable_word = 32'h0;
  supervisor_enable_word = 32'h0;

  for (pack_index = 1; pack_index <= SOURCE_COUNT;
       pack_index = pack_index + 1) begin
    pending_word[pack_index] = pending_q[pack_index];
    machine_enable_word[pack_index] = machine_enable_q[pack_index];
    supervisor_enable_word[pack_index] = supervisor_enable_q[pack_index];
  end
end

always_comb begin
  machine_claim_id = '0;
  machine_claim_priority = '0;
  supervisor_claim_id = '0;
  supervisor_claim_priority = '0;

  for (claim_index = 1; claim_index <= SOURCE_COUNT;
       claim_index = claim_index + 1) begin
    if (pending_q[claim_index] && machine_enable_q[claim_index] &&
        (priority_q[claim_index] > machine_threshold_q) &&
        ((machine_claim_id == '0) ||
         (priority_q[claim_index] > machine_claim_priority))) begin
      machine_claim_id = claim_index[SOURCE_ID_WIDTH-1:0];
      machine_claim_priority = priority_q[claim_index];
    end

    if (pending_q[claim_index] && supervisor_enable_q[claim_index] &&
        (priority_q[claim_index] > supervisor_threshold_q) &&
        ((supervisor_claim_id == '0) ||
         (priority_q[claim_index] > supervisor_claim_priority))) begin
      supervisor_claim_id = claim_index[SOURCE_ID_WIDTH-1:0];
      supervisor_claim_priority = priority_q[claim_index];
    end
  end
end

assign meip = (machine_claim_id != '0);
assign seip = (supervisor_claim_id != '0);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    rd_data <= 32'h0;
    pending_q <= '0;
    claimed_q <= '0;
    claimed_by_supervisor_q <= '0;
    machine_enable_q <= '0;
    supervisor_enable_q <= '0;
    machine_threshold_q <= '0;
    supervisor_threshold_q <= '0;

    for (sequential_index = 1; sequential_index <= SOURCE_COUNT;
         sequential_index = sequential_index + 1) begin
      priority_q[sequential_index] <= '0;
    end
  end else begin
    // A gateway holds one request until software claims and completes it.
    for (sequential_index = 1; sequential_index <= SOURCE_COUNT;
         sequential_index = sequential_index + 1) begin
      if (!pending_q[sequential_index] && !claimed_q[sequential_index] &&
          source_irq[sequential_index - 1]) begin
        pending_q[sequential_index] <= 1'b1;
      end
    end

    if (req && wr_en) begin
      if (priority_addr_valid) begin
        priority_q[priority_source_id] <= wr_data[PRIORITY_WIDTH-1:0];
      end else begin
        unique case (addr)
          M_ENABLE_ADDR: begin
            for (sequential_index = 1; sequential_index <= SOURCE_COUNT;
                 sequential_index = sequential_index + 1) begin
              machine_enable_q[sequential_index] <= wr_data[sequential_index];
            end
          end
          S_ENABLE_ADDR: begin
            for (sequential_index = 1; sequential_index <= SOURCE_COUNT;
                 sequential_index = sequential_index + 1) begin
              supervisor_enable_q[sequential_index] <= wr_data[sequential_index];
            end
          end
          M_THRESHOLD_ADDR:
            machine_threshold_q <= wr_data[PRIORITY_WIDTH-1:0];
          S_THRESHOLD_ADDR:
            supervisor_threshold_q <= wr_data[PRIORITY_WIDTH-1:0];
          M_CLAIM_ADDR: begin
            if ((wr_data > 0) && (wr_data <= SOURCE_COUNT)) begin
              if (claimed_q[wr_data] &&
                  !claimed_by_supervisor_q[wr_data]) begin
                claimed_q[wr_data] <= 1'b0;
              end
            end
          end
          S_CLAIM_ADDR: begin
            if ((wr_data > 0) && (wr_data <= SOURCE_COUNT)) begin
              if (claimed_q[wr_data] &&
                  claimed_by_supervisor_q[wr_data]) begin
                claimed_q[wr_data] <= 1'b0;
              end
            end
          end
          default: begin
          end
        endcase
      end
    end

    if (req && !wr_en) begin
      if (priority_addr_valid) begin
        rd_data <= {{(32-PRIORITY_WIDTH){1'b0}},
                    priority_q[priority_source_id]};
      end else begin
        unique case (addr)
          PENDING_ADDR: rd_data <= pending_word;
          M_ENABLE_ADDR: rd_data <= machine_enable_word;
          S_ENABLE_ADDR: rd_data <= supervisor_enable_word;
          M_THRESHOLD_ADDR:
            rd_data <= {{(32-PRIORITY_WIDTH){1'b0}}, machine_threshold_q};
          S_THRESHOLD_ADDR:
            rd_data <= {{(32-PRIORITY_WIDTH){1'b0}}, supervisor_threshold_q};
          M_CLAIM_ADDR: begin
            rd_data <= {{(32-SOURCE_ID_WIDTH){1'b0}}, machine_claim_id};
            if (machine_claim_id != '0) begin
              pending_q[machine_claim_id] <= 1'b0;
              claimed_q[machine_claim_id] <= 1'b1;
              claimed_by_supervisor_q[machine_claim_id] <= 1'b0;
            end
          end
          S_CLAIM_ADDR: begin
            rd_data <= {{(32-SOURCE_ID_WIDTH){1'b0}}, supervisor_claim_id};
            if (supervisor_claim_id != '0) begin
              pending_q[supervisor_claim_id] <= 1'b0;
              claimed_q[supervisor_claim_id] <= 1'b1;
              claimed_by_supervisor_q[supervisor_claim_id] <= 1'b1;
            end
          end
          default: rd_data <= 32'h0;
        endcase
      end
    end
  end
end

endmodule
