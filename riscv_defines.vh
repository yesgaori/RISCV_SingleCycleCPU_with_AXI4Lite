`ifndef RISCV_DEFINES
`define RISCV_DEFINES

// --- Opcodes (7-bit) ---
`define OP_R_TYPE       7'b0110011
`define OP_I_TYPE       7'b0010011
`define OP_LOAD         7'b0000011
`define OP_STORE        7'b0100011
`define OP_BRANCH       7'b1100011
`define OP_JAL          7'b1101111
`define OP_JALR         7'b1100111
`define OP_LUI          7'b0110111
`define OP_AUIPC        7'b0010111

// --- ALU Control Signals (5-bit) ---
`define ALU_ADD         5'b00000
`define ALU_SUB         5'b00001
`define ALU_AND         5'b00010
`define ALU_OR          5'b00011
`define ALU_XOR         5'b00100
`define ALU_SLL         5'b00101
`define ALU_SRL         5'b00110
`define ALU_SRA         5'b00111
`define ALU_SLT         5'b01000
`define ALU_SLTU        5'b01001
`define ALU_MUL         5'b10000

// --- Branch Checks (ALU Output Control) ---
`define ALU_BEQ         5'b01010
`define ALU_BNE         5'b01011
`define ALU_BLT         5'b01100
`define ALU_BGE         5'b01101
`define ALU_BLTU        5'b01110
`define ALU_BGEU        5'b01111

// --- Memory Map (Address) ---
`define ADDR_LED        32'hFFFFFF00
`define ADDR_SW         32'hFFFFFF04

`endif