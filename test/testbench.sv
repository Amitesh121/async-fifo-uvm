`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// -------------------------------------------------------------
// 1. Interfaces
// -------------------------------------------------------------
interface fifo_if (
    input logic wclk,
    input logic rclk
);
    logic        wrst_n;
    logic        winc;
    logic [7:0]  wdata;
    logic        wfull;

    logic        rrst_n;
    logic        rinc;
    logic [7:0]  rdata;
    logic        rempty;
endinterface

// -------------------------------------------------------------
// 2. Transaction Sequence Item
// -------------------------------------------------------------
class fifo_item extends uvm_sequence_item;
    rand logic [7:0] data;
    rand bit         is_write;
    rand bit         is_read;

    `uvm_object_utils_begin(fifo_item)
        `uvm_field_int(data, UVM_ALL_ON)
        `uvm_field_int(is_write, UVM_ALL_ON)
        `uvm_field_int(is_read, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "fifo_item");
        super.new(name);
    endfunction
endclass

// -------------------------------------------------------------
// 3. Sequences
// -------------------------------------------------------------
class fifo_burst_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_burst_seq)

    function new(string name = "fifo_burst_seq");
        super.new(name);
    endfunction

    virtual task body();
        fifo_item item;
        
        `uvm_info("SEQ", "Starting Write Burst Sequence...", UVM_LOW)
        repeat (20) begin
            item = fifo_item::type_id::create("item");
            start_item(item);
            assert(item.randomize() with { is_write == 1; is_read == 0; });
            finish_item(item);
        end

        `uvm_info("SEQ", "Starting Read Sequence...", UVM_LOW)
        repeat (20) begin
            item = fifo_item::type_id::create("item");
            start_item(item);
            assert(item.randomize() with { is_write == 0; is_read == 1; });
            finish_item(item);
        end
    endtask
endclass

// -------------------------------------------------------------
// 4. Driver
// -------------------------------------------------------------
class fifo_driver extends uvm_driver #(fifo_item);
    `uvm_component_utils(fifo_driver)
    virtual fifo_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Could not get vif from config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.winc  <= 0;
        vif.rinc  <= 0;
        vif.wdata <= 0;

        forever begin
            seq_item_port.get_next_item(req);
            if (req.is_write) begin
                @(posedge vif.wclk);
                if (!vif.wfull) begin
                    vif.winc  <= 1;
                    vif.wdata <= req.data;
                end
                @(posedge vif.wclk);
                vif.winc <= 0;
            end 
            else if (req.is_read) begin
                @(posedge vif.rclk);
                if (!vif.rempty) begin
                    vif.rinc <= 1;
                end
                @(posedge vif.rclk);
                vif.rinc <= 0;
            end
            seq_item_port.item_done();
        end
    endtask
endclass

