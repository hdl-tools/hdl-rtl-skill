// ANTI-PATTERN: AP-STRUCT-03 signal read but never driven
// EXPECT: unassigned-variable
module ap_unassigned (input logic clk_i, output logic y_o);
  logic never_driven;
  assign y_o = never_driven;
endmodule
