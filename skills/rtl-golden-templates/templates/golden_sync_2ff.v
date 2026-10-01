//=============================================================================
// golden_sync_2ff.v -- Verilog-2001 two-flop CDC synchroniser
//-----------------------------------------------------------------------------
// Purpose        : Verilog-2001 dialect of golden_sync_2ff.sv. Same contract.
// When to use    : Single-bit CDC in a .v-only codebase.
// Review focus   : CDC Review, identical to the .sv version. Additionally
//                  check that the chain is declared reg and never touched by
//                  any other always block.
// Common mistakes: Same four as the .sv version. One more: in Verilog-2001 it
//                  is easy to accidentally declare the chain as the wrong
//                  width when STAGES is overridden, because there is no
//                  elaboration-time assertion to catch STAGES < 2.
// Retrieval       : cdc verilog, synchronizer verilog, 2ff .v, resync verilog
//   triggers      :
//=============================================================================
`default_nettype none

module golden_sync_2ff #(
    parameter STAGES    = 2,
    parameter RESET_VAL = 1'b0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_d_i,
    output wire sync_q_o
);

  (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_chain_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync_chain_q <= {STAGES{RESET_VAL}};
    end else begin
      sync_chain_q <= {sync_chain_q[STAGES-2:0], async_d_i};
    end
  end

  assign sync_q_o = sync_chain_q[STAGES-1];

endmodule

`default_nettype wire
