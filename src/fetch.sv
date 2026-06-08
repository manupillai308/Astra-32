module fetch (
    input logic clk,
    input logic reset_n,

    input logic [31:0] pc, // program counter input

    output logic imem_req, // instruction memory request
    output logic [31:0] imem_addr, // address to instruction memory

    input logic [31:0] imem_data, // data read from memory
    output logic [31:0] instruction // decoded instruction
);

logic req_reg;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        req_reg <= 1'b0;
    else
        req_reg <= 1'b1; // start instruction fetch after reset
end

assign imem_req = req_reg;
assign imem_addr = pc;
assign instruction = imem_data;

endmodule