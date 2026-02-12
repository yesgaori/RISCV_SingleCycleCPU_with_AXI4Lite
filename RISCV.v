`timescale 1ns / 1ps
`include "riscv_defines.vh"

// ============================================================================
// 1. Program Counter & Adder & Mux
// ============================================================================
module program_counter(input clk, rst,
                       input stall,              
                       input [31:0] pc_in, 
                       output reg [31:0] pc_out
                       );
    always@(posedge clk or posedge rst) begin
        if(rst) pc_out <= 32'b0;
        else if(!stall) pc_out <= pc_in; // Stall이 아닐 때만 PC 업데이트
    end
endmodule

module pc_adder(input [31:0] pc_in, output [31:0] pc_next);
    assign pc_next = pc_in + 4;
endmodule

module pc_mux(input [31:0] pc_in, pc_branch, pc_jalr, input isJALR, pc_select, output reg [31:0] pc_out);
    always@(*) begin
        if(isJALR) pc_out = pc_jalr;
        else if(pc_select) pc_out = pc_branch;
        else pc_out = pc_in;
    end
endmodule

// ============================================================================
// 2. Control Units
// ============================================================================
module main_control_unit(
    input [6:0] opcode,
    output reg RegWrite, MemRead, MemWrite, ALUSrc, Branch, isJALR, Jump,
    output reg [1:0] MemToReg, ALUOp
);
    always@(*) begin
        {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} = 0;
        case(opcode)
            `OP_R_TYPE: {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b0, 2'b00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b10};
            `OP_I_TYPE: {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b1, 2'b00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b11};
            `OP_LOAD:   {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b1, 2'b01, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00};
            `OP_STORE:  {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b1, 2'b00, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 2'b00};
            `OP_BRANCH: {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 2'b01};
            `OP_JAL:    {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b0, 2'b00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b10};
            `OP_JALR:   {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b1, 2'b10, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 2'b00};
            `OP_LUI:    {ALUSrc, MemToReg, RegWrite, MemRead, MemWrite, Branch, isJALR, Jump, ALUOp} 
                        <= {1'b1, 2'b00, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b11};
        endcase
    end
endmodule

module ALU_Control(
    input [2:0] funct3,
    input [6:0] funct7,
    input [1:0] ALUOp,
    output reg [4:0] ctrl
);
    always@(*) begin
        ctrl = `ALU_ADD;
        case(ALUOp)
            2'b00: ctrl = `ALU_ADD; // LW, SW
            2'b01: begin // Branch
                case(funct3)
                    3'b000: ctrl = `ALU_BEQ;
                    3'b001: ctrl = `ALU_BNE;
                    default: ctrl = `ALU_BEQ;
                endcase
            end
            2'b10: begin // R-Type
                if(funct7 == 7'b0000001) ctrl = `ALU_MUL;
                else begin
                    case(funct3)
                        3'b000: ctrl = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001: ctrl = `ALU_SLL;
                        3'b010: ctrl = `ALU_SLT;
                        3'b011: ctrl = `ALU_SLTU;
                        3'b100: ctrl = `ALU_XOR;
                        3'b101: ctrl = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                        3'b110: ctrl = `ALU_OR;
                        3'b111: ctrl = `ALU_AND;
                    endcase
                end
            end
            2'b11: begin // I-Type
                case(funct3)
                    3'b000: ctrl = `ALU_ADD; 
                    3'b001: ctrl = `ALU_SLL;
                    3'b010: ctrl = `ALU_SLT;
                    3'b011: ctrl = `ALU_SLTU;
                    3'b100: ctrl = `ALU_XOR;
                    3'b101: ctrl = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                    3'b110: ctrl = `ALU_OR;
                    3'b111: ctrl = `ALU_AND;
                endcase
            end
        endcase
    end
endmodule

// ============================================================================
// 3. Data Path Modules
// ============================================================================
module Register_File(input clk, rst, RegWrite, input [4:0] Rs1, Rs2, Rd, input [31:0] Write_data, output [31:0] read_data1, read_data2);
    reg [31:0] Registers [31:0];
    integer i;
    initial begin for(i=0; i<32; i=i+1) Registers[i] = 0; Registers[2] = 32'd256; end // SP 초기화
    always@(posedge clk) begin
        if(rst) for(i=0; i<32; i=i+1) Registers[i] <= 0;
        else if(RegWrite && (Rd != 0)) Registers[Rd] <= Write_data;
    end
    assign read_data1 = (Rs1 == 0) ? 0 : Registers[Rs1];
    assign read_data2 = (Rs2 == 0) ? 0 : Registers[Rs2];
endmodule

module immediate_generator(input [31:0] inst, output reg [31:0] imm);
    always@(*) case(inst[6:0])
        `OP_I_TYPE, `OP_LOAD, `OP_JALR: imm = {{20{inst[31]}}, inst[31:20]};
        `OP_STORE:  imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        `OP_BRANCH: imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
        `OP_LUI, `OP_AUIPC: imm = {inst[31:12], 12'b0};
        `OP_JAL:    imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
        default:    imm = 0;
    endcase
endmodule

module Instruction_Memory(input [31:0] addr, output [31:0] inst);
    reg [31:0] mem [127:0];
    assign inst = mem[addr >> 2];
    initial begin
        
        $readmemh("/media/user1/data/work_cpu/single_cycle_cpu_by_riscV/test.hex", mem); 
    end
endmodule

module ALU(input [31:0] A, B, input [4:0] ALUcontrol, output reg [31:0] Result, output reg Zero);
    always@(*) begin
        Result = 0; Zero = 0;
        case(ALUcontrol)
            `ALU_ADD: Result = A + B;
            `ALU_SUB: Result = A - B;
            `ALU_AND: Result = A & B; `ALU_OR: Result = A | B;
            `ALU_XOR: Result = A ^ B;
            `ALU_SLL: Result = A << B[4:0]; `ALU_SRL: Result = A >> B[4:0];
            `ALU_SRA: Result = $signed(A) >>> B[4:0];
            `ALU_SLT: Result = ($signed(A) < $signed(B)) ? 1 : 0;
            `ALU_SLTU: Result = (A < B) ? 1 : 0;
            `ALU_MUL: Result = A * B;
            `ALU_BEQ: Zero = (A == B); `ALU_BNE: Zero = (A != B);
            default: Result = 0;
        endcase
        if(ALUcontrol < `ALU_BEQ) Zero = (Result == 0);
    end
endmodule

module MUX2to1(input [31:0] i0, i1, input sel, output [31:0] out);
    assign out = (sel) ? i1 : i0;
endmodule

module MUX4to1_DataMemory(input [31:0] alu_res, mem_dat, pc_p4, pc_imm, input [1:0] sel, output reg [31:0] out);
    always@(*) case(sel) 2'b00:out=alu_res; 2'b01:out=mem_dat; 2'b10:out=pc_p4; 2'b11:out=pc_imm; default:out=0; endcase
endmodule

// ============================================================================
// 4-1. Data_Memory (cpu 내부 )
// ============================================================================

module Data_Memory(
    input clk, rst, MemRead, MemWrite,
    input [31:0] address,
    input [2:0] funct3,
    input [31:0] write_data,
    
    output reg[31:0] read_data,
    // GPIO
    input [15:0] SW_Port,
    output reg[15:0] LED_Port
);

    reg [31:0] D_Memory[63:0]; // 64 Words (256 Bytes)
    integer k;

    // Word indexing을 위한 주소 처리
    wire [31:0] mem_word = D_Memory[address >> 2];

    // --- 쓰기 로직 (SB, SH, SW 및 LED 제어) ---
    always@(posedge clk or posedge rst) begin
        if(rst) begin
            LED_Port <= 16'h0000;
        end
        else if(MemWrite) begin
            // GPIO LED 주소 처리 (기존 defines.vh의 LED_ADDR 사용)
            if(address == `ADDR_LED) LED_Port <= write_data[15:0];
            else begin
                case(funct3)
                    3'b010: D_Memory[address >> 2] <= write_data; // SW
                    3'b001: begin // SH
                        case(address[1])
                            1'b0: D_Memory[address >> 2] <= {D_Memory[address >> 2][31:16], write_data[15:0]};
                            1'b1: D_Memory[address >> 2] <= {write_data[15:0], D_Memory[address >> 2][15:0]};
                        endcase
                    end
                    3'b000: begin // SB
                        case(address[1:0])
                            2'b00: D_Memory[address >> 2] <= {D_Memory[address >> 2][31:8], write_data[7:0]};
                            2'b01: D_Memory[address >> 2] <= {D_Memory[address >> 2][31:16], write_data[7:0], D_Memory[address >> 2][7:0]};
                            2'b10: D_Memory[address >> 2] <= {D_Memory[address >> 2][31:24], write_data[7:0], D_Memory[address >> 2][15:0]};
                            2'b11: D_Memory[address >> 2] <= {write_data[7:0], D_Memory[address >> 2][23:0]};
                        endcase
                    end
                endcase
            end
        end 
    end

    // --- 읽기 로직 (LB, LH, LW, LBU, LHU 및 SW_Port 제어) ---
    always@(*) begin
        if(MemRead) begin
            // GPIO Switch 주소 처리
            if(address == `ADDR_SW) read_data = {16'b0, SW_Port};
            else begin
                case(funct3)
                    3'b000: begin // LB (Signed)
                        case(address[1:0])
                            2'b00: read_data = {{24{mem_word[7]}}, mem_word[7:0]};
                            2'b01: read_data = {{24{mem_word[15]}}, mem_word[15:8]};
                            2'b10: read_data = {{24{mem_word[23]}}, mem_word[23:16]};
                            2'b11: read_data = {{24{mem_word[31]}}, mem_word[31:24]};
                        endcase
                    end 
                    3'b001: begin // LH (Signed)
                        case(address[1])
                            1'b0: read_data = {{16{mem_word[15]}}, mem_word[15:0]};
                            1'b1: read_data = {{16{mem_word[31]}}, mem_word[31:16]};
                        endcase
                    end
                    3'b010: read_data = mem_word; // LW
                    3'b100: begin // LBU (Unsigned)
                        case(address[1:0])
                            2'b00: read_data = {24'b0, mem_word[7:0]};
                            2'b01: read_data = {24'b0, mem_word[15:8]};
                            2'b10: read_data = {24'b0, mem_word[23:16]};
                            2'b11: read_data = {24'b0, mem_word[31:24]};
                        endcase
                    end
                    3'b101: begin // LHU (Unsigned)
                        case(address[1])
                            1'b0: read_data = {16'b0, mem_word[15:0]};
                            1'b1: read_data = {16'b0, mem_word[31:16]};
                        endcase
                    end
                    default: read_data = 32'b0;
                endcase
            end
        end
        else read_data = 32'b0;
    end

    initial begin
        for(k = 0; k < 64; k = k + 1) D_Memory[k] = 32'b0;
        D_Memory[17] = 56;
        D_Memory[15] = 65;
    end
