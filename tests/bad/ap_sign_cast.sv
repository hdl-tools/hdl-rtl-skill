// ANTI-PATTERN: AP-SIGN-03 size-cast of a bare literal is signed
// EXPECT: arith-op-mismatch
// WIDTH'(1) is signed because the literal 1 is a signed int; the cast changes
// the width, not the signedness. Write WIDTH'(1'b1) instead.
module ap_sign_cast #(
    parameter int unsigned WIDTH = 8
) (
    input  wire              clk,
    input  wire              rst_n,
    output logic [WIDTH-1:0] count_q
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) count_q <= '0;
    else        count_q <= count_q + WIDTH'(1);
  end
endmodule
