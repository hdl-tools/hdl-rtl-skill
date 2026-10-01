//=============================================================================
// golden_ready_valid.sv -- one-deep ready/valid stage + the handshake contract
//-----------------------------------------------------------------------------
// Purpose        : The smallest provably-correct ready/valid stage, and the
//                  written contract that every ready/valid interface in the
//                  design must obey. Read the contract before writing any
//                  handshake by hand.
// When to use    : A simple buffered interface where half throughput (one beat
//                  every two cycles) is acceptable. If you need a beat every
//                  cycle, use golden_register_slice.sv instead -- do NOT try
//                  to "optimise" this module into full throughput, that is
//                  exactly how the combinational valid<->ready loop gets born.
// Review focus   : Protocol Review (all five contract rules below), CDC Review
//                  (both sides MUST be the same clock domain -- a handshake
//                  across domains needs a req/ack pair plus synchronisers).
// Common mistakes: 1. s_ready_o made a function of m_ready_i -> combinational
//                     path straight through, and with a second such stage
//                     facing it, a combinational loop.
//                  2. Retracting valid before the beat is accepted, so the
//                     downstream sees a beat that then vanishes.
//                  3. Changing data while valid is high and ready is low.
//                  4. Waiting for ready before asserting valid -> deadlock,
//                     because the partner is waiting for valid before ready.
// Retrieval       : ready valid, ready/valid, handshake, backpressure, stall,
//   triggers      : flow control, valid ready, stream interface, beat
//
//-----------------------------------------------------------------------------
// THE READY/VALID CONTRACT -- five rules, all mandatory
//-----------------------------------------------------------------------------
// R1 TRANSFER     A beat transfers on a rising clock edge when valid && ready.
//                 Neither side may assume a transfer on any other condition.
// R2 NO RETRACT   Once valid is asserted it MUST stay asserted, with the same
//                 payload, until the beat is accepted. Valid is a promise.
// R3 STABLE DATA  Payload MUST NOT change while valid && !ready.
// R4 NO VALID<-READY DEPENDENCY
//                 valid MUST NOT depend combinationally on ready. ready MAY
//                 depend on valid. Violating this is how two correct-looking
//                 modules deadlock or form a combinational loop when joined.
// R5 RESET        Both valid and ready must be deasserted (not X) at reset,
//                 and neither side may transfer during reset.
//-----------------------------------------------------------------------------
//=============================================================================
`default_nettype none

module golden_ready_valid #(
    parameter int unsigned WIDTH = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    // Upstream (this module is the sink)
    input  wire              s_valid_i,
    input  wire  [WIDTH-1:0] s_data_i,
    output logic             s_ready_o,
    // Downstream (this module is the source)
    output logic             m_valid_o,
    output logic [WIDTH-1:0] m_data_o,
    input  wire              m_ready_i
);

  logic             full_q;
  logic [WIDTH-1:0] data_q;

  // R4 holds by construction: s_ready_o is a registered state bit, so it
  // cannot contain a combinational path from m_ready_i.
  assign s_ready_o = !full_q;

  // R2/R3 hold by construction: m_valid_o and m_data_o come straight out of
  // flops that only change on an accepted beat.
  assign m_valid_o = full_q;
  assign m_data_o  = data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      full_q <= 1'b0;            // R5
      data_q <= '0;
    end else begin
      if (full_q) begin
        // Holding a beat. Release it only when the sink takes it.
        if (m_ready_i) begin
          full_q <= 1'b0;
        end
      end else begin
        // Empty. Accept whatever upstream is offering.
        if (s_valid_i) begin
          full_q <= 1'b1;
          data_q <= s_data_i;
        end
      end
    end
  end

endmodule

`default_nettype wire