endmodule
// ============================================================================
// 4-2. AXI Master Interface (S_COOLDOWN 포함된 최신 버전)
// ============================================================================
module AXI_Master_Interface (
    input wire clk, input wire rst,
    input wire mem_read, input wire mem_write,
    input wire [31:0] addr, input wire [31:0] wdata,
    output reg [31:0] rdata, output reg busy, output reg done,

    // AXI Ports
    output reg [31:0] M_AXI_AWADDR, output reg [2:0] M_AXI_AWPROT, output reg M_AXI_AWVALID, input wire M_AXI_AWREADY,
    output reg [31:0] M_AXI_WDATA, output reg [3:0] M_AXI_WSTRB, output reg M_AXI_WVALID, input wire M_AXI_WREADY,
    input wire [1:0] M_AXI_BRESP, input wire M_AXI_BVALID, output reg M_AXI_BREADY,
    output reg [31:0] M_AXI_ARADDR, output reg [2:0] M_AXI_ARPROT, output reg M_AXI_ARVALID, input wire M_AXI_ARREADY,
    input wire [31:0] M_AXI_RDATA, input wire [1:0] M_AXI_RRESP, input wire M_AXI_RVALID, output reg M_AXI_RREADY
);
    localparam S_IDLE=0, S_WR_SEND=1, S_WR_RESP=2, S_RD_ADDR=3, S_RD_DATA=4, S_COOLDOWN=5;
    reg [2:0] state;

    initial begin M_AXI_AWPROT=0; M_AXI_ARPROT=0; M_AXI_WSTRB=4'b1111; end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE; busy <= 0; rdata <= 0; done <= 0;
            M_AXI_AWVALID <= 0; M_AXI_AWADDR <= 0; M_AXI_WVALID <= 0; M_AXI_WDATA <= 0; M_AXI_BREADY <= 0;
            M_AXI_ARVALID <= 0; M_AXI_ARADDR <= 0; M_AXI_RREADY <= 0;
        end else begin
            done <= 0;
            case (state)
                S_IDLE: begin
                    M_AXI_BREADY <= 0; M_AXI_RREADY <= 0;
                    if (mem_write) begin
                        busy <= 1; M_AXI_AWADDR <= addr; M_AXI_AWVALID <= 1; M_AXI_WDATA <= wdata; M_AXI_WVALID <= 1; state <= S_WR_SEND;
                    end else if (mem_read) begin
                        busy <= 1; M_AXI_ARADDR <= addr; M_AXI_ARVALID <= 1; state <= S_RD_ADDR;
                    end else busy <= 0;
                end
                S_WR_SEND: begin
                    if (M_AXI_AWREADY && M_AXI_AWVALID) M_AXI_AWVALID <= 0;
                    if (M_AXI_WREADY && M_AXI_WVALID) M_AXI_WVALID <= 0;
                    if ((!M_AXI_AWVALID || M_AXI_AWREADY) && (!M_AXI_WVALID || M_AXI_WREADY)) begin
                        M_AXI_BREADY <= 1; state <= S_WR_RESP;
                    end
                end
                S_WR_RESP: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY <= 0; busy <= 0; state <= S_COOLDOWN;
                    end
                end
                S_RD_ADDR: begin
                    if (M_AXI_ARREADY && M_AXI_ARVALID) begin
                        M_AXI_ARVALID <= 0; M_AXI_RREADY <= 1; state <= S_RD_DATA;
                    end
                end
                S_RD_DATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        rdata <= M_AXI_RDATA; M_AXI_RREADY <= 0; busy <= 0; state <= S_COOLDOWN;
                    end
                end
                S_COOLDOWN: begin busy <= 1; state <= S_IDLE; done <= 1; // [핵심] IDLE로 돌아가기 직전에 '완료' 깃발을 듬! 
                end
                 
                default: state <= S_IDLE;
                
            endcase
        end
    end
