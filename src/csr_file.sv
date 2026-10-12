import risc_pkg::*;

module csr_file (
  input  logic        clk,
  input  logic        reset_n,

  input  logic [11:0] rd_addr,
  output logic [31:0] rd_data,
  input  logic        access_wr_en,
  output logic        access_illegal,

  input  logic        wr_en,
  input  logic [11:0] wr_addr,
  input  logic [31:0] wr_data,

  input  logic        instret_inc,
  input  logic [63:0] time_value,

  input  logic [31:0] irq_pending,
  output logic        irq_valid,
  output interrupt_cause_t irq_cause,

  input  logic        trap_enter,
  input  trap_payload_t trap,
  input  logic        mret_enter,
  input  logic        sret_enter,

  output logic [31:0] mtvec,
  output logic [31:0] stvec,
  output logic [31:0] mepc,
  output logic [31:0] sepc,
  output logic        trap_to_supervisor,
  output logic        sret_blocked,
  output privilege_mode_t current_privilege
);

localparam logic [11:0] CSR_MSTATUS  = 12'h300;
localparam logic [11:0] CSR_MISA     = 12'h301;
localparam logic [11:0] CSR_MEDELEG  = 12'h302;
localparam logic [11:0] CSR_MIDELEG  = 12'h303;
localparam logic [11:0] CSR_MIE      = 12'h304;
localparam logic [11:0] CSR_MTVEC    = 12'h305;
localparam logic [11:0] CSR_MCOUNTEREN = 12'h306;
localparam logic [11:0] CSR_MSTATUSH = 12'h310;
localparam logic [11:0] CSR_MSCRATCH = 12'h340;
localparam logic [11:0] CSR_MEPC     = 12'h341;
localparam logic [11:0] CSR_MCAUSE   = 12'h342;
localparam logic [11:0] CSR_MTVAL    = 12'h343;
localparam logic [11:0] CSR_MIP      = 12'h344;
localparam logic [11:0] CSR_MCYCLE   = 12'hb00;
localparam logic [11:0] CSR_MINSTRET = 12'hb02;
localparam logic [11:0] CSR_MCYCLEH  = 12'hb80;
localparam logic [11:0] CSR_MINSTRETH = 12'hb82;
localparam logic [11:0] CSR_MVENDORID = 12'hf11;
localparam logic [11:0] CSR_MARCHID   = 12'hf12;
localparam logic [11:0] CSR_MIMPID    = 12'hf13;
localparam logic [11:0] CSR_MHARTID   = 12'hf14;
localparam logic [11:0] CSR_MCONFIGPTR = 12'hf15;

localparam logic [11:0] CSR_SSTATUS  = 12'h100;
localparam logic [11:0] CSR_SIE      = 12'h104;
localparam logic [11:0] CSR_STVEC    = 12'h105;
localparam logic [11:0] CSR_SCOUNTEREN = 12'h106;
localparam logic [11:0] CSR_SSCRATCH = 12'h140;
localparam logic [11:0] CSR_SEPC     = 12'h141;
localparam logic [11:0] CSR_SCAUSE   = 12'h142;
localparam logic [11:0] CSR_STVAL    = 12'h143;
localparam logic [11:0] CSR_SIP      = 12'h144;
localparam logic [11:0] CSR_SATP     = 12'h180;
localparam logic [11:0] CSR_CYCLE    = 12'hc00;
localparam logic [11:0] CSR_TIME     = 12'hc01;
localparam logic [11:0] CSR_INSTRET  = 12'hc02;
localparam logic [11:0] CSR_CYCLEH   = 12'hc80;
localparam logic [11:0] CSR_TIMEH    = 12'hc81;
localparam logic [11:0] CSR_INSTRETH = 12'hc82;

