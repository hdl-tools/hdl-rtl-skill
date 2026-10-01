//=============================================================================
// golden_counter.sv -- parameterised up-counter with saturate or wrap
//-----------------------------------------------------------------------------
// Purpose        : Reference synchronous counter. The canonical shape for any
//                  _q/_d sequential element with a synchronous load and an
//                  explicit overflow contract.
// When to use    : Any counter, timer, timeout, credit counter, or address
//                  generator. Start here rather than writing one from scratch.
// Review focus   : Width Review (does WIDTH hold MAX_COUNT?), Arithmetic
//                  Review (wrap vs saturate is a SPEC decision, never a
//                  default), Reset Review (counter must reset to a known
//                  value), Parameter Review (WIDTH=0, MAX_COUNT=0 edges).
// Common mistakes: 1. Letting the counter wrap when the spec wanted saturate
//                     -- silent, and only shows up as a corrupted address.
//                  2. WIDTH too small for MAX_COUNT, so the terminal count is
//                     never reached and a timeout hangs forever.
//                  3. Comparing count_q == MAX_COUNT with a differently signed
//                     or wider constant -> -Wsign-compare / -Wwidth-trunc.
//                  4. Forgetting that incr_i and load_i can arrive together.
// Retrieval       : counter, timer, timeout, tick, credit, address generator,
//   triggers      : up-counter, down-counter, saturating counter, wrap
//=============================================================================
`default_nettype none

module golden_counter #(
    // Counter width in bits. Must be large enough to represent MAX_COUNT.
    parameter int unsigned WIDTH     = 8,
    // Terminal count. The counter wraps or saturates here per SATURATE.
    parameter int unsigned MAX_COUNT = (2 ** WIDTH) - 1,
    // 1 = hold at MAX_COUNT, 0 = wrap to zero. No default is "safe": pick one.
    parameter bit          SATURATE  = 1'b0
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clear_i,              // synchronous clear to zero
    input  wire              incr_i,               // count enable
    input  wire              load_i,               // synchronous load, wins
    input  wire  [WIDTH-1:0] load_value_i,
    output logic [WIDTH-1:0] count_q,
    output logic             at_max_o              // count_q == MAX_COUNT
);

  // Elaboration-time guards. These fail the build instead of producing a
  // counter that silently cannot reach its own terminal count. Guarded so the
  // check runs at elaboration and never becomes synthesised logic.
  // synthesis translate_off
  initial begin
    if (WIDTH == 0)
      $fatal(1, "golden_counter: WIDTH must be >= 1");
    if (MAX_COUNT > ((2 ** WIDTH) - 1))
      $fatal(1, "golden_counter: MAX_COUNT=%0d does not fit in WIDTH=%0d",
             MAX_COUNT, WIDTH);
  end
  // synthesis translate_on

  logic [WIDTH-1:0] count_d;

  assign at_max_o = (count_q == WIDTH'(MAX_COUNT));

  // Next-state is pure combinational and total: every path assigns count_d,
  // so no latch can be inferred. Priority is explicit: clear > load > incr.
  always_comb begin
    count_d = count_q;
    if (clear_i) begin
      count_d = '0;
    end else if (load_i) begin
      count_d = load_value_i;
    end else if (incr_i) begin
      if (at_max_o) begin
        count_d = SATURATE ? count_q : '0;
      end else begin
        count_d = count_q + WIDTH'(1'b1);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_q <= '0;
    end else begin
      count_q <= count_d;
    end
  end

endmodule

`default_nettype wire