endmodule

// ============================================================================
// 5. UART Module
// ============================================================================
module uart_tx (
    input clk, rst, start,
    input [7:0] data,
    output reg tx = 1'b1, output reg busy
);
    parameter CLKS_PER_BIT = 10416; // 100MHz / 9600 baud
    reg [13:0] clk_count = 0; reg [2:0] bit_index = 0; reg [7:0] data_temp = 0; reg [1:0] state = 0;

    always @(posedge clk) begin
        if (rst) begin state <= 0; tx <= 1; busy <= 0; clk_count <= 0; bit_index <= 0; end
        else begin
            case (state)
                0: begin 
                    tx <= 1; clk_count <= 0; bit_index <= 0;
                    if (start) begin busy <= 1; data_temp <= data; state <= 1; end else busy <= 0;
                end
                1: begin // Start
                    tx <= 0;
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin clk_count <= 0; state <= 2; end
                end
                2: begin // Data
                    tx <= data_temp[bit_index];
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin 
                        clk_count <= 0;
                        if (bit_index < 7) bit_index <= bit_index + 1;
                        else begin bit_index <= 0; state <= 3; end
                    end
                end
                3: begin // Stop
                    tx <= 1;
                    if (clk_count < CLKS_PER_BIT-1) clk_count <= clk_count + 1;
                    else begin busy <= 0; state <= 0; end
                end
            endcase
        end
    end
