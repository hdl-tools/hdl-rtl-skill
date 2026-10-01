// ANTI-PATTERN: AP-STRUCT-02 typo creates an implicit net
// EXPECT: error
// Only an error because of `default_nettype none. Without it this is SILENT.
`default_nettype none
module ap_implicit_net (input logic a_i, output logic y_o);
  assign some_nte = a_i;
  assign y_o = some_nte;
endmodule
`default_nettype wire
