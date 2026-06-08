module instruction_memory #(
    parameter ADDR_WIDTH = 7, // address bits
    parameter DATA_WIDTH = 8 // data width per memory cell
)(
    input logic imem_req, // read enable
    input logic [31:0] imem_addr, // byte address (word-aligned)
    output logic [31:0] imem_data // output instruction
);

logic [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH-1)];

initial begin
    $readmemh("src/machine_code.mem", mem); // initialize ROM with data
    // $readmemh("find_maximum_in_array_machine_code.mem", mem);

end

always_comb begin
    if (imem_req) begin
        imem_data = {
            mem[imem_addr],
            mem[imem_addr+1],
            mem[imem_addr+2],
            mem[imem_addr+3]
        };
    end else begin
        imem_data = 32'd0;
    end
end

endmodule