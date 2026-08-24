// --------------------------------------------------------
// DDR Memory Adapter - CPU clock to MIG ui_clk bridge
// --------------------------------------------------------

import risc_pkg::*;

module ddr_memory (
  input  logic        cpu_clk,
  input  logic        cpu_reset_n,

  input  logic        ui_clk,
  input  logic        ui_reset_n,

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

localparam logic [2:0] MIG_CMD_WRITE = 3'b000;
localparam logic [2:0] MIG_CMD_READ  = 3'b001;

typedef enum logic [3:0] {
  ST_IDLE,
  ST_CAPTURE_REQ,
  ST_DISPATCH,
  ST_LAUNCH_WRITE,
  ST_WAIT_WRITE,
  ST_LAUNCH_READ,
  ST_WAIT_READ_CMD,
  ST_WAIT_READ_DATA,
  ST_DONE
} state_t;

state_t state_q;

mem_size_t   req_data_size_cpu;
logic [31:0] req_addr_cpu;
logic [31:0] req_wr_data_cpu;
logic        req_zero_extend_cpu;
logic        req_wr_en_cpu;
logic        req_toggle_cpu;
logic        busy_cpu;
logic [31:0] rd_data_cpu;

(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
logic [1:0]  resp_toggle_sync_cpu;
logic        resp_toggle_seen_cpu;

(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
logic [1:0]  req_toggle_sync_ui;
logic        req_toggle_seen_ui;
logic        resp_toggle_ui;
logic [31:0] resp_data_ui;

mem_size_t   req_data_size_ui;
logic [31:0] req_addr_ui;
logic [31:0] req_wr_data_ui;
logic        req_zero_extend_ui;
logic        req_wr_en_ui;

logic [127:0] rd_line_q;
logic [7:0]   rd_byte_data;
logic [15:0]  rd_half_data;
logic [31:0]  rd_word_data;
logic         read_beat_q;
logic         read_cmd_done_q;

logic [127:0] wr_line_data;
logic [15:0]  wr_line_mask;
logic         write_cmd_done_q;
logic         write_second_beat_q;
logic         write_data_done_q;

assign dmem_busy = dmem_req || busy_cpu;
assign dmem_rd_data = rd_data_cpu;

always_ff @(posedge cpu_clk or negedge cpu_reset_n) begin
  if (!cpu_reset_n) begin
    busy_cpu <= 1'b0;
    req_data_size_cpu <= WORD;
    req_addr_cpu <= 32'h0;
    req_wr_data_cpu <= 32'h0;
    req_zero_extend_cpu <= 1'b0;
    req_wr_en_cpu <= 1'b0;
    req_toggle_cpu <= 1'b0;
    resp_toggle_sync_cpu <= 2'b00;
    resp_toggle_seen_cpu <= 1'b0;
    rd_data_cpu <= 32'h0;
  end else begin
    resp_toggle_sync_cpu <= {resp_toggle_sync_cpu[0], resp_toggle_ui};

    if (resp_toggle_sync_cpu[1] != resp_toggle_seen_cpu) begin
      resp_toggle_seen_cpu <= resp_toggle_sync_cpu[1];
      rd_data_cpu <= resp_data_ui;
      busy_cpu <= 1'b0;
    end

    if (!busy_cpu && dmem_req) begin
      req_data_size_cpu <= dmem_data_size;
      req_addr_cpu <= dmem_addr;
      req_wr_data_cpu <= dmem_wr_data;
      req_zero_extend_cpu <= dmem_zero_extend;
      req_wr_en_cpu <= dmem_wr_en;
      busy_cpu <= 1'b1;
      req_toggle_cpu <= ~req_toggle_cpu;
    end
  end
end

always_ff @(posedge ui_clk or negedge ui_reset_n) begin
  if (!ui_reset_n) begin
    state_q <= ST_IDLE;

    req_toggle_sync_ui <= 2'b00;
    req_toggle_seen_ui <= 1'b0;
    resp_toggle_ui <= 1'b0;
    resp_data_ui <= 32'h0;

    req_data_size_ui <= WORD;
    req_addr_ui <= 32'h0;
    req_wr_data_ui <= 32'h0;
    req_zero_extend_ui <= 1'b0;
    req_wr_en_ui <= 1'b0;

    rd_line_q <= 128'h0;
    read_beat_q <= 1'b0;
    read_cmd_done_q <= 1'b0;

    write_cmd_done_q <= 1'b0;
    write_second_beat_q <= 1'b0;
    write_data_done_q <= 1'b0;

    app_addr <= 28'h0;
    app_cmd <= MIG_CMD_READ;
    app_en <= 1'b0;
    app_wdf_data <= 64'h0;
    app_wdf_end <= 1'b0;
    app_wdf_mask <= 8'hff;
    app_wdf_wren <= 1'b0;
  end else begin
    req_toggle_sync_ui <= {req_toggle_sync_ui[0], req_toggle_cpu};

    unique case (state_q)
      ST_IDLE: begin
        app_en <= 1'b0;
        app_wdf_wren <= 1'b0;
        app_wdf_end <= 1'b0;
        app_wdf_mask <= 8'hff;
        read_beat_q <= 1'b0;
        write_cmd_done_q <= 1'b0;
        write_second_beat_q <= 1'b0;
        write_data_done_q <= 1'b0;

        if (req_toggle_sync_ui[1] != req_toggle_seen_ui) begin
          req_toggle_seen_ui <= req_toggle_sync_ui[1];
          state_q <= ST_CAPTURE_REQ;
        end
      end

      ST_CAPTURE_REQ: begin
        req_data_size_ui <= req_data_size_cpu;
        req_addr_ui <= req_addr_cpu;
        req_wr_data_ui <= req_wr_data_cpu;
        req_zero_extend_ui <= req_zero_extend_cpu;
        req_wr_en_ui <= req_wr_en_cpu;

        state_q <= ST_DISPATCH;
      end

      ST_DISPATCH: begin
        state_q <= req_wr_en_ui ? ST_LAUNCH_WRITE : ST_LAUNCH_READ;
      end

      ST_LAUNCH_WRITE: begin
        app_addr <= dmem_addr_to_app_addr(req_addr_ui);
        app_cmd <= MIG_CMD_WRITE;
        app_en <= 1'b1;
        app_wdf_data <= wr_line_data[63:0];
        app_wdf_mask <= wr_line_mask[7:0];
        app_wdf_wren <= 1'b1;
        app_wdf_end <= 1'b0;

        write_cmd_done_q <= 1'b0;
        write_second_beat_q <= 1'b0;
        write_data_done_q <= 1'b0;
        state_q <= ST_WAIT_WRITE;
      end

      ST_WAIT_WRITE: begin
        if (app_en && app_rdy) begin
          app_en <= 1'b0;
          write_cmd_done_q <= 1'b1;
        end

        if (app_wdf_wren && app_wdf_rdy) begin
          if (!write_second_beat_q) begin
            app_wdf_data <= wr_line_data[127:64];
            app_wdf_mask <= wr_line_mask[15:8];
            app_wdf_end <= 1'b1;
            write_second_beat_q <= 1'b1;
          end else begin
            app_wdf_wren <= 1'b0;
            app_wdf_end <= 1'b0;
            app_wdf_mask <= 8'hff;
            write_data_done_q <= 1'b1;
          end
        end

        if (write_cmd_done_q && write_data_done_q) begin
          state_q <= ST_DONE;
        end
      end

      ST_LAUNCH_READ: begin
        app_addr <= dmem_addr_to_app_addr(req_addr_ui);
        app_cmd <= MIG_CMD_READ;
        app_en <= 1'b1;
        app_wdf_wren <= 1'b0;
        app_wdf_end <= 1'b0;
        app_wdf_mask <= 8'hff;
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
        resp_data_ui <= req_wr_en_ui ? 32'h0 : dmem_rd_data_ui();
        resp_toggle_ui <= ~resp_toggle_ui;
        state_q <= ST_IDLE;
      end

      default: begin
        app_en <= 1'b0;
        app_wdf_wren <= 1'b0;
        app_wdf_end <= 1'b0;
        app_wdf_mask <= 8'hff;
        state_q <= ST_IDLE;
      end
    endcase
  end
end

always_comb begin
  wr_line_data = 128'h0;
  wr_line_mask = 16'hffff;

  unique case (req_data_size_ui)
    BYTE: begin
      // wr_line_data[start_index +: width] = wr_line_data[start_index + width - 1 : start_index]
      wr_line_data[8 * req_addr_ui[3:0] +: 8] = req_wr_data_ui[7:0];
      wr_line_mask[req_addr_ui[3:0]] = 1'b0;
    end

    HALF_WORD: begin
      wr_line_data[8 * {req_addr_ui[3:1], 1'b0} +: 16] = req_wr_data_ui[15:0];
      wr_line_mask[{req_addr_ui[3:1], 1'b0} +: 2] = 2'b00;
    end

    WORD: begin
      wr_line_data[8 * {req_addr_ui[3:2], 2'b00} +: 32] = req_wr_data_ui;
      wr_line_mask[{req_addr_ui[3:2], 2'b00} +: 4] = 4'b0000;
    end

    default: begin
      wr_line_data = 128'h0;
      wr_line_mask = 16'hffff;
    end
  endcase
end

// We align down misaligned reads for now; traps can replace this later.
assign rd_byte_data = rd_line_q[8 * req_addr_ui[3:0] +: 8];
assign rd_half_data = rd_line_q[8 * {req_addr_ui[3:1], 1'b0} +: 16];
assign rd_word_data = rd_line_q[8 * {req_addr_ui[3:2], 2'b00} +: 32];

function automatic logic [31:0] dmem_rd_data_ui();
  unique case (req_data_size_ui)
    BYTE: begin
      dmem_rd_data_ui = req_zero_extend_ui ?
        {24'h0, rd_byte_data} :
        {{24{rd_byte_data[7]}}, rd_byte_data};
    end

    HALF_WORD: begin
      dmem_rd_data_ui = req_zero_extend_ui ?
        {16'h0, rd_half_data} :
        {{16{rd_half_data[15]}}, rd_half_data};
    end

    WORD: begin
      dmem_rd_data_ui = rd_word_data;
    end

    default: begin
      dmem_rd_data_ui = 32'h0;
    end
  endcase
endfunction

function automatic logic [27:0] dmem_addr_to_app_addr(input logic [31:0] addr);
  logic [31:0] burst_base_byte_addr;
  begin
    burst_base_byte_addr = addr & 32'hffff_fff0;
    dmem_addr_to_app_addr = burst_base_byte_addr[28:1];
  end
endfunction

endmodule
