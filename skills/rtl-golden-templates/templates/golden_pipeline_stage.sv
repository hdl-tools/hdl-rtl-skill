//=============================================================================
// golden_pipeline_stage.sv -- datapath pipeline stage with valid propagation
//-----------------------------------------------------------------------------
// Purpose        : One stage of a fixed-latency datapath pipeline. Carries a
//                  payload and its valid bit together so that a bubble can
//                  never be mistaken for data.
// When to use    : Fixed-latency arithmetic or lookup pipelines where the
//                  consumer cannot apply backpressure. If the consumer CAN
//                  stall, you need a ready signal -- use
//                  golden_register_slice.sv instead, which handles the
//                  backpressure correctly.
// Review focus   : Reset Review (valid must clear on reset -- a stale valid
//                  after reset injects a phantom beat), X/Z Review (payload
//                  may be X while valid is low, and consumers MUST gate on
//                  valid), Sequential Logic Review (payload and valid must be
//                  in the SAME always_ff so they cannot skew), Power Review
//                  (payload only toggles when valid, which is free clock
//                  gating for the synthesis tool).
// Common mistakes: 1. Registering the payload and the valid bit in two
//                     different always_ff blocks, so a later edit changes the
//                     enable on one and not the other and the valid bit
//                     drifts a cycle away from its data.
//                  2. Resetting the payload but not the valid bit (or the
//                     reverse). A valid bit that comes out of reset high
//                     injects garbage into the pipeline on cycle one.
//                  3. Using flush_i and en_i together without deciding the
//                     priority. Flush must win, or a stalled stage keeps data
//                     that was supposed to be discarded.
//                  4. Assuming a stalled pipeline preserves ordering when the
//                     enable is driven per-stage rather than globally.
// Retrieval       : pipeline, pipeline stage, pipe stage, datapath pipeline,
//   triggers      : valid propagation, pipeline bubble, pipeline flush,
//                   retiming stage, latency stage
//=============================================================================
`default_nettype none

module golden_pipeline_stage #(
    parameter int unsigned WIDTH = 32,
    // Payload value presented while the stage is invalid. '0 keeps the
    // downstream logic X-free, which makes a real X much easier to trace.
    parameter logic [WIDTH-1:0] IDLE_PATTERN = '0
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              en_i,       // stage advance (stall when low)
    input  wire              flush_i,    // discard in-flight beat; wins over en_i
    input  wire              valid_i,
    input  wire  [WIDTH-1:0] data_i,
    output logic             valid_q_o,
    output logic [WIDTH-1:0] data_q_o
);

  // Payload and valid live in ONE always_ff. They physically cannot skew.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q_o <= 1'b0;
      data_q_o  <= IDLE_PATTERN;
    end else if (flush_i) begin
      // Flush has priority over en_i. Only the valid bit needs clearing --
      // leaving the payload alone saves the toggle power, and it is
      // unobservable because every consumer gates on valid.
      valid_q_o <= 1'b0;
    end else if (en_i) begin
      valid_q_o <= valid_i;
      if (valid_i) begin
        data_q_o <= data_i;
      end
    end
  end

endmodule

`default_nettype wire
