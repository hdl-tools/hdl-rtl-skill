//=============================================================================
// golden_fifo_sync.sv -- single-clock synchronous FIFO
//-----------------------------------------------------------------------------
// Purpose        : Buffer a stream within ONE clock domain. Uses the extra
//                  pointer bit trick so that full and empty are distinguished
//                  without a separate counter that can drift out of sync.
// When to use    : Rate matching, burst absorption, or decoupling producer and
//                  consumer inside a single clock domain.
//                  If the two sides have DIFFERENT clocks, this module is
//                  WRONG and will corrupt data -- use golden_fifo_async.sv.
// Review focus   : Width Review (ADDR_W derived, never hand-typed), FIFO
//                  overflow/underflow protection, Reset Review (both pointers
//                  must clear together -- a half-reset FIFO reports a bogus
//                  level), Parameter Review (DEPTH=1, DEPTH=2, non-power-of-2).
// Common mistakes: 1. full/empty from a separate count register that is
//                     incremented and decremented in different branches, so a
//                     simultaneous read+write loses a count.
//                  2. Pointers sized $clog2(DEPTH) instead of $clog2(DEPTH)+1,
//                     making full and empty indistinguishable.
//                  3. Accepting a write when full, or a read when empty, and
//                     silently corrupting the pointer.
//                  4. Non-power-of-two DEPTH with wrap-by-truncation pointers.
// Retrieval       : fifo, sync fifo, synchronous fifo, queue, buffer, ring
//   triggers      : buffer, circular buffer, rate matching, elastic store
//=============================================================================
`default_nettype none

module golden_fifo_sync #(
    parameter int unsigned WIDTH = 32,
    // MUST be a power of two. Enforced at elaboration below.
    parameter int unsigned DEPTH = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              wr_en_i,
    input  wire  [WIDTH-1:0] wr_data_i,
    output logic             full_o,
    input  wire              rd_en_i,
    output logic [WIDTH-1:0] rd_data_o,
    output logic             empty_o,
    output logic [$clog2(DEPTH):0] count_o
);

  localparam int unsigned ADDR_W = $clog2(DEPTH);

  initial begin
    if (DEPTH < 2)
      $fatal(1, "golden_fifo_sync: DEPTH must be >= 2 (got %0d)", DEPTH);
    if ((DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "golden_fifo_sync: DEPTH must be a power of two (got %0d)",
             DEPTH);
  end

  logic [WIDTH-1:0] mem [DEPTH];

  // One bit WIDER than the address. That extra bit is what separates "wrapped
  // once more than the reader" (full) from "same position" (empty).
  logic [ADDR_W:0] wr_ptr_q;
  logic [ADDR_W:0] rd_ptr_q;

  logic do_write;
  logic do_read;

  // Guarded: a write when full or a read when empty is ignored, not silently
  // allowed to corrupt the pointer.
  assign do_write = wr_en_i && !full_o;
  assign do_read  = rd_en_i && !empty_o;

  assign empty_o = (wr_ptr_q == rd_ptr_q);
  assign full_o  = (wr_ptr_q[ADDR_W] != rd_ptr_q[ADDR_W]) &&
                   (wr_ptr_q[ADDR_W-1:0] == rd_ptr_q[ADDR_W-1:0]);

  // Occupancy from the pointer difference -- a single source of truth, so it
  // cannot drift out of step with full_o/empty_o the way a separate
  // up/down counter can.
  assign count_o = wr_ptr_q - rd_ptr_q;

  // Combinational (first-word-fall-through) read: data is valid in the same
  // cycle empty_o is low. If your flow needs a registered read port, register
  // rd_data_o and remember that empty_o then leads the data by one cycle.
  assign rd_data_o = mem[rd_ptr_q[ADDR_W-1:0]];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else begin
      if (do_write) begin
        wr_ptr_q <= wr_ptr_q + {{ADDR_W{1'b0}}, 1'b1};
      end
      if (do_read) begin
        rd_ptr_q <= rd_ptr_q + {{ADDR_W{1'b0}}, 1'b1};
      end
    end
  end

  // Memory has no reset: resetting a RAM is expensive and unnecessary because
  // the pointers guarantee no location is read before it is written.
  always_ff @(posedge clk) begin
    if (do_write) begin
      mem[wr_ptr_q[ADDR_W-1:0]] <= wr_data_i;
    end
  end

endmodule

`default_nettype wire
