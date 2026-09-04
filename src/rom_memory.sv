import risc_pkg::*;

module rom_memory #(
    parameter ADDR_WIDTH = 12 // byte address bits
)(
    input  logic        clk,
    input  logic        req,         // 1 = perform read this cycle
    input  mem_size_t   data_size,
    input  logic [31:0] addr,        // byte address
    input  logic        zero_extend,
    output logic [31:0] rd_data      // valid one cycle after req
);

localparam int WORD_ADDR_WIDTH = ADDR_WIDTH - 2;

logic [31:0] mem [0:(2**WORD_ADDR_WIDTH)-1];
logic [31:0] ram_rd_data;
logic [1:0] ram_byte_offset;
mem_size_t ram_data_size;
logic ram_zero_extend;

// Simulation can override the program with +PROGRAM=<path>. Synthesis uses a
// fixed file so Vivado can infer initialized FPGA memory.
initial begin
`ifndef SYNTHESIS
    string program_path;
    if (!$value$plusargs("PROGRAM=%s", program_path))
        program_path = "machine_code.mem";
    $readmemh(program_path, mem);
`else
    $readmemh("machine_code.mem", mem);
`endif
end

// Synchronous read: 1-cycle latency. Required to infer BRAM on FPGA.
// rd_data is only updated when req is asserted, so the captured
// instruction stays valid across stall cycles in the front-half of the pipe.
always_ff @(posedge clk) begin
    if (req) begin
        ram_rd_data <= mem[addr[ADDR_WIDTH-1:2]];
        ram_byte_offset <= addr[1:0];
        ram_data_size <= data_size;
        ram_zero_extend <= zero_extend;
    end
end

always_comb begin
    unique case (ram_data_size)
        BYTE: begin
            unique case (ram_byte_offset)
                2'b00: rd_data = ram_zero_extend ? {24'h0, ram_rd_data[7:0]} : {{24{ram_rd_data[7]}}, ram_rd_data[7:0]};
                2'b01: rd_data = ram_zero_extend ? {24'h0, ram_rd_data[15:8]} : {{24{ram_rd_data[15]}}, ram_rd_data[15:8]};
                2'b10: rd_data = ram_zero_extend ? {24'h0, ram_rd_data[23:16]} : {{24{ram_rd_data[23]}}, ram_rd_data[23:16]};
                default: rd_data = ram_zero_extend ? {24'h0, ram_rd_data[31:24]} : {{24{ram_rd_data[31]}}, ram_rd_data[31:24]};
            endcase
        end
        HALF_WORD: begin
            rd_data = ram_zero_extend ?
                (ram_byte_offset[1] ? {16'h0, ram_rd_data[31:16]} : {16'h0, ram_rd_data[15:0]}) :
                (ram_byte_offset[1] ? {{16{ram_rd_data[31]}}, ram_rd_data[31:16]} : {{16{ram_rd_data[15]}}, ram_rd_data[15:0]});
        end
        WORD: rd_data = ram_rd_data;
        default: rd_data = ram_rd_data;
    endcase
end

endmodule
