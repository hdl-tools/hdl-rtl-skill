//=============================================================================
// golden_sync_2ff.sv -- two-flop clock domain crossing synchroniser
//-----------------------------------------------------------------------------
// Purpose        : Safely carry ONE bit of control information from an
//                  arbitrary source domain into clk. This is the only
//                  sanctioned primitive for a bare asynchronous bit.
// When to use    : A single-bit level or pulse-extended signal crossing clock
//                  domains. Instantiate one per bit ONLY if the bits are
//                  functionally independent.
// Review focus   : CDC Review. Confirm (a) the destination clock is clk,
//                  (b) nothing combinational sits between the stages,
//                  (c) STAGES >= 2, (d) the source is stable for >= 1
//                  destination clock period (see Common mistakes #3).
// Common mistakes: 1. *** USING THIS FOR A MULTI-BIT BUS. *** The bits settle
//                     on different cycles and you sample a value that never
//                     existed in the source domain. Multi-bit needs gray code
//                     (see golden_fifo_async.sv) or a req/ack handshake.
//                  2. Putting logic between the flops, which reintroduces the
//                     metastability window the second flop exists to close.
//                  3. Synchronising a pulse shorter than one destination clock
//                     period. The pulse is simply lost. Widen it in the source
//                     domain first (toggle + edge detect).
//                  4. Dropping the ASYNC_REG / false-path constraint, so STA
//                     times a path that is intentionally asynchronous.
// Retrieval       : cdc, synchronizer, synchroniser, 2ff, two-flop, metastable,
//   triggers      : metastability, clock domain crossing, async signal, resync
//=============================================================================
`default_nettype none

module golden_sync_2ff #(
    // Number of flops in the chain. 2 is the minimum. 3 for high MTBF or
    // when the source domain is much faster than clk.
    parameter int unsigned STAGES    = 2,
    // Value the chain presents while reset is asserted.
    parameter bit          RESET_VAL = 1'b0
) (
    input  wire  clk,            // DESTINATION domain clock
    input  wire  rst_n,          // reset synchronous to clk
    input  wire  async_d_i,      // from the SOURCE domain -- unconstrained
    output logic sync_q_o        // safe to use in the clk domain
);

  initial begin
    if (STAGES < 2)
      $fatal(1, "golden_sync_2ff: STAGES must be >= 2 (got %0d)", STAGES);
  end

  // Synthesis attribute: keeps the chain from being retimed or merged, and
  // marks it for the CDC checker. Vendor spelling varies -- Xilinx ASYNC_REG,
  // Intel PRESERVE, Synopsys async_reg. Keep whichever your flow reads.
  (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0] sync_chain_q;

  // Nothing but flops. No combinational logic between stages, by construction.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync_chain_q <= {STAGES{RESET_VAL}};
    end else begin
      sync_chain_q <= {sync_chain_q[STAGES-2:0], async_d_i};
    end
  end

  assign sync_q_o = sync_chain_q[STAGES-1];

endmodule

`default_nettype wire
