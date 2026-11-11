# Dual-Clock Asynchronous FIFO with UVM Verification

A parameterizable Dual-Clock Asynchronous FIFO implemented in SystemVerilog, designed for safe Clock Domain Crossing (CDC) and verified using a comprehensive UVM 1.2 testbench environment.

## Architecture
- **Clock Domain Crossing (CDC):** Uses 2-stage D flip-flop synchronizers.
- **Pointers:** Binary counters converted to Gray code to ensure single-bit transitions across clock domains.
- **Flag Logic:** Pessimistic full and empty detection ensuring zero overflow or underflow.

## Verification Environment (UVM 1.2)
- **Driver & Monitor:** Domain-specific signal driving and passive bus monitoring.
- **Scoreboard:** Golden reference queue model comparing written vs. read data integrity in-order.
- **Test Scenarios:** Burst writes to saturation, back-to-back reads, and variable asynchronous clock ratios.

## How to Run
Run online via [EDA Playground](https://www.edaplayground.com/) using Synopsys VCS or Aldec Riviera-PRO with UVM 1.2 enabled.
