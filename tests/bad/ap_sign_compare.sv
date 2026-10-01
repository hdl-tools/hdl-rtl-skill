// ANTI-PATTERN: AP-SIGN-01 signed compared against unsigned
// EXPECT: sign-compare
module ap_sign_compare (input logic signed [7:0] s_i, input logic [7:0] u_i,
                        output logic lt_o);
  assign lt_o = (s_i < u_i);
endmodule
