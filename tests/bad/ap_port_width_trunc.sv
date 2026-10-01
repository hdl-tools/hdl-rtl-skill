// ANTI-PATTERN: AP-WIDTH-02 truncation at an instance port connection
// EXPECT: port-width-trunc
module ap_pw_sub (input logic [3:0] a_i, output logic [3:0] y_o);
  assign y_o = a_i;
endmodule
module ap_port_width_trunc (input logic [7:0] wide_i, output logic [3:0] y_o);
  ap_pw_sub u_sub (.a_i(wide_i), .y_o(y_o));
endmodule
