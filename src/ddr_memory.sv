// --------------------------------------------------------
// DDR Memory Adapter - MIG read path
// --------------------------------------------------------

import risc_pkg::*;

module ddr_memory (
  input  logic        clk,
  input  logic        reset_n,

  input  logic        dmem_req,
  input  logic        dmem_wr_en,
  input  mem_size_t   dmem_data_size,
  input  logic [31:0] dmem_addr,
  input  logic [31:0] dmem_wr_data,
  input  logic        dmem_zero_extend,

  output logic [31:0] dmem_rd_data,
  output logic        dmem_busy,

  output logic [27:0] app_addr,
  output logic [2:0]  app_cmd,
  output logic        app_en,
  input  logic        app_rdy,

  output logic [63:0] app_wdf_data,
  output logic        app_wdf_end,
  output logic [7:0]  app_wdf_mask,
  output logic        app_wdf_wren,
  input  logic        app_wdf_rdy,

  input  logic [63:0] app_rd_data,
  input  logic        app_rd_data_end,
  input  logic        app_rd_data_valid
);

localparam logic [2:0] MIG_CMD_READ = 3'b001;

typedef enum logic [2:0] {
  ST_IDLE,
  ST_LAUNCH_READ,
  ST_WAIT_READ_CMD,
  ST_WAIT_READ_DATA,
  ST_DONE
} state_t;

state_t state_q;

mem_size_t   req_data_size;
logic [31:0] req_addr;
logic        req_zero_extend;

logic [127:0] rd_line_q;
logic         read_beat_q;
logic         read_cmd_done_q;
logic [31:0] rd_word_data;

assign dmem_busy = dmem_req || (state_q != ST_IDLE);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= ST_IDLE;

    req_data_size <= WORD;
    req_addr <= 32'h0;
    req_zero_extend <= 1'b0;

    rd_line_q <= 128'h0;
    read_beat_q <= 1'b0;
    read_cmd_done_q <= 1'b0;

    app_addr <= 28'h0;
    app_cmd <= MIG_CMD_READ;
    app_en <= 1'b0;

    app_wdf_data <= 64'h0;
    app_wdf_end <= 1'b0;
    app_wdf_mask <= 8'hff;
    app_wdf_wren <= 1'b0;
  end else begin
    app_wdf_data <= 64'h0;
    app_wdf_end <= 1'b0;
    app_wdf_mask <= 8'hff;
    app_wdf_wren <= 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        app_en <= 1'b0;
        read_beat_q <= 1'b0;

        if (dmem_req) begin
          req_data_size <= dmem_data_size;
          req_addr <= dmem_addr;
          req_zero_extend <= dmem_zero_extend;

          if (dmem_wr_en) begin
            state_q <= ST_DONE;
          end else begin
            state_q <= ST_LAUNCH_READ;
          end
        end
      end

      ST_LAUNCH_READ: begin
        app_addr <= dmem_addr_to_app_addr(req_addr);
        app_cmd <= MIG_CMD_READ;
        app_en <= 1'b1;
        read_beat_q <= 1'b0;
        read_cmd_done_q <= 1'b0;
        state_q <= ST_WAIT_READ_CMD;
      end

      ST_WAIT_READ_CMD: begin
        if (app_en && app_rdy) begin
          app_en <= 1'b0;
          read_cmd_done_q <= 1'b1;
        end

        if (read_cmd_done_q) begin
          read_cmd_done_q <= 1'b0;
          state_q <= ST_WAIT_READ_DATA;
        end
      end

      ST_WAIT_READ_DATA: begin
        if (app_rd_data_valid) begin
          if (!read_beat_q) begin
            rd_line_q[63:0] <= app_rd_data;
            read_beat_q <= 1'b1;

            if (app_rd_data_end) begin
              state_q <= ST_DONE;
            end
          end else begin
            rd_line_q[127:64] <= app_rd_data;

            if (app_rd_data_end) begin
              read_beat_q <= 1'b0;
              state_q <= ST_DONE;
            end
          end
        end
      end

      ST_DONE: begin
        state_q <= ST_IDLE;
      end

      default: begin
        app_en <= 1'b0;
        state_q <= ST_IDLE;
      end
    endcase
  end
end

always_comb begin
  unique case (req_addr[3:2])
    2'h0: rd_word_data = rd_line_q[31:0];
    2'h1: rd_word_data = rd_line_q[63:32];
    2'h2: rd_word_data = rd_line_q[95:64];
    2'h3: rd_word_data = rd_line_q[127:96];
    default: rd_word_data = 32'h0;
  endcase
end

always_comb begin
  unique case (req_data_size)
    BYTE: begin
      unique case (req_addr[1:0])
        2'b00: dmem_rd_data = req_zero_extend ? {24'h0, rd_word_data[7:0]} : {{24{rd_word_data[7]}}, rd_word_data[7:0]};
        2'b01: dmem_rd_data = req_zero_extend ? {24'h0, rd_word_data[15:8]} : {{24{rd_word_data[15]}}, rd_word_data[15:8]};
        2'b10: dmem_rd_data = req_zero_extend ? {24'h0, rd_word_data[23:16]} : {{24{rd_word_data[23]}}, rd_word_data[23:16]};
        default: dmem_rd_data = req_zero_extend ? {24'h0, rd_word_data[31:24]} : {{24{rd_word_data[31]}}, rd_word_data[31:24]};
      endcase
    end

    HALF_WORD: begin
      dmem_rd_data = req_zero_extend ?
        (req_addr[1] ? {16'h0, rd_word_data[31:16]} : {16'h0, rd_word_data[15:0]}) :
        (req_addr[1] ? {{16{rd_word_data[31]}}, rd_word_data[31:16]} : {{16{rd_word_data[15]}}, rd_word_data[15:0]});
    end

    WORD: begin
      dmem_rd_data = rd_word_data;
    end

    default: begin
      dmem_rd_data = 32'h0;
    end
  endcase
end

function automatic logic [27:0] dmem_addr_to_app_addr(input logic [31:0] addr);
  logic [31:0] burst_base_byte_addr;
  begin
    burst_base_byte_addr = addr & 32'hffff_fff0;
    dmem_addr_to_app_addr = burst_base_byte_addr[28:1];
  end
endfunction

endmodule
