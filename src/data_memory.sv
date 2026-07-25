// --------------------------------------------------------
// Data Memory - RTL (Refined, Parameterized)
// --------------------------------------------------------

import risc_pkg::*;

module data_memory #(
  parameter ADDR_WIDTH = 6,  // 2^6 = 64 (insted of 2^16)
  parameter DATA_WIDTH = 8    // Byte-wide RAM
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
logic [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];
logic [ADDR_WIDTH-1:0] ram_addr;

assign ram_addr = dmem_addr[ADDR_WIDTH-1:0];

// write logic - store

always_ff @ (posedge clk) begin
  if (dmem_req && dmem_wr_en) begin
    case (dmem_data_size)
      BYTE: mem[ram_addr] <= dmem_wr_data[7:0]; // SB
      HALF_WORD: {mem[ram_addr+1], mem[ram_addr]} <= dmem_wr_data[15:0]; // SH
      WORD: {mem[ram_addr+3], mem[ram_addr+2], mem[ram_addr+1], mem[ram_addr]} <= dmem_wr_data; //SW
    endcase
  end
end

// read logic - load (synchronous; matches BRAM read-port semantics)
// Output reg holds last loaded value across cycles where no read is issued,
// so MEM-stage data is still on dmem_rd_data when WB consumes it next cycle.
always_ff @(posedge clk) begin
  if (dmem_req && !dmem_wr_en) begin
    case (dmem_data_size)
      BYTE: dmem_rd_data <= dmem_zero_extend ? {{24{1'b0}}, mem[ram_addr]} : {{24{mem[ram_addr][7]}}, mem[ram_addr]};
      HALF_WORD: dmem_rd_data <= dmem_zero_extend ?
                  {{16{1'b0}}, mem[ram_addr+1], mem[ram_addr]} :
                  {{16{mem[ram_addr+1][7]}}, mem[ram_addr+1], mem[ram_addr]};
      WORD: dmem_rd_data <= {mem[ram_addr+3], mem[ram_addr+2], mem[ram_addr+1], mem[ram_addr]};
    endcase
  end
end

endmodule
