//=============================================================================
// golden_counter.v -- Verilog-2001 dialect of golden_counter.sv
//-----------------------------------------------------------------------------
// Purpose        : Same counter contract as golden_counter.sv, for codebases
//                  locked to Verilog-2001 (older synthesis flows, some FPGA
//                  toolchains, legacy IP that must stay .v).
// When to use    : ONLY when SystemVerilog is unavailable. The .sv version is
//                  strictly safer: always_ff and always_comb let the tool
//                  prove intent that plain always blocks cannot.
// Review focus   : Everything from the .sv version, PLUS the checks the
//                  language no longer does for you -- sensitivity lists,
//                  accidental latches in always @*, reg-vs-wire misuse.
// Common mistakes: 1. always @(posedge clk) with an incomplete reset branch.
//                  2. always @(a or b) sensitivity list missing a signal
//                     -- simulates wrong, synthesises right. Use always @*.
//                  3. Declaring a combinational output as wire and then
//                     assigning it inside an always block.
// Retrieval       : counter verilog, counter .v, verilog-2001 counter,
//   triggers      : legacy counter, non-systemverilog counter
//=============================================================================
`default_nettype none

module golden_counter #(
    parameter WIDTH     = 8,
    parameter MAX_COUNT = (1 << WIDTH) - 1,
    parameter SATURATE  = 0
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clear_i,
    input  wire              incr_i,
    input  wire              load_i,
    input  wire  [WIDTH-1:0] load_value_i,
    output reg   [WIDTH-1:0] count_q,
    output wire              at_max_o
);

  // synthesis translate_off
  initial begin
    if (WIDTH < 1) begin
      $display("FATAL golden_counter: WIDTH must be >= 1");
      $finish;
    end
  end
  // synthesis translate_on

  wire [WIDTH-1:0] max_count_w = MAX_COUNT[WIDTH-1:0];

  assign at_max_o = (count_q == max_count_w);

  // always @* -- NOT always @(signal list). An explicit list is the single
  // most common source of sim/synth mismatch in Verilog-2001.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_q <= {WIDTH{1'b0}};
    end else if (clear_i) begin
      count_q <= {WIDTH{1'b0}};
    end else if (load_i) begin
      count_q <= load_value_i;
    end else if (incr_i) begin
      if (at_max_o) begin
        count_q <= (SATURATE != 0) ? count_q : {WIDTH{1'b0}};
      end else begin
        count_q <= count_q + {{(WIDTH-1){1'b0}}, 1'b1};
      end
    end
  end

endmodule

`default_nettype wire
