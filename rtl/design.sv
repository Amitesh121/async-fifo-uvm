// Code your design here
`timescale 1ns/1ps

// -------------------------------------------------------------
// Top-Level Asynchronous FIFO
// -------------------------------------------------------------
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4  // Depth = 2^ADDR_WIDTH = 16
)(
    // Write Domain
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,

    // Read Domain
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty
);

    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0]   wptr, rptr;
    logic [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr;

    // Dual-Port RAM Memory
    fifo_mem #(DATA_WIDTH, ADDR_WIDTH) u_mem (
        .wclk   (wclk),
        .winc   (winc),
        .wfull  (wfull),
        .waddr  (waddr),
        .wdata  (wdata),
        .raddr  (raddr),
        .rdata  (rdata)
    );

    // 2-FF Synchronizer: Read Pointer to Write Domain
    sync_ptr #(ADDR_WIDTH) u_sync_r2w (
        .clk      (wclk),
        .rst_n    (wrst_n),
        .ptr_in   (rptr),
        .ptr_out  (wq2_rptr)
    );

    // 2-FF Synchronizer: Write Pointer to Read Domain
    sync_ptr #(ADDR_WIDTH) u_sync_w2r (
        .clk      (rclk),
        .rst_n    (rrst_n),
        .ptr_in   (wptr),
        .ptr_out  (rq2_wptr)
    );

    // Write Domain Controller & Full Flag Logic
    fifo_wr_ctrl #(ADDR_WIDTH) u_wr_ctrl (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .winc     (winc),
        .wq2_rptr (wq2_rptr),
        .waddr    (waddr),
        .wptr     (wptr),
        .wfull    (wfull)
    );

    // Read Domain Controller & Empty Flag Logic
    fifo_rd_ctrl #(ADDR_WIDTH) u_rd_ctrl (
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .rinc     (rinc),
        .rq2_wptr (rq2_wptr),
        .raddr    (raddr),
        .rptr     (rptr),
        .rempty   (rempty)
    );

endmodule

// -------------------------------------------------------------
// FIFO Dual-Port Memory
// -------------------------------------------------------------
module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  logic                  wclk,
    input  logic                  winc,
    input  logic                  wfull,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge wclk) begin
        if (winc && !wfull)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];
endmodule

// -------------------------------------------------------------
// 2-Flip-Flop Synchronizer for Pointer Domain Crossing
// -------------------------------------------------------------
module sync_ptr #(
    parameter ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [ADDR_WIDTH:0]   ptr_in,
    output logic [ADDR_WIDTH:0]   ptr_out
);
    logic [ADDR_WIDTH:0] q1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q1      <= '0;
            ptr_out <= '0;
        end else begin
            q1      <= ptr_in;
            ptr_out <= q1;
        end
    end
endmodule

// -------------------------------------------------------------
// Write Control: Gray pointer generation & Full flag
// -------------------------------------------------------------
module fifo_wr_ctrl #(
    parameter ADDR_WIDTH = 4
)(
    input  logic                wclk,
    input  logic                wrst_n,
    input  logic                winc,
    input  logic [ADDR_WIDTH:0] wq2_rptr,
    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0]   wptr,
    output logic                  wfull
);
    logic [ADDR_WIDTH:0] wbin;
    logic [ADDR_WIDTH:0] wbin_next, wgray_next;
    logic                wfull_val;

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= '0;
            wptr  <= '0;
            wfull <= '0;
        end else begin
            wbin  <= wbin_next;
            wptr  <= wgray_next;
            wfull <= wfull_val;
        end
    end

    assign wbin_next  = wbin + (winc & ~wfull);
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;
    assign waddr      = wbin[ADDR_WIDTH-1:0];

    // Full condition: MSBs inverted, remaining bits identical
    assign wfull_val = (wgray_next == {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1], wq2_rptr[ADDR_WIDTH-2:0]});
endmodule

// -------------------------------------------------------------
// Read Control: Gray pointer generation & Empty flag
// -------------------------------------------------------------
module fifo_rd_ctrl #(
    parameter ADDR_WIDTH = 4
)(
    input  logic                rclk,
    input  logic                rrst_n,
    input  logic                rinc,
    input  logic [ADDR_WIDTH:0] rq2_wptr,
    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0]   rptr,
    output logic                  rempty
);
    logic [ADDR_WIDTH:0] rbin;
    logic [ADDR_WIDTH:0] rbin_next, rgray_next;
    logic                rempty_val;

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= '0;
            rptr   <= '0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rptr   <= rgray_next;
            rempty <= rempty_val;
        end
    end

    assign rbin_next  = rbin + (rinc & ~rempty);
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;
    assign raddr      = rbin[ADDR_WIDTH-1:0];

    // Empty condition: Pointers are completely equal
    assign rempty_val = (rgray_next == rq2_wptr);
endmodule