endmodule

// ============================================================================
// 6. RISC-V TOP Module (Hybrid Architecture 적용됨)
// ============================================================================
module RISCV_Top#(
    // [IP 설정 창(GUI)에서 변경할 수 있는 파라미터들]
    parameter integer RESET_VECTOR      = 32'h0000_0000, // 시작 주소 (부트로더 위치 등)
    parameter integer SYS_CLK_FREQ      = 100_000_000,   // 시스템 동작 클럭 (UART 등 계산용)
    parameter integer CLK_DIV_BIT       = 2,             // 클럭 분주 비트 (속도 조절용)
    parameter integer AXI_ADDR_WIDTH    = 32,            // AXI 주소 너비
    parameter integer AXI_DATA_WIDTH    = 32             // AXI 데이터 너비
)(
    input sys_clk, rst,
    input [15:0] SW_Port, output [15:0] LED_Port, output RsTx,
    // AXI Ports
    output [31:0] M_AXI_AWADDR, output [2:0] M_AXI_AWPROT, output M_AXI_AWVALID, input M_AXI_AWREADY,
    output [31:0] M_AXI_WDATA, output [3:0] M_AXI_WSTRB, output M_AXI_WVALID, input M_AXI_WREADY,
    input [1:0] M_AXI_BRESP, input M_AXI_BVALID, output M_AXI_BREADY,
    output [31:0] M_AXI_ARADDR, output [2:0] M_AXI_ARPROT, output M_AXI_ARVALID, input M_AXI_ARREADY,
    input [31:0] M_AXI_RDATA, input [1:0] M_AXI_RRESP, input M_AXI_RVALID, output M_AXI_RREADY
);
    // Clock Setup
    reg [25:0] clk_counter;
    wire clk;
    always @(posedge sys_clk or posedge rst) begin
        if(rst) clk_counter <= 0; else clk_counter <= clk_counter + 1;
    end
    
    // [중요] 시뮬레이션용: sys_clk 직결 / 실제 구현용: clk_counter 사용
