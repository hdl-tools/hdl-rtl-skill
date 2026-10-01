//=============================================================================
// golden_register_slice.sv -- full-throughput skid buffer (pipeline register)
//-----------------------------------------------------------------------------
// Purpose        : Insert a register stage into a ready/valid stream WITHOUT
//                  losing throughput. Breaks both the forward (valid/data) and
//                  the backward (ready) timing path. One beat per cycle.
// When to use    : Timing closure on a long stream path; crossing a physical
//                  partition or floorplan boundary; isolating a slow consumer
//                  from a fast producer. The default tool for "this path fails
//                  timing but I must not lose bandwidth".
// Review focus   : Protocol Review (all five contract rules in
//                  golden_ready_valid.sv), Arithmetic/Width Review (payload
//                  width consistent end to end), Reset Review (both valid bits
//                  clear). Verify throughput in simulation: a continuous
//                  s_valid_i with a continuous m_ready_i must give a beat
//                  every cycle, not every other cycle.
// Common mistakes: 1. Building a one-deep stage (golden_ready_valid.sv) and
//                     assuming it is full throughput. It is not -- it is 50%.
//                  2. Making s_ready_o depend on m_ready_i to "save a flop",
//                     which reintroduces the exact combinational path the
//                     slice was inserted to cut.
//                  3. Forgetting the skid register, so a beat already accepted
//                     is dropped when the sink stalls in the same cycle. This
//                     is a silent data-loss bug that only appears under
//                     backpressure, which is rarely in the directed tests.
//                  4. Loading the skid register unconditionally instead of
//                     only when the main register is occupied and stalled.
// Retrieval       : register slice, skid buffer, pipeline register, timing
//   triggers      : closure stage, elastic buffer, backpressure buffer,
//                   break timing path, full throughput handshake
//=============================================================================
`default_nettype none

module golden_register_slice #(
    parameter int unsigned WIDTH = 32
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              s_valid_i,
    input  wire  [WIDTH-1:0] s_data_i,
    output logic             s_ready_o,
    output logic             m_valid_o,
    output logic [WIDTH-1:0] m_data_o,
    input  wire              m_ready_i
);

  // main_* is the beat presented downstream. skid_* holds the one extra beat
  // that was already accepted when the sink stalled. Two entries is exactly
  // enough: upstream is told to stop in the same cycle the skid fills.
  logic             main_valid_q;
  logic [WIDTH-1:0] main_data_q;
  logic             skid_valid_q;
  logic [WIDTH-1:0] skid_data_q;

  // Registered, so no combinational path from m_ready_i to s_ready_o. This is
  // the whole point of the module.
  assign s_ready_o = !skid_valid_q;
  assign m_valid_o = main_valid_q;
  assign m_data_o  = main_data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      main_valid_q <= 1'b0;
      main_data_q  <= '0;
      skid_valid_q <= 1'b0;
      skid_data_q  <= '0;
    end else if (!skid_valid_q) begin
      // s_ready_o is high this cycle, so upstream may hand us a beat.
      if (m_ready_i || !main_valid_q) begin
        // Main register is draining or already empty: load it directly.
        // When s_valid_i is low this correctly clears main_valid_q.
        main_valid_q <= s_valid_i;
        if (s_valid_i) begin
          main_data_q <= s_data_i;
        end
      end else if (s_valid_i) begin
        // Main register is occupied AND the sink is stalled, but we already
        // promised s_ready_o this cycle. Park the beat in the skid register
        // and drop s_ready_o for next cycle. Nothing is lost.
        skid_valid_q <= 1'b1;
        skid_data_q  <= s_data_i;
      end
    end else begin
      // Skid is occupied, s_ready_o is low. Wait for the sink, then shift
      // skid -> main, which frees the skid and re-opens the input.
      if (m_ready_i) begin
        main_valid_q <= 1'b1;
        main_data_q  <= skid_data_q;
        skid_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
