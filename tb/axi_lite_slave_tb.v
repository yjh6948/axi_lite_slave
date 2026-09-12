`timescale 1ns / 1ps

module axi_lite_slave_tb;

    localparam ADDR_WIDTH = 8;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    reg                       aclk;
    reg                       aresetn;

    reg  [ADDR_WIDTH-1:0]     awaddr;
    reg                       awvalid;
    wire                      awready;

    reg  [DATA_WIDTH-1:0]     wdata;
    reg  [(DATA_WIDTH/8)-1:0] wstrb;
    reg                       wvalid;
    wire                      wready;

    wire [1:0]                bresp;
    wire                      bvalid;
    reg                       bready;

    reg  [ADDR_WIDTH-1:0]     araddr;
    reg                       arvalid;
    wire                      arready;

    wire [DATA_WIDTH-1:0]     rdata;
    wire [1:0]                rresp;
    wire                      rvalid;
    reg                       rready;

    integer errors = 0;
    integer i;

    axi_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .s_axi_aclk(aclk),
        .s_axi_aresetn(aresetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready)
    );

    always #(CLK_PERIOD / 2) aclk = ~aclk;

    // ---- Low-level channel drivers (independent AW / W) ----
    task drive_aw(input [ADDR_WIDTH-1:0] addr);
        begin
            @(posedge aclk);
            awaddr  <= addr;
            awvalid <= 1'b1;
            @(posedge aclk);
            while (!awready) @(posedge aclk);
            awvalid <= 1'b0;
        end
    endtask

    task drive_w(input [DATA_WIDTH-1:0] data, input [(DATA_WIDTH/8)-1:0] strb);
        begin
            @(posedge aclk);
            wdata  <= data;
            wstrb  <= strb;
            wvalid <= 1'b1;
            @(posedge aclk);
            while (!wready) @(posedge aclk);
            wvalid <= 1'b0;
        end
    endtask

    task wait_bresp(output [1:0] resp);
        begin
            bready <= 1'b1;
            while (!bvalid) @(posedge aclk);
            resp = bresp;
            @(posedge aclk);
            bready <= 1'b0;
        end
    endtask

    // Standard write: AW and W asserted the same cycle
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data,
                    input [(DATA_WIDTH/8)-1:0] strb, output [1:0] resp);
        begin
            fork
                drive_aw(addr);
                drive_w(data, strb);
            join
            wait_bresp(resp);
        end
    endtask

    task axi_read(input [ADDR_WIDTH-1:0] addr, output [DATA_WIDTH-1:0] data, output [1:0] resp);
        begin
            @(posedge aclk);
            araddr  <= addr;
            arvalid <= 1'b1;
            rready  <= 1'b1;
            @(posedge aclk);
            while (!arready) @(posedge aclk);
            arvalid <= 1'b0;
            while (!rvalid) @(posedge aclk);
            data = rdata;
            resp = rresp;
            @(posedge aclk);
            rready <= 1'b0;
        end
    endtask

    task check(input [DATA_WIDTH-1:0] expected, input [DATA_WIDTH-1:0] actual, input [200:0] name);
        begin
            if (expected !== actual) begin
                $display("FAIL [%0s]: expected 0x%08h, got 0x%08h", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]: 0x%08h", name, actual);
            end
        end
    endtask

    task check_resp(input [1:0] expected, input [1:0] actual, input [200:0] name);
        begin
            if (expected !== actual) begin
                $display("FAIL [%0s]: expected resp %0b, got %0b", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]: resp %0b", name, actual);
            end
        end
    endtask

    reg [DATA_WIDTH-1:0] read_val;
    reg [1:0]            resp_val;

    initial begin
        $dumpfile("axi_lite_slave_tb.vcd");
        $dumpvars(0, axi_lite_slave_tb);

        aclk    = 0;
        aresetn = 0;
        awaddr  = 0; awvalid = 0;
        wdata   = 0; wstrb = 0; wvalid = 0;
        bready  = 0;
        araddr  = 0; arvalid = 0;
        rready  = 0;

        repeat (5) @(posedge aclk);
        aresetn = 1;
        repeat (5) @(posedge aclk);

        // --- 1. Basic full-word write/read to each register ---
        axi_write(8'h00, 32'hDEADBEEF, 4'b1111, resp_val);
        check_resp(RESP_OKAY, resp_val, "REG0 write resp");
        axi_read(8'h00, read_val, resp_val);
        check(32'hDEADBEEF, read_val, "REG0 full write");

        axi_write(8'h04, 32'h12345678, 4'b1111, resp_val);
        axi_read(8'h04, read_val, resp_val);
        check(32'h12345678, read_val, "REG1 full write");

        // --- 2. Byte-strobe partial write ---
        axi_write(8'h0C, 32'hFFFFFF5A, 4'b0001, resp_val);
        axi_read(8'h0C, read_val, resp_val);
        check(32'h0000005A, read_val, "REG3 byte-strobe write");

        // --- 3. Decoupled AW/W: address arrives, then data much later ---
        fork
            drive_aw(8'h08);
            begin
                repeat (7) @(posedge aclk); // data lags address by several cycles
                drive_w(32'hCAFEF00D, 4'b1111);
            end
        join
        wait_bresp(resp_val);
        check_resp(RESP_OKAY, resp_val, "decoupled AW-first resp");
        axi_read(8'h08, read_val, resp_val);
        check(32'hCAFEF00D, read_val, "decoupled AW-first data");

        // --- 4. Decoupled AW/W: data arrives, then address much later ---
        fork
            drive_w(32'h11223344, 4'b1111);
            begin
                repeat (7) @(posedge aclk); // address lags data by several cycles
                drive_aw(8'h00);
            end
        join
        wait_bresp(resp_val);
        check_resp(RESP_OKAY, resp_val, "decoupled W-first resp");
        axi_read(8'h00, read_val, resp_val);
        check(32'h11223344, read_val, "decoupled W-first data");

        // --- 5. Out-of-range address -> SLVERR, register unchanged ---
        axi_write(8'h40, 32'hBADBADBA, 4'b1111, resp_val);
        check_resp(RESP_SLVERR, resp_val, "OOB write resp");
        axi_read(8'h40, read_val, resp_val);
        check_resp(RESP_SLVERR, resp_val, "OOB read resp");

        // --- 6. Backpressure: master delays BREADY/RREADY ---
        @(posedge aclk);
        awaddr <= 8'h04; awvalid <= 1'b1;
        wdata  <= 32'hA5A5A5A5; wstrb <= 4'b1111; wvalid <= 1'b1;
        bready <= 1'b0; // not ready yet
        @(posedge aclk);
        while (!(awready && wready)) @(posedge aclk);
        awvalid <= 1'b0; wvalid <= 1'b0;
        repeat (4) @(posedge aclk); // hold off BREADY, bvalid must stay asserted
        if (!bvalid) begin
            $display("FAIL [backpressure]: bvalid dropped before bready was asserted");
            errors = errors + 1;
        end else begin
            $display("PASS [backpressure]: bvalid held while bready low");
        end
        bready <= 1'b1;
        @(posedge aclk);
        bready <= 1'b0;
        axi_read(8'h04, read_val, resp_val);
        check(32'hA5A5A5A5, read_val, "backpressure write landed");

        // --- 7. Back-to-back writes, no idle gap between transactions ---
        for (i = 0; i < 4; i = i + 1) begin
            axi_write(8'h00, i, 4'b1111, resp_val);
        end
        axi_read(8'h00, read_val, resp_val);
        check(32'd3, read_val, "back-to-back final value");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
