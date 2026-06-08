module instruction_memory #(
    parameter ADDR_WIDTH = 7, // address bits
    parameter DATA_WIDTH = 8 // data width per memory cell
)(
    input logic imem_req, // read enable
    input logic [31:0] imem_addr, // byte address (word-aligned)
    output logic [31:0] imem_data // output instruction
);

logic [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH-1)];

// Program path comes from +PROGRAM=<path> plusarg so the harness can run
// many .mem files against the same compiled image without renaming files.
initial begin
    string program_path;
    if (!$value$plusargs("PROGRAM=%s", program_path))
        program_path = "src/machine_code.mem"; // fallback for ad-hoc runs
    $readmemh(program_path, mem);
end

always_comb begin
    if (imem_req) begin
        imem_data = {
            mem[imem_addr+3],
            mem[imem_addr+2],
            mem[imem_addr+1],
            mem[imem_addr]
        };
    end else begin
        imem_data = 32'd0;
    end
end

endmodule