// -------------------------------------------------------------
// 5. Monitor
// -------------------------------------------------------------
class fifo_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_monitor)
    virtual fifo_if vif;
    uvm_analysis_port #(fifo_item) wr_ap;
    uvm_analysis_port #(fifo_item) rd_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        wr_ap = new("wr_ap", this);
        rd_ap = new("rd_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Could not get vif from config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
        fork
            // Monitor Write Domain
            begin : wr_mon_proc
                fifo_item wr_item;
                forever begin
                    @(posedge vif.wclk);
                    if (vif.winc && !vif.wfull) begin
                        wr_item = fifo_item::type_id::create("wr_item");
                        wr_item.data = vif.wdata;
                        wr_item.is_write = 1;
                        wr_item.is_read  = 0;
                        wr_ap.write(wr_item);
                    end
                end
            end

            // Monitor Read Domain
            begin : rd_mon_proc
                fifo_item rd_item;
                forever begin
                    @(posedge vif.rclk);
                    if (vif.rinc && !vif.rempty) begin
                        #1ps; // Wait for memory read data stability
                        rd_item = fifo_item::type_id::create("rd_item");
                        rd_item.data = vif.rdata;
                        rd_item.is_read  = 1;
                        rd_item.is_write = 0;
                        rd_ap.write(rd_item);
                    end
                end
            end
        join
    endtask
endclass

// -------------------------------------------------------------
// 6. Scoreboard
// -------------------------------------------------------------
`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)

class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)

    uvm_analysis_imp_wr #(fifo_item, fifo_scoreboard) wr_export;
    uvm_analysis_imp_rd #(fifo_item, fifo_scoreboard) rd_export;

    logic [7:0] queue_model[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        wr_export = new("wr_export", this);
        rd_export = new("rd_export", this);
    endfunction

    function void write_wr(fifo_item item);
        queue_model.push_back(item.data);
        `uvm_info("SCB_WR", $sformatf("Pushed to ref model: 0x%0h (Model depth: %0d)", item.data, queue_model.size()), UVM_HIGH)
    endfunction

    function void write_rd(fifo_item item);
        logic [7:0] expected;
        if (queue_model.size() == 0) begin
            `uvm_error("SCB_ERR", "Read transaction triggered when reference queue is EMPTY!")
            return;
        end
        expected = queue_model.pop_front();
        if (expected === item.data) begin
            `uvm_info("SCB_PASS", $sformatf("MATCH: Got 0x%0h == Expected 0x%0h", item.data, expected), UVM_LOW)
        end else begin
            `uvm_error("SCB_MISMATCH", $sformatf("MISMATCH: Got 0x%0h, Expected 0x%0h", item.data, expected))
        end
    endfunction
endclass

// -------------------------------------------------------------
// 7. Environment & Agent
// -------------------------------------------------------------
class fifo_agent extends uvm_agent;
    `uvm_component_utils(fifo_agent)
    fifo_driver                driver;
    fifo_monitor               monitor;
    uvm_sequencer #(fifo_item) sequencer;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver    = fifo_driver::type_id::create("driver", this);
        monitor   = fifo_monitor::type_id::create("monitor", this);
        sequencer = uvm_sequencer#(fifo_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass

class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)
    fifo_agent      agent;
    fifo_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = fifo_agent::type_id::create("agent", this);
        scoreboard = fifo_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.wr_ap.connect(scoreboard.wr_export);
        agent.monitor.rd_ap.connect(scoreboard.rd_export);
    endfunction
endclass

// -------------------------------------------------------------
// 8. Test Class
// -------------------------------------------------------------
class fifo_test extends uvm_test;
    `uvm_component_utils(fifo_test)
    fifo_env env;

    function new(string name = "fifo_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = fifo_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        fifo_burst_seq seq;
        phase.raise_objection(this);
        seq = fifo_burst_seq::type_id::create("seq");
        seq.start(env.agent.sequencer);
        #200ns;
        phase.drop_objection(this);
    endtask
endclass

// -------------------------------------------------------------
// 9. Top-Level Testbench Module
// -------------------------------------------------------------
module tb_top;
    logic wclk = 0;
    logic rclk = 0;

    // Asynchronous clocks: wclk = 100MHz (10ns period), rclk = 66.6MHz (15ns period)
    always #5.0ns wclk = ~wclk;
    always #7.5ns rclk = ~rclk;

    fifo_if vif(wclk, rclk);

    // DUT Instantiation
    async_fifo #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(4)
    ) dut (
        .wclk   (vif.wclk),
        .wrst_n (vif.wrst_n),
        .winc   (vif.winc),
        .wdata  (vif.wdata),
        .wfull  (vif.wfull),

        .rclk   (vif.rclk),
        .rrst_n (vif.rrst_n),
        .rinc   (vif.rinc),
        .rdata  (vif.rdata),
        .rempty (vif.rempty)
    );

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);

        vif.wrst_n = 0;
        vif.rrst_n = 0;
        #30ns;
        vif.wrst_n = 1;
        vif.rrst_n = 1;

        uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
        run_test("fifo_test");
    end
endmodule