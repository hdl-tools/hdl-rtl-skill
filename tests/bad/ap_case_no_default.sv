// ANTI-PATTERN: AP-FSM-02 case without default -> latch + unreachable state
// EXPECT: case-default
// EXPECT: inferred-latch
module ap_case_no_default (input logic [1:0] sel_i, output logic [1:0] y_o);
  always_comb begin
    case (sel_i)
      2'b00: y_o = 2'b01;
      2'b01: y_o = 2'b10;
    endcase
  end
endmodule
