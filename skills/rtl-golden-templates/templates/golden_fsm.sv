//=============================================================================
// golden_fsm.sv -- three-block Moore FSM with safe illegal-state recovery
//-----------------------------------------------------------------------------
// Purpose        : Reference finite state machine. Three separate blocks:
//                  state register, next-state decode, output decode. This is
//                  the shape that lets a tool PROVE there is no latch and no
//                  unreachable state.
// When to use    : Any control sequencer -- bus protocol, DMA engine, link
//                  bring-up, calibration sequence, arbiter controller.
// Review focus   : FSM Review (every state assigns state_d; is every state
//                  reachable; is every state exitable), Case Statement Review
//                  (default present and meaningful), Reset Review (resets to a
//                  defined idle state), X/Z Review (no state encoding gap can
//                  latch an X).
// Common mistakes: 1. One-block FSM mixing state and outputs, so outputs are
//                     registered a cycle later than intended.
//                  2. Missing default in the next-state case -> inferred latch
//                     AND a state machine that can wedge forever if a bit
//                     flips (SEU, or an X during bring-up).
//                  3. A state that no transition ever enters -- dead logic
//                     that lint flags and synthesis silently removes.
//                  4. Mealy outputs assigned in the state register block, so
//                     they are off by a cycle versus the spec timing diagram.
//                  5. Driving state_q from more than one always_ff block.
// Retrieval       : fsm, state machine, moore, mealy, sequencer, controller,
//   triggers      : state encoding, one-hot state, next state, idle state
//
// DESIGN NOTE -- why plain `case` and not `unique case`:
//   `unique case` adds a simulation/formal assertion that exactly one branch
//   matches, which is genuinely useful. But slang (and most lint rulesets)
//   flag `unique case` together with a `default` as -Wcase-redundant-default,
//   and the two really do pull in opposite directions: `unique` asserts the
//   illegal case cannot happen, while `default` exists precisely to recover
//   when it does (SEU, X during bring-up, a flipped bit on a long wire).
//   For anything that must not wedge in the field, SAFE RECOVERY WINS. Keep
//   the `default`, drop `unique`, and if you want the one-hot/uniqueness
//   check, write it as an explicit concurrent assertion so it lives in the
//   verification domain instead of constraining the synthesised logic.
//=============================================================================
`default_nettype none

module golden_fsm (
    input  wire  clk,
    input  wire  rst_n,
    input  wire  start_i,
    input  wire  data_valid_i,
    input  wire  done_i,
    input  wire  error_i,
    output logic busy_o,
    output logic capture_en_o,
    output logic error_o
);

  // Explicit enum. Named states beat raw parameters: slang and every lint
  // tool can then tell you about an unhandled state by name.
  typedef enum logic [2:0] {
    ST_IDLE    = 3'b000,
    ST_ARM     = 3'b001,
    ST_CAPTURE = 3'b010,
    ST_DRAIN   = 3'b011,
    ST_ERROR   = 3'b100
  } state_e;

  state_e state_q, state_d;

  //--------------------------------------------------------------------------
  // Block 1 of 3: state register. Does nothing but hold state. No outputs.
  //--------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
    end else begin
      state_q <= state_d;
    end
  end

  //--------------------------------------------------------------------------
  // Block 2 of 3: next-state decode. Pure combinational and TOTAL.
  // state_d is assigned unconditionally first, so no path can infer a latch
  // even if a future edit forgets a branch.
  //--------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;

    case (state_q)
      ST_IDLE: begin
        if (start_i) state_d = ST_ARM;
      end

      ST_ARM: begin
        if      (error_i)      state_d = ST_ERROR;
        else if (data_valid_i) state_d = ST_CAPTURE;
      end

      ST_CAPTURE: begin
        if      (error_i) state_d = ST_ERROR;
        else if (done_i)  state_d = ST_DRAIN;
      end

      ST_DRAIN: begin
        state_d = ST_IDLE;
      end

      ST_ERROR: begin
        // Error is sticky until the requester drops start_i. An error state
        // you can leave by accident is worse than one you must acknowledge.
        if (!start_i) state_d = ST_IDLE;
      end

      // Recovery, not decoration. 3 bits encode 8 values and only 5 are
      // legal; a flipped bit or an X during bring-up lands here. Going to
      // ST_ERROR makes the fault observable instead of silently wedging.
      default: begin
        state_d = ST_ERROR;
      end
    endcase
  end

  //--------------------------------------------------------------------------
  // Block 3 of 3: output decode. Moore -- outputs depend on state_q only,
  // never on the inputs, so they are glitch-free and timing-predictable.
  //--------------------------------------------------------------------------
  always_comb begin
    busy_o       = 1'b0;
    capture_en_o = 1'b0;
    error_o      = 1'b0;

    case (state_q)
      ST_IDLE:    ;                        // all defaults hold
      ST_ARM:     busy_o       = 1'b1;
      ST_CAPTURE: begin
        busy_o       = 1'b1;
        capture_en_o = 1'b1;
      end
      ST_DRAIN:   busy_o       = 1'b1;
      ST_ERROR:   error_o      = 1'b1;
      default:    error_o      = 1'b1;
    endcase
  end

endmodule

`default_nettype wire
