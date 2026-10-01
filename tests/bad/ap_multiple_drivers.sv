// ANTI-PATTERN: AP-STRUCT-01 two continuous assignments to one variable
// EXPECT: error
module ap_multiple_drivers (input logic a_i, input logic b_i, output logic y_o);
  assign y_o = a_i;
  assign y_o = b_i;
endmodule
