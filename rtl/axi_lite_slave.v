// AXI4-Lite slave with 4 x 32-bit read/write registers.
//
// Register map (word-aligned, byte address):
//   0x00 : REG0
//   0x04 : REG1
//   0x08 : REG2
//   0x0C : REG3
//   anything else -> SLVERR (out of range)
//
// AW and W channels are decoupled: address and data may arrive on
// different clock cycles, in either order, as real AXI masters do.
module axi_lite_slave #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  wire                      s_axi_aclk,
    input  wire                      s_axi_aresetn,

    // Write address channel
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,

    // Write data channel
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,

    // Write response channel
    output reg  [1:0]                s_axi_bresp,
    output reg                       s_axi_bvalid,
    input  wire                      s_axi_bready,

    // Read address channel
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire                      s_axi_arvalid,
    output reg                       s_axi_arready,

    // Read data channel
    output reg  [DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                s_axi_rresp,
    output reg                       s_axi_rvalid,
    input  wire                      s_axi_rready
);

    localparam RESP_OKAY  = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    reg [DATA_WIDTH-1:0] reg0, reg1, reg2, reg3;

    // ---- Decoupled AW/W capture ----
    // have_awaddr / have_wdata latch independently as soon as their own
    // channel's valid arrives; the actual register write fires only once
    // both are held, then both are released together for the next txn.
    reg                   have_awaddr, have_wdata;
    reg [ADDR_WIDTH-1:0]  awaddr_r;
    reg [DATA_WIDTH-1:0]  wdata_r;
    reg [(DATA_WIDTH/8)-1:0] wstrb_r;

    wire write_fire = have_awaddr && have_wdata && !s_axi_bvalid;

    assign s_axi_awready = s_axi_awvalid && !have_awaddr;
    assign s_axi_wready  = s_axi_wvalid  && !have_wdata;

    wire aw_in_range = (awaddr_r[ADDR_WIDTH-1:4] == {(ADDR_WIDTH-4){1'b0}});
    wire ar_in_range = (s_axi_araddr[ADDR_WIDTH-1:4] == {(ADDR_WIDTH-4){1'b0}});

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            have_awaddr <= 1'b0;
            awaddr_r    <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (s_axi_awready) begin
                have_awaddr <= 1'b1;
                awaddr_r    <= s_axi_awaddr;
            end else if (write_fire) begin
                have_awaddr <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            have_wdata <= 1'b0;
            wdata_r    <= {DATA_WIDTH{1'b0}};
            wstrb_r    <= {(DATA_WIDTH/8){1'b0}};
        end else begin
            if (s_axi_wready) begin
                have_wdata <= 1'b1;
                wdata_r    <= s_axi_wdata;
                wstrb_r    <= s_axi_wstrb;
            end else if (write_fire) begin
                have_wdata <= 1'b0;
            end
        end
    end

    // ---- Register write (byte-strobe aware) ----
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            reg0 <= {DATA_WIDTH{1'b0}};
            reg1 <= {DATA_WIDTH{1'b0}};
            reg2 <= {DATA_WIDTH{1'b0}};
            reg3 <= {DATA_WIDTH{1'b0}};
        end else if (write_fire && aw_in_range) begin
            case (awaddr_r[3:2])
                2'd0: begin
                    if (wstrb_r[0]) reg0[7:0]   <= wdata_r[7:0];
                    if (wstrb_r[1]) reg0[15:8]  <= wdata_r[15:8];
                    if (wstrb_r[2]) reg0[23:16] <= wdata_r[23:16];
                    if (wstrb_r[3]) reg0[31:24] <= wdata_r[31:24];
                end
                2'd1: begin
                    if (wstrb_r[0]) reg1[7:0]   <= wdata_r[7:0];
                    if (wstrb_r[1]) reg1[15:8]  <= wdata_r[15:8];
                    if (wstrb_r[2]) reg1[23:16] <= wdata_r[23:16];
                    if (wstrb_r[3]) reg1[31:24] <= wdata_r[31:24];
                end
                2'd2: begin
                    if (wstrb_r[0]) reg2[7:0]   <= wdata_r[7:0];
                    if (wstrb_r[1]) reg2[15:8]  <= wdata_r[15:8];
                    if (wstrb_r[2]) reg2[23:16] <= wdata_r[23:16];
                    if (wstrb_r[3]) reg2[31:24] <= wdata_r[31:24];
                end
                2'd3: begin
                    if (wstrb_r[0]) reg3[7:0]   <= wdata_r[7:0];
                    if (wstrb_r[1]) reg3[15:8]  <= wdata_r[15:8];
                    if (wstrb_r[2]) reg3[23:16] <= wdata_r[23:16];
                    if (wstrb_r[3]) reg3[31:24] <= wdata_r[31:24];
                end
            endcase
        end
    end

    // ---- Write response channel ----
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
        end else begin
            if (write_fire) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= aw_in_range ? RESP_OKAY : RESP_SLVERR;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---- Read address channel ----
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
        end else begin
            s_axi_arready <= s_axi_arvalid && !s_axi_arready && !s_axi_rvalid;
        end
    end

    // ---- Read data channel ----
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rdata  <= {DATA_WIDTH{1'b0}};
        end else begin
            if (s_axi_arready && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                if (ar_in_range) begin
                    s_axi_rresp <= RESP_OKAY;
                    case (s_axi_araddr[3:2])
                        2'd0: s_axi_rdata <= reg0;
                        2'd1: s_axi_rdata <= reg1;
                        2'd2: s_axi_rdata <= reg2;
                        2'd3: s_axi_rdata <= reg3;
                    endcase
                end else begin
                    s_axi_rresp <= RESP_SLVERR;
                    s_axi_rdata <= {DATA_WIDTH{1'b0}};
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // ---- Protocol assertions ----
    // AXI4-Lite requires that once a channel's VALID is asserted by its
    // driver, VALID and the payload must hold stable until the READY
    // handshake completes -- the driver may not "give up" and change its
    // mind mid-transaction. BVALID/RVALID are driven by this slave, so
    // these are self-checks on our own compliance.
    //
    // NOTE: this Icarus Verilog build doesn't parse concurrent SVA
    // (`property` / `assert property` with `|=>`, `$stable`), so the same
    // "stable until handshake" checks are hand-rolled here as immediate
    // assertions over a one-cycle-delayed shadow of each channel.

    reg       prev_bvalid, prev_bready;
    reg [1:0] prev_bresp;
    reg       prev_rvalid, prev_rready;
    reg [DATA_WIDTH-1:0] prev_rdata;
    reg [1:0]            prev_rresp;

    always @(posedge s_axi_aclk) begin
        if (s_axi_aresetn) begin
            // P1: once BVALID is up, it (and BRESP) must stay stable until BREADY.
            if (prev_bvalid && !prev_bready) begin
                assert (s_axi_bvalid && s_axi_bresp === prev_bresp)
                    else $error("[ASSERT] BVALID/BRESP changed while waiting for BREADY");
            end

            // P2: once RVALID is up, it (and RDATA/RRESP) must stay stable until RREADY.
            if (prev_rvalid && !prev_rready) begin
                assert (s_axi_rvalid && s_axi_rdata === prev_rdata && s_axi_rresp === prev_rresp)
                    else $error("[ASSERT] RVALID/RDATA/RRESP changed while waiting for RREADY");
            end

            // P3: RDATA must be a defined value whenever RVALID is asserted.
            if (s_axi_rvalid) begin
                assert (!$isunknown(s_axi_rdata))
                    else $error("[ASSERT] RDATA is X/Z while RVALID is asserted");
            end
        end

        prev_bvalid <= s_axi_bvalid;
        prev_bready <= s_axi_bready;
        prev_bresp  <= s_axi_bresp;
        prev_rvalid <= s_axi_rvalid;
        prev_rready <= s_axi_rready;
        prev_rdata  <= s_axi_rdata;
        prev_rresp  <= s_axi_rresp;
    end

endmodule
