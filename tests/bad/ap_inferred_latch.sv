// ANTI-PATTERN: AP-LATCH-01 incomplete always_comb infers a latch
// EXPECT: inferred-latch
// NOTE: requires FULL elaboration. --lint-only does NOT catch this.
module ap_inferred_latch (input logic sel_i, input logic a_i, output logic y_o);
  always_comb begin
    if (sel_i) y_o = a_i;
  end
endmodule