//    assign clk = sys_clk; 
     assign clk = clk_counter[2]; // 실제 보드용

    // Wires
    wire [31:0] pc_curr, pc_next, pc_mux_out, pc_branch_target;
    wire [31:0] inst, imm_ext, reg_rdata1, reg_rdata2, alu_res, wb_data;
    wire [31:0] alu_op2;
    wire RegWrite, MemRead, MemWrite, ALUSrc, Branch, isJALR, Jump, Zero;
    wire [1:0] MemToReg, ALUOp;
    wire [4:0] ALU_Ctrl;
    wire axi_busy, stall;
    wire axi_done; // [수정] 이 줄을 꼭 추가해주세요!
    // ------------------------------------------------------------------------
    // [1] 주소 디코더 (Address Decoder) & 메모리 맵
    // ------------------------------------------------------------------------
    // 0xFFFFxxxx 주소는 외부 장치(AXI)로 판단
    wire is_mmio = (alu_res[31:16] == 16'hFFFF);

    // ------------------------------------------------------------------------
    // [2] 내부 고속 데이터 메모리 (Internal Data Memory)
    // ------------------------------------------------------------------------
    // [수정] 내부 고속 데이터 메모리 인스턴스화
    wire [31:0] internal_rdata;
    wire [15:0] internal_led_output;

    Data_Memory Internal_DMEM (
        .clk(clk),
        .rst(rst),
        .MemRead(MemRead && !is_mmio),     // 내부 주소일 때만 활성 
        .MemWrite(MemWrite && !is_mmio),   // 내부 주소일 때만 활성 
        .address(alu_res),                 // ALU 결과 주소 [cite: 119]
        .funct3(inst[14:12]),              // 명령어로부터 크기 정보 전달 
        .write_data(reg_rdata2),           // 저장할 데이터 [cite: 119]
        .read_data(internal_rdata),        // 출력 데이터
        .SW_Port(SW_Port),                 // 외부 Switch 연결 [cite: 114]
        .LED_Port(internal_led_output)     // 내부 LED 포트 연결
    );

    // ------------------------------------------------------------------------
    // [3] 최종 Read Data 선택 및 Stall 로직
    // ------------------------------------------------------------------------
    wire [31:0] axi_rdata;
    wire [31:0] final_mem_rdata;

    // AXI 데이터와 내부 메모리 데이터 중 선택
    assign final_mem_rdata = is_mmio ? axi_rdata : internal_rdata;

    // [2] MMIO 요청 감지: "메모리 쓰기/읽기" AND "외부 주소"
    // (내부 메모리 접근 시에는 이 신호가 0이 됩니다!)
    wire mmio_req = (MemRead || MemWrite) && is_mmio; 

    // [3] Stall 결정 로직 (수정됨)
    // "MMIO 요청이 있는데(mmio_req), 아직 완료(done)가 안 됐으면 멈춰라!"
    // 내부 메모리 요청일 땐 mmio_req가 0이라서 stall도 절대 안 걸림.
    assign stall = mmio_req && !axi_done;
    
    // ------------------------------------------------------------------------
    // [4] 모듈 연결
    // ------------------------------------------------------------------------
    
    // UART Start Logic (MMIO 주소일 때만)
    reg uart_start;
    wire is_uart_addr = (alu_res == 32'hFFFFFF10);
    always @(*) begin
        if (MemWrite && is_uart_addr) uart_start = 1;
        else uart_start = 0;
    end
    uart_tx UART_Unit (.clk(sys_clk), .rst(rst), .start(uart_start), .data(reg_rdata2[7:0]), .tx(RsTx), .busy());

    program_counter PC (.clk(clk), .rst(rst), .stall(stall), .pc_in(pc_mux_out), .pc_out(pc_curr));
    pc_adder PC_Add (.pc_in(pc_curr), .pc_next(pc_next));
    assign pc_branch_target = pc_curr + imm_ext;
    pc_mux PC_Mux (.pc_in(pc_next), .pc_branch(pc_branch_target), .pc_jalr(alu_res), .isJALR(isJALR), .pc_select((Branch & Zero) | Jump), .pc_out(pc_mux_out));
    
    Instruction_Memory IMEM (.addr(pc_curr), .inst(inst)); // TCM (Instruction Memory)
    
    main_control_unit Main_Control (.opcode(inst[6:0]), .RegWrite(RegWrite), .MemRead(MemRead), .MemWrite(MemWrite), .ALUSrc(ALUSrc), .Branch(Branch), .isJALR(isJALR), .Jump(Jump), .MemToReg(MemToReg), .ALUOp(ALUOp));
    immediate_generator Imm_Gen (.inst(inst), .imm(imm_ext));
    Register_File RegFile (.clk(clk), .rst(rst), .RegWrite(RegWrite), .Rs1(inst[19:15]), .Rs2(inst[24:20]), .Rd(inst[11:7]), .Write_data(wb_data), .read_data1(reg_rdata1), .read_data2(reg_rdata2));
    ALU_Control ALUC (.funct3(inst[14:12]), .funct7(inst[31:25]), .ALUOp(ALUOp), .ctrl(ALU_Ctrl));
    MUX2to1 ALU_Src_Mux (.i0(reg_rdata2), .i1(imm_ext), .sel(ALUSrc), .out(alu_op2));
    ALU Main_ALU (.A(reg_rdata1), .B(alu_op2), .ALUcontrol(ALU_Ctrl), .Result(alu_res), .Zero(Zero));

    // [핵심] AXI Master 연결 시 MMIO 체크
    AXI_Master_Interface AXI_Master (
        .clk(clk), .rst(rst),
        .mem_read(MemRead && is_mmio),   // 외부 주소일 때만 AXI 동작
        .mem_write(MemWrite && is_mmio), // 외부 주소일 때만 AXI 동작
        .addr(alu_res),
        .wdata(reg_rdata2),
        .rdata(axi_rdata),               // AXI가 읽은 값
        .busy(axi_busy),
        .done(axi_done),
        
        // AXI Ports
        .M_AXI_AWADDR(M_AXI_AWADDR), .M_AXI_AWPROT(M_AXI_AWPROT), .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA), .M_AXI_WSTRB(M_AXI_WSTRB), .M_AXI_WVALID(M_AXI_WVALID), .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BRESP(M_AXI_BRESP), .M_AXI_BVALID(M_AXI_BVALID), .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARADDR(M_AXI_ARADDR), .M_AXI_ARPROT(M_AXI_ARPROT), .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RDATA(M_AXI_RDATA), .M_AXI_RRESP(M_AXI_RRESP), .M_AXI_RVALID(M_AXI_RVALID), .M_AXI_RREADY(M_AXI_RREADY)
    );

    MUX4to1_DataMemory WB_Mux (.alu_res(alu_res), .mem_dat(final_mem_rdata), .pc_p4(pc_next), .pc_imm(pc_branch_target), .sel(MemToReg), .out(wb_data));

    // LED Debugging
    assign LED_Port[15] = clk_counter[25];
    assign LED_Port[13] = uart_start;
    assign LED_Port[14] = axi_busy; 
    assign LED_Port[12:8] = 0;
    assign LED_Port[7:0] = pc_curr[9:2];
endmodule