localparam int MSTATUS_SIE_BIT = 1;
localparam int MSTATUS_MIE_BIT = 3;
localparam int MSTATUS_SPIE_BIT = 5;
localparam int MSTATUS_MPIE_BIT = 7;
localparam int MSTATUS_SPP_BIT = 8;
localparam int MSTATUS_MPP_LSB = 11;
localparam int MSTATUS_MPP_MSB = 12;
localparam int MSTATUS_MPRV_BIT = 17;
localparam int MSTATUS_SUM_BIT = 18;
localparam int MSTATUS_MXR_BIT = 19;
localparam int MSTATUS_TVM_BIT = 20;
localparam int MSTATUS_TW_BIT = 21;
localparam int MSTATUS_TSR_BIT = 22;
localparam logic [31:0] MISA_VALUE =
    (32'h1 << 30) |  // MXL=1: RV32
    (32'h1 << 0)  |  // A: atomic extension
    (32'h1 << 20) |  // U: user mode
    (32'h1 << 18) |  // S: supervisor mode
    (32'h1 << 12) |  // M: integer multiply/divide extension
    (32'h1 << 8);    // I: base integer ISA
localparam logic [31:0] SSTATUS_MASK =
    (32'h1 << MSTATUS_SIE_BIT) |
    (32'h1 << MSTATUS_SPIE_BIT) |
    (32'h1 << MSTATUS_SPP_BIT) |
    (32'h1 << MSTATUS_MXR_BIT);
localparam logic [31:0] MSTATUS_WRITABLE_MASK =
    SSTATUS_MASK |
    (32'h1 << MSTATUS_MIE_BIT) |
    (32'h1 << MSTATUS_MPIE_BIT) |
    (32'h3 << MSTATUS_MPP_LSB) |
    (32'h1 << MSTATUS_MPRV_BIT) |
    (32'h1 << MSTATUS_TVM_BIT) |
    (32'h1 << MSTATUS_TW_BIT) |
    (32'h1 << MSTATUS_TSR_BIT);
localparam logic [31:0] COUNTER_ENABLE_MASK = 32'h0000_0007;
localparam logic [31:0] SUPERVISOR_IRQ_MASK =
    (32'h1 << IRQ_CAUSE_SSI) |
    (32'h1 << IRQ_CAUSE_STI) |
    (32'h1 << IRQ_CAUSE_SEI);
localparam logic [31:0] MIP_SW_WRITABLE_MASK = SUPERVISOR_IRQ_MASK;
localparam logic [31:0] SIP_SW_WRITABLE_MASK = (32'h1 << IRQ_CAUSE_SSI);
localparam logic [31:0] MACHINE_IRQ_MASK =
    (32'h1 << IRQ_CAUSE_MSI) |
    (32'h1 << IRQ_CAUSE_MTI) |
    (32'h1 << IRQ_CAUSE_MEI);
localparam logic [31:0] SUPPORTED_IRQ_MASK =
    SUPERVISOR_IRQ_MASK | MACHINE_IRQ_MASK;
localparam logic [31:0] SUPPORTED_EXCEPTION_DELEG_MASK =
    (32'h1 << TRAP_CAUSE_INST_ADDR_MISALIGNED) |
    (32'h1 << TRAP_CAUSE_ILLEGAL_INSTRUCTION) |
    (32'h1 << TRAP_CAUSE_BREAKPOINT) |
    (32'h1 << TRAP_CAUSE_LOAD_ADDR_MISALIGNED) |
    (32'h1 << TRAP_CAUSE_STORE_ADDR_MISALIGNED) |
    (32'h1 << TRAP_CAUSE_ECALL_U) |
    (32'h1 << TRAP_CAUSE_ECALL_S);

logic [31:0] mstatus_q;
logic [31:0] medeleg_q;
logic [31:0] mideleg_q;
logic [31:0] mie_q;
logic [31:0] mtvec_q;
logic [31:0] mscratch_q;
logic [31:0] mepc_q;
logic [31:0] mcause_q;
logic [31:0] mtval_q;
logic [63:0] mcycle_q;
logic [63:0] minstret_q;
logic [31:0] mcounteren_q;
logic [31:0] scounteren_q;
logic [31:0] stvec_q;
logic [31:0] sscratch_q;
logic [31:0] sepc_q;
logic [31:0] scause_q;
logic [31:0] stval_q;
logic [31:0] mip_value;
logic [31:0] sstatus_value;
logic [31:0] sie_value;
logic [31:0] sip_value;
logic [31:0] enabled_pending;
logic [31:0] machine_enabled_pending;
logic [31:0] supervisor_enabled_pending;
logic [31:0] eligible_pending;
// Software-injected supervisor pending bits stored behind mip.
logic [31:0] mip_supervisor_sw_q;
logic        csr_implemented;
logic        counter_access;
logic [1:0]  counter_enable_bit;
logic        counter_access_illegal;
logic [31:0] mstatus_write_value;
privilege_mode_t current_privilege_q;

assign mtvec = mtvec_q;
assign stvec = stvec_q;
assign mepc = mepc_q;
assign sepc = sepc_q;
assign current_privilege = current_privilege_q;
assign sret_blocked = (current_privilege_q == PRIVILEGE_S) &&
                      mstatus_q[MSTATUS_TSR_BIT];
assign trap_to_supervisor = (current_privilege_q != PRIVILEGE_M) &&
                            (trap.mcause[31] ? mideleg_q[trap.mcause[4:0]] :
                                               medeleg_q[trap.mcause[4:0]]);
assign mip_value = (irq_pending & SUPPORTED_IRQ_MASK) |
                   mip_supervisor_sw_q;
assign sstatus_value = mstatus_q & SSTATUS_MASK;
assign sie_value = mie_q & mideleg_q & SUPERVISOR_IRQ_MASK;
assign sip_value = mip_value & mideleg_q & SUPERVISOR_IRQ_MASK;
assign enabled_pending = mip_value & mie_q;
assign machine_enabled_pending = enabled_pending & ~mideleg_q;
assign supervisor_enabled_pending = enabled_pending & mideleg_q;

always_comb begin
  eligible_pending = 32'h0;

  unique case (current_privilege_q)
    PRIVILEGE_M: begin
      if (mstatus_q[MSTATUS_MIE_BIT]) begin
        eligible_pending = machine_enabled_pending;
      end
    end
    PRIVILEGE_S: begin
      if (machine_enabled_pending != 32'h0) begin
        eligible_pending = machine_enabled_pending;
      end else if (mstatus_q[MSTATUS_SIE_BIT]) begin
        eligible_pending = supervisor_enabled_pending;
      end
    end
    default: begin
      eligible_pending = (machine_enabled_pending != 32'h0) ? machine_enabled_pending :
                                                               supervisor_enabled_pending;
    end
  endcase
end

assign irq_valid = (eligible_pending != 32'h0);

always_comb begin
  counter_access = 1'b1;
  counter_enable_bit = 2'd0;

  unique case (rd_addr)
    CSR_CYCLE, CSR_CYCLEH:     counter_enable_bit = 2'd0;
    CSR_TIME, CSR_TIMEH:       counter_enable_bit = 2'd1;
    CSR_INSTRET, CSR_INSTRETH: counter_enable_bit = 2'd2;
    default: begin
      counter_access = 1'b0;
      counter_enable_bit = 2'd0;
    end
  endcase

  counter_access_illegal = 1'b0;
  if (counter_access) begin
    unique case (current_privilege_q)
      PRIVILEGE_S:
        counter_access_illegal = !mcounteren_q[counter_enable_bit];
      PRIVILEGE_U:
        counter_access_illegal = !mcounteren_q[counter_enable_bit] ||
                                 !scounteren_q[counter_enable_bit];
      default: counter_access_illegal = 1'b0;
    endcase
  end
end

always_comb begin
  mstatus_write_value = wr_data & MSTATUS_WRITABLE_MASK;
  unique case (wr_data[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB])
    PRIVILEGE_U,
    PRIVILEGE_S,
    PRIVILEGE_M: begin
    end
    default:
      mstatus_write_value[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] = PRIVILEGE_M;
  endcase
end

always_comb begin
  unique case (rd_addr)
    CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN, CSR_SSCRATCH, CSR_SEPC,
    CSR_SCAUSE, CSR_STVAL, CSR_SIP, CSR_SATP,
    CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC,
    CSR_MCOUNTEREN, CSR_MSTATUSH,
    CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP,
    CSR_MCYCLE, CSR_MINSTRET, CSR_MCYCLEH, CSR_MINSTRETH,
    CSR_CYCLE, CSR_TIME, CSR_INSTRET, CSR_CYCLEH, CSR_TIMEH, CSR_INSTRETH,
    CSR_MVENDORID, CSR_MARCHID,
    CSR_MIMPID, CSR_MHARTID, CSR_MCONFIGPTR: csr_implemented = 1'b1;
    default:                  csr_implemented = 1'b0;
  endcase

  access_illegal = !csr_implemented ||
                   (rd_addr[9:8] == 2'b10) ||
                   (rd_addr[9:8] > current_privilege_q) ||
                   (access_wr_en && (rd_addr[11:10] == 2'b11)) ||
                   counter_access_illegal ||
                   ((current_privilege_q == PRIVILEGE_S) &&
                    mstatus_q[MSTATUS_TVM_BIT] &&
                    (rd_addr == CSR_SATP));
end

always_comb begin
  irq_cause = IRQ_CAUSE_MSI;

  if (eligible_pending[IRQ_CAUSE_MEI]) begin
    irq_cause = IRQ_CAUSE_MEI;
  end else if (eligible_pending[IRQ_CAUSE_MSI]) begin
    irq_cause = IRQ_CAUSE_MSI;
  end else if (eligible_pending[IRQ_CAUSE_MTI]) begin
    irq_cause = IRQ_CAUSE_MTI;
  end else if (eligible_pending[IRQ_CAUSE_SEI]) begin
    irq_cause = IRQ_CAUSE_SEI;
  end else if (eligible_pending[IRQ_CAUSE_SSI]) begin
    irq_cause = IRQ_CAUSE_SSI;
  end else if (eligible_pending[IRQ_CAUSE_STI]) begin
    irq_cause = IRQ_CAUSE_STI;
  end
end

always_comb begin
  unique case (rd_addr)
    CSR_SSTATUS:  rd_data = sstatus_value;
    CSR_SIE:      rd_data = sie_value;
    CSR_STVEC:    rd_data = stvec_q;
    CSR_SCOUNTEREN: rd_data = scounteren_q;
    CSR_SSCRATCH: rd_data = sscratch_q;
    CSR_SEPC:     rd_data = sepc_q;
    CSR_SCAUSE:   rd_data = scause_q;
    CSR_STVAL:    rd_data = stval_q;
    CSR_SIP:      rd_data = sip_value;
    CSR_SATP:     rd_data = 32'h0;
    CSR_MSTATUS:  rd_data = mstatus_q;
    CSR_MISA:     rd_data = MISA_VALUE;
    CSR_MEDELEG:  rd_data = medeleg_q;
    CSR_MIDELEG:  rd_data = mideleg_q;
    CSR_MIE:      rd_data = mie_q;
    CSR_MTVEC:    rd_data = mtvec_q;
    CSR_MCOUNTEREN: rd_data = mcounteren_q;
    CSR_MSTATUSH: rd_data = 32'h0;
    CSR_MSCRATCH: rd_data = mscratch_q;
    CSR_MEPC:     rd_data = mepc_q;
    CSR_MCAUSE:   rd_data = mcause_q;
    CSR_MTVAL:    rd_data = mtval_q;
    CSR_MIP:      rd_data = mip_value;
    CSR_MCYCLE,
    CSR_CYCLE:    rd_data = mcycle_q[31:0];
    CSR_MINSTRET,
    CSR_INSTRET:  rd_data = minstret_q[31:0];
    CSR_MCYCLEH,
    CSR_CYCLEH:   rd_data = mcycle_q[63:32];
    CSR_MINSTRETH,
    CSR_INSTRETH: rd_data = minstret_q[63:32];
    CSR_TIME:     rd_data = time_value[31:0];
    CSR_TIMEH:    rd_data = time_value[63:32];
    CSR_MVENDORID,
    CSR_MARCHID,
    CSR_MIMPID,
    CSR_MHARTID,
    CSR_MCONFIGPTR: rd_data = 32'h0;
    default:      rd_data = 32'h0;
  endcase

  if (wr_en && (wr_addr == rd_addr)) begin
    unique case (rd_addr)
      CSR_SSTATUS: rd_data = wr_data & SSTATUS_MASK;
      CSR_SCOUNTEREN: rd_data = wr_data & COUNTER_ENABLE_MASK;
      CSR_SIE:     rd_data = wr_data & mideleg_q & SUPERVISOR_IRQ_MASK;
      CSR_SIP:     rd_data = (sip_value & ~SIP_SW_WRITABLE_MASK) |
                                  (wr_data & SIP_SW_WRITABLE_MASK & mideleg_q);
      CSR_SATP:    rd_data = 32'h0;
      CSR_MSTATUS: rd_data = mstatus_write_value;
      CSR_MISA:    rd_data = MISA_VALUE;
      CSR_MCOUNTEREN: rd_data = wr_data & COUNTER_ENABLE_MASK;
      CSR_MSTATUSH: rd_data = 32'h0;
      CSR_MEDELEG: rd_data = wr_data & SUPPORTED_EXCEPTION_DELEG_MASK;
      CSR_MIDELEG: rd_data = wr_data & SUPERVISOR_IRQ_MASK;
      CSR_MIE:     rd_data = wr_data & SUPPORTED_IRQ_MASK;
      CSR_MIP:     rd_data = (mip_value & ~MIP_SW_WRITABLE_MASK) |
                                  (wr_data & MIP_SW_WRITABLE_MASK);
      default:     rd_data = wr_data;
    endcase
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mstatus_q <= 32'h0;
    medeleg_q <= 32'h0;
    mideleg_q <= 32'h0;
    mie_q <= 32'h0;
    mtvec_q <= 32'h0;
    mscratch_q <= 32'h0;
    mepc_q <= 32'h0;
    mcause_q <= 32'h0;
    mtval_q <= 32'h0;
    mcycle_q <= 64'h0;
    minstret_q <= 64'h0;
    mcounteren_q <= 32'h0;
    scounteren_q <= 32'h0;
    stvec_q <= 32'h0;
    sscratch_q <= 32'h0;
    sepc_q <= 32'h0;
    scause_q <= 32'h0;
    stval_q <= 32'h0;
    mip_supervisor_sw_q <= 32'h0;
    current_privilege_q <= PRIVILEGE_M;
  end else begin
    mcycle_q <= mcycle_q + 1'b1;

    if (instret_inc) begin
      minstret_q <= minstret_q + 1'b1;
    end

    if (trap_enter) begin
      if (trap_to_supervisor) begin
        sepc_q <= trap.mepc;
        scause_q <= trap.mcause;
        stval_q <= trap.mtval;
        mstatus_q[MSTATUS_SPIE_BIT] <= mstatus_q[MSTATUS_SIE_BIT];
        mstatus_q[MSTATUS_SIE_BIT] <= 1'b0;
        mstatus_q[MSTATUS_SPP_BIT] <= (current_privilege_q == PRIVILEGE_S);
        current_privilege_q <= PRIVILEGE_S;
      end else begin
        mepc_q <= trap.mepc;
        mcause_q <= trap.mcause;
        mtval_q <= trap.mtval;
        mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
        mstatus_q[MSTATUS_MIE_BIT] <= 1'b0;
        mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= current_privilege_q;
        current_privilege_q <= PRIVILEGE_M;
      end
    end else if (mret_enter) begin
      mstatus_q[MSTATUS_MIE_BIT] <= mstatus_q[MSTATUS_MPIE_BIT];
      mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
      mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRIVILEGE_U;
      if (mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] != PRIVILEGE_M) begin
        mstatus_q[MSTATUS_MPRV_BIT] <= 1'b0;
      end
      unique case (mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB])
        PRIVILEGE_U: current_privilege_q <= PRIVILEGE_U;
        PRIVILEGE_S: current_privilege_q <= PRIVILEGE_S;
        default:     current_privilege_q <= PRIVILEGE_M;
      endcase
    end else if (sret_enter) begin
      mstatus_q[MSTATUS_SIE_BIT] <= mstatus_q[MSTATUS_SPIE_BIT];
      mstatus_q[MSTATUS_SPIE_BIT] <= 1'b1;
      mstatus_q[MSTATUS_SPP_BIT] <= 1'b0;
      mstatus_q[MSTATUS_MPRV_BIT] <= 1'b0;
      current_privilege_q <= mstatus_q[MSTATUS_SPP_BIT] ? PRIVILEGE_S : PRIVILEGE_U;
    end else if (wr_en) begin
      unique case (wr_addr)
        CSR_SSTATUS:  mstatus_q <= (mstatus_q & ~SSTATUS_MASK) |
                                   (wr_data & SSTATUS_MASK);
        CSR_SIE:      mie_q <= (mie_q & ~(mideleg_q & SUPERVISOR_IRQ_MASK)) |
                              (wr_data & mideleg_q & SUPERVISOR_IRQ_MASK);
        CSR_STVEC:    stvec_q <= wr_data;
        CSR_SCOUNTEREN: scounteren_q <= wr_data & COUNTER_ENABLE_MASK;
        CSR_SSCRATCH: sscratch_q <= wr_data;
        CSR_SEPC:     sepc_q <= wr_data;
        CSR_SCAUSE:   scause_q <= wr_data;
        CSR_STVAL:    stval_q <= wr_data;
        CSR_SIP:      mip_supervisor_sw_q <=
                          (mip_supervisor_sw_q & ~SIP_SW_WRITABLE_MASK) |
                          (wr_data & SIP_SW_WRITABLE_MASK & mideleg_q);
        CSR_SATP: begin
        end
        CSR_MSTATUS:  mstatus_q <= mstatus_write_value;
        CSR_MISA: begin
        end
        CSR_MCOUNTEREN: mcounteren_q <= wr_data & COUNTER_ENABLE_MASK;
        CSR_MSTATUSH: begin
        end
        CSR_MEDELEG:  medeleg_q <= wr_data & SUPPORTED_EXCEPTION_DELEG_MASK;
        CSR_MIDELEG:  mideleg_q <= wr_data & SUPERVISOR_IRQ_MASK;
        CSR_MIE:      mie_q <= wr_data & SUPPORTED_IRQ_MASK;
        CSR_MTVEC:    mtvec_q <= wr_data;
        CSR_MSCRATCH: mscratch_q <= wr_data;
        CSR_MEPC:     mepc_q <= wr_data;
        CSR_MCAUSE:   mcause_q <= wr_data;
        CSR_MTVAL:    mtval_q <= wr_data;
        CSR_MIP:      mip_supervisor_sw_q <= wr_data & MIP_SW_WRITABLE_MASK;
        CSR_MCYCLE:   mcycle_q <= {mcycle_q[63:32], wr_data};
        CSR_MINSTRET: minstret_q <= {minstret_q[63:32], wr_data};
        CSR_MCYCLEH:  mcycle_q <= {wr_data, mcycle_q[31:0]};
        CSR_MINSTRETH: minstret_q <= {wr_data, minstret_q[31:0]};
        default: begin
        end
      endcase
    end
  end
end

endmodule
