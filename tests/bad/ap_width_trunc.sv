// ANTI-PATTERN: AP-WIDTH-01 silent width truncation on assignment
// EXPECT: width-trunc
module ap_width_trunc (input logic [7:0] wide_i, output logic [3:0] narrow_o);
  assign narrow_o = wide_i;
endmodule
