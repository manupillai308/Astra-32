// --------------------------------------------------------
// Data Memory - RTL (Refined, Parameterized)
// --------------------------------------------------------

import risc_pkg::*;

module data_memory #(
  parameter ADDR_WIDTH = 6  // byte address bits: 2^6 = 64 bytes
)(
  input logic 				  clk,
  input  logic                dmem_req,                 
  input  logic                dmem_wr_en,               
  input mem_size_t		      dmem_data_size,           
  input  logic [31:0]         dmem_addr,                
  input  logic [31:0]         dmem_wr_data,             
  input  logic                dmem_zero_extend,         

  output logic [31:0]         dmem_rd_data              
);

// --------------------------------------------------------
// RAM Declaration
// --------------------------------------------------------
localparam int WORD_ADDR_WIDTH = ADDR_WIDTH - 2;

logic [31:0] mem [0:(2**WORD_ADDR_WIDTH)-1];
logic [WORD_ADDR_WIDTH-1:0] word_addr;
logic [1:0] byte_offset;

assign word_addr = dmem_addr[ADDR_WIDTH-1:2];
assign byte_offset = dmem_addr[1:0]; // which byte in that index (notice 4 bytes per index)

// write logic - store

always_ff @ (posedge clk) begin
  if (dmem_req && dmem_wr_en) begin
    case (dmem_data_size)
      BYTE: begin
        case (byte_offset)
          2'b00: mem[word_addr][7:0] <= dmem_wr_data[7:0];
          2'b01: mem[word_addr][15:8] <= dmem_wr_data[7:0];
          2'b10: mem[word_addr][23:16] <= dmem_wr_data[7:0];
          default: mem[word_addr][31:24] <= dmem_wr_data[7:0];
        endcase
      end
      HALF_WORD: begin // RISC RV32I is aligned, div by 2 for HALF_WORD, div by 4 for WORD
        if (byte_offset == 2'b00) mem[word_addr][15:0] <= dmem_wr_data[15:0];
        else if (byte_offset == 2'b10) mem[word_addr][31:16] <= dmem_wr_data[15:0];
      end
      WORD: begin
        if (byte_offset == 2'b00) mem[word_addr] <= dmem_wr_data;
      end
    endcase
  end
end

// read logic - load (synchronous; matches BRAM read-port semantics)
// Output reg holds last loaded value across cycles where no read is issued,
// so MEM-stage data is still on dmem_rd_data when WB consumes it next cycle.
always_ff @(posedge clk) begin
  if (dmem_req && !dmem_wr_en) begin
    case (dmem_data_size)
      BYTE: begin
        case (byte_offset)
          2'b00: dmem_rd_data <= dmem_zero_extend ? {24'h0, mem[word_addr][7:0]} : {{24{mem[word_addr][7]}}, mem[word_addr][7:0]};
          2'b01: dmem_rd_data <= dmem_zero_extend ? {24'h0, mem[word_addr][15:8]} : {{24{mem[word_addr][15]}}, mem[word_addr][15:8]};
          2'b10: dmem_rd_data <= dmem_zero_extend ? {24'h0, mem[word_addr][23:16]} : {{24{mem[word_addr][23]}}, mem[word_addr][23:16]};
          default: dmem_rd_data <= dmem_zero_extend ? {24'h0, mem[word_addr][31:24]} : {{24{mem[word_addr][31]}}, mem[word_addr][31:24]};
        endcase
      end
      HALF_WORD: dmem_rd_data <= dmem_zero_extend ? 
      (byte_offset[1] ? {16'h0, mem[word_addr][31:16]} : {16'h0, mem[word_addr][15:0]}) 
      : (byte_offset[1] ? {{16{mem[word_addr][31]}}, mem[word_addr][31:16]} : {{16{mem[word_addr][15]}}, mem[word_addr][15:0]});
      WORD: dmem_rd_data <= mem[word_addr];
    endcase
  end
end

endmodule
