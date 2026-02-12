`timescale 1ns / 1ps

module tb_riscv_axi();
    reg sys_clk; reg rst;
    reg [15:0] SW_Port; wire [15:0] LED_Port; wire RsTx;

    // AXI Wires
    wire [31:0] M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR;
    wire [2:0] M_AXI_AWPROT, M_AXI_ARPROT;
    wire [3:0] M_AXI_WSTRB;
    wire M_AXI_AWVALID, M_AXI_WVALID, M_AXI_BREADY, M_AXI_ARVALID, M_AXI_RREADY;
    reg M_AXI_AWREADY, M_AXI_WREADY, M_AXI_BVALID, M_AXI_ARREADY, M_AXI_RVALID;
    reg [1:0] M_AXI_BRESP, M_AXI_RRESP;
    reg [31:0] M_AXI_RDATA;

    // CPU 연결
    RISCV_Top uut (
        .sys_clk(sys_clk), .rst(rst), .SW_Port(SW_Port), .LED_Port(LED_Port), .RsTx(RsTx),
        .M_AXI_AWADDR(M_AXI_AWADDR), .M_AXI_AWPROT(M_AXI_AWPROT), .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA), .M_AXI_WSTRB(M_AXI_WSTRB), .M_AXI_WVALID(M_AXI_WVALID), .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BRESP(M_AXI_BRESP), .M_AXI_BVALID(M_AXI_BVALID), .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARADDR(M_AXI_ARADDR), .M_AXI_ARPROT(M_AXI_ARPROT), .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RDATA(M_AXI_RDATA), .M_AXI_RRESP(M_AXI_RRESP), .M_AXI_RVALID(M_AXI_RVALID), .M_AXI_RREADY(M_AXI_RREADY)
    );

    initial begin sys_clk = 0; forever #5 sys_clk = ~sys_clk; end
    initial begin rst = 1; SW_Port = 0; #102; rst = 0; end

    // 가짜 메모리 & Slave Logic
    reg [31:0] slave_mem [0:255]; 
    reg [1:0] slave_state;

    reg [3:0] delay_cnt; // 지연 카운터 추가

    always @(posedge sys_clk) begin
        if (rst) begin
            slave_state <= 0; 
            M_AXI_AWREADY <= 0; M_AXI_WREADY <= 0; M_AXI_BVALID <= 0;
            delay_cnt <= 0;
        end else begin
            case (slave_state)
                0: begin // IDLE
                    if (M_AXI_AWVALID || M_AXI_WVALID) begin
                        // 바로 넘어가지 않고, 카운터가 찼는지 확인
                        if (delay_cnt < 4) begin 
                            delay_cnt <= delay_cnt + 1; // 0,1,2,3 -> 4클럭 지연
                        end else begin
                            // 4클럭 기다린 후에야 비로소 READY를 줌
                            M_AXI_AWREADY <= 1; 
                            M_AXI_WREADY <= 1; 
                            slave_state <= 1;
                            delay_cnt <= 0; // 카운터 초기화
                        end
                    end
                end

                1: begin // WRITE & RESP
                    // 여기는 핸드쉐이크니까 빨리 처리 (취향에 따라 여기도 늦출 수 있음)
                    if (M_AXI_AWVALID && M_AXI_AWREADY) M_AXI_AWREADY <= 0;
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        M_AXI_WREADY <= 0;
                        slave_mem[M_AXI_AWADDR[9:2]] <= M_AXI_WDATA;
                    end
                    
                    if (!M_AXI_AWREADY && !M_AXI_WREADY) begin
                         M_AXI_BVALID <= 1; 
                         slave_state <= 2;
                    end
                end

                2: if (M_AXI_BVALID && M_AXI_BREADY) begin // DONE
                       M_AXI_BVALID <= 0; 
                       slave_state <= 0;
                   end
            endcase
        end
    end

    // Slave Read Logic
    always @(posedge sys_clk) begin
        if (rst) begin M_AXI_ARREADY <= 0; M_AXI_RVALID <= 0; end
        else begin
            if (M_AXI_ARVALID && !M_AXI_ARREADY) begin
                M_AXI_ARREADY <= 1; M_AXI_RDATA <= slave_mem[M_AXI_ARADDR[9:2]];
            end else M_AXI_ARREADY <= 0;

            if (M_AXI_ARREADY && M_AXI_ARVALID) M_AXI_RVALID <= 1;
            else if (M_AXI_RREADY && M_AXI_RVALID) M_AXI_RVALID <= 0;
        end
    end
    
    // ---------------------------------------------------------
    // [1] 성능 측정용 변수 선언 (중복 방지를 위해 기존 선언 확인 후 추가)
    // ---------------------------------------------------------
    integer t_start_int = 0;   // 내부 메모리 시작 시간
    integer t_start_mmio = 0;  // MMIO 시작 시간
    integer d_int = 0;         // 내부 메모리 소요 시간
    integer d_mmio = 0;        // MMIO 소요 시간
    reg done_int_flag = 0;     // 측정 완료 플래그
    reg done_mmio_flag = 0;

    // ---------------------------------------------------------
    // [2] 통합 측정 로직
    // ---------------------------------------------------------
    always @(posedge uut.clk) begin
        // Case A: 내부 메모리 쓰기 측정 (PC = 0xC)
        if (uut.pc_curr == 32'h0000000c && t_start_int == 0) begin
            t_start_int = $time;
            $display("[TIME] Internal Dmem Write START at %t", $time);
        end

        // PC가 0x10으로 변하는 그 순간! (내부 메모리 작업이 끝난 시점)
        // Stall 여부와 상관없이 PC의 변화만 체크하여 정확히 10ns를 잡습니다.
        if (uut.pc_curr == 32'h00000010 && t_start_int != 0 && !done_int_flag) begin
            d_int = $time - t_start_int;
            $display("[RESULT] Internal Memory Access Time: %0d ns (Fast!)", d_int);
            
            // [중요] 그와 동시에 MMIO 측정을 바로 시작합니다.
            t_start_mmio = $time;
            $display("[TIME] AXI MMIO Write START at %t", $time);
            done_int_flag = 1; // 내부 메모리 결과는 한 번만 출력
        end

        // Case B: 외부 MMIO 쓰기 측정 (PC = 0x10)
        // PC가 0x14로 넘어가는 순간! (AXI 핸드쉐이크와 Stall이 모두 끝난 시점)
        if (uut.pc_curr == 32'h00000014 && !done_mmio_flag) begin
            if (t_start_mmio != 0) begin
                d_mmio = $time - t_start_mmio;
                // %0d를 사용하여 'x ns'가 아닌 실제 숫자가 찍히도록 합니다.
                $display("[RESULT] AXI MMIO Access Time: %0d ns (%0d Cycles)", d_mmio, d_mmio/10);
                done_mmio_flag = 1; // MMIO 결과도 한 번만 출력
            end
        end
    end
endmodule