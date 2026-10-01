//=============================================================================
// golden_rr_arbiter.sv -- round-robin arbiter, provably starvation-free
//-----------------------------------------------------------------------------
// Purpose        : Grant a shared resource to one of N requesters so that no
//                  requester can be starved. A continuously asserted request
//                  is granted within at most N grants.
// When to use    : Shared bus, shared memory port, shared DMA channel, output
//                  port of a crossbar -- anywhere more than one agent competes
//                  and fairness matters.
// Review focus   : Arbitration fairness (walk the mask update by hand for the
//                  wrap case), Protocol Review (grant must be one-hot, and
//                  must only advance when the grant is actually consumed),
//                  Reset Review (mask must reset to all-ones so the first
//                  arbitration is well defined), Parameter Review (N=1, N=2).
// Common mistakes: 1. *** Fixed priority dressed up as round robin. *** A
//                     plain priority encoder over req_i starves requester N-1
//                     whenever requester 0 is always asserting. This is the
//                     single most common arbiter bug and it only shows up
//                     under sustained load, i.e. never in a directed test.
//                  2. Rotating the pointer every cycle instead of only when
//                     the grant is consumed (update_i). The pointer then races
//                     ahead of the actual grants and fairness is lost.
//                  3. Mask reset to zero, so the first arbitration after reset
//                     silently falls through to the unmasked path.
//                  4. Grant not one-hot because the two priority paths are
//                     OR-ed instead of being mutually exclusive.
//                  5. Granting to a requester that has since deasserted.
// Retrieval       : arbiter, round robin, round-robin, rr arbiter, fairness,
//   triggers      : starvation, priority encoder, grant, request grant,
//                   shared bus arbitration, crossbar arbitration
//=============================================================================
`default_nettype none

module golden_rr_arbiter #(
    parameter int unsigned N = 4
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire  [N-1:0] req_i,
    // Advance the rotation ONLY when the granted agent actually used its turn.
    // Tie high if a grant is always consumed in the same cycle.
    input  wire          update_i,
    output logic [N-1:0] grant_o,
    output logic         grant_valid_o
);

  // Guarded so the check runs at elaboration and never becomes synthesised
  // logic.
  // synthesis translate_off
  initial begin
    if (N < 1)
      $fatal(1, "golden_rr_arbiter: N must be >= 1 (got %0d)", N);
  end
  // synthesis translate_on

  // Isolate the lowest set bit: x & (-x). Produces a one-hot result, or zero
  // when x is zero. This is what makes grant_o one-hot by construction rather
  // than by review.
  function automatic logic [N-1:0] lowest_one(input logic [N-1:0] x);
    return x & (~x + {{(N-1){1'b0}}, 1'b1});
  endfunction

  // mask_q holds the requesters at or above the current rotation point.
  // All ones at reset => the first arbitration behaves as plain lowest-index.
  logic [N-1:0] mask_q;
  logic [N-1:0] masked_req;
  logic [N-1:0] grant_masked;
  logic [N-1:0] grant_unmasked;

  assign masked_req     = req_i & mask_q;
  assign grant_masked   = lowest_one(masked_req);
  assign grant_unmasked = lowest_one(req_i);

  // Two-level priority: serve the rotation window first; if nobody in the
  // window is asking, wrap to the lowest requester overall. The two terms are
  // mutually exclusive because the second is only selected when the first is
  // empty, so grant_o stays one-hot.
  assign grant_o       = (masked_req != '0) ? grant_masked : grant_unmasked;
  assign grant_valid_o = (req_i != '0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mask_q <= {N{1'b1}};
    end else if (grant_valid_o && update_i) begin
      // Next window starts strictly above the agent just granted.
      // grant_o | (grant_o - 1) sets every bit from 0 up to the granted index;
      // inverting leaves only the bits above it. When the top bit was granted
      // this yields zero, which makes the next arbitration take the unmasked
      // path -- i.e. it wraps. That is the intended behaviour.
      mask_q <= ~(grant_o | (grant_o - {{(N-1){1'b0}}, 1'b1}));
    end
  end

endmodule

`default_nettype wire
