//=============================================================================
// golden_fifo_async.sv -- dual-clock asynchronous FIFO (gray-coded pointers)
//-----------------------------------------------------------------------------
// Purpose        : Move a data stream between two UNRELATED clock domains
//                  safely. This is the reference CDC data path; a 2-flop
//                  synchroniser alone cannot do this job.
// When to use    : Any time a multi-bit payload crosses a clock boundary and
//                  you need throughput. For a single control bit use
//                  golden_sync_2ff.sv. For a rare multi-bit value where
//                  throughput does not matter, a req/ack handshake is simpler.
// Review focus   : CDC Review -- THE critical one. Confirm: pointers are gray
//                  coded; exactly one 2-flop synchroniser per direction; no
//                  combinational logic inside either synchroniser chain; full
//                  is computed only in the write domain and empty only in the
//                  read domain; the memory itself is never reset; both resets
//                  are released safely (see Reset Review below).
//                  Reset Review -- the two domains have SEPARATE resets. Each
//                  must be synchronised to its own clock before use, and the
//                  FIFO must not be read while the write side is still in
//                  reset (and vice versa) or the pointers disagree.
// Common mistakes: 1. *** BINARY pointers through a synchroniser. *** Multiple
//                     bits change on one increment (7->8 is 0111->1000), the
//                     bits land on different cycles, and you sample a pointer
//                     value that never existed. Gray code changes exactly ONE
//                     bit per increment, which is the entire reason it is used.
//                  2. Computing full and empty in the same clock domain. Each
//                     flag belongs to the domain that can make it worse:
//                     full in the write domain, empty in the read domain.
//                  3. Only one synchroniser, or synchronising a pointer and
//                     then doing arithmetic on it before use.
//                  4. Resetting the memory array -- huge area, and pointless
//                     because the pointers prevent reading unwritten data.
//                  5. DEPTH not a power of two: gray coding relies on binary
//                     wrap, so a non-power-of-two depth breaks the flags.
//                  6. Assuming the occupancy is knowable exactly in either
//                     domain. It is NOT -- each side sees a conservative,
//                     delayed view. Never build exact-level logic on it.
// Retrieval       : async fifo, asynchronous fifo, cdc fifo, dual clock fifo,
//   triggers      : clock domain crossing fifo, gray code pointer, two clock
//                   fifo, cross clock buffer, multi-bit cdc
//
//-----------------------------------------------------------------------------
// WHY A MULTI-BIT 2-FLOP SYNCHRONISER IS LEGAL HERE
//   The usual rule is "never put a bus through a 2-flop synchroniser". That
//   rule exists because independent bits settle on different cycles. Gray
//   coding removes the premise: exactly one bit changes per increment, so the
//   worst case is sampling the pointer one increment stale -- which is a valid
//   pointer value and always conservative (full too early, empty too late).
//   This exception applies ONLY to a gray-coded monotonic counter. Do not
//   generalise it to arbitrary data.
//=============================================================================
`default_nettype none

module golden_fifo_async #(
    parameter int unsigned WIDTH = 32,
    // MUST be a power of two and >= 4. See the initial block for why 4.
    parameter int unsigned DEPTH = 16
) (
    // ---- write domain ----
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en_i,
    input  wire  [WIDTH-1:0] wr_data_i,
    output logic             wr_full_o,
    // ---- read domain ----
    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en_i,
    output logic [WIDTH-1:0] rd_data_o,
    output logic             rd_empty_o
);

  localparam int unsigned ADDR_W = $clog2(DEPTH);

  // Guarded so the check runs at elaboration and never becomes synthesised
  // logic.
  // synthesis translate_off
  initial begin
    // DEPTH >= 4 is not arbitrary: the full comparison slices
    // [ADDR_W-2:0] off the synchronised read pointer, which needs ADDR_W >= 2.
    if (DEPTH < 4)
      $fatal(1, "golden_fifo_async: DEPTH must be >= 4 (got %0d)", DEPTH);
    if ((DEPTH & (DEPTH - 1)) != 0)
      $fatal(1, "golden_fifo_async: DEPTH must be a power of two (got %0d)",
             DEPTH);
  end
  // synthesis translate_on

  // Pointers are ADDR_W+1 bits: the extra bit distinguishes full from empty.
  logic [ADDR_W:0] wr_bin_q,  wr_gray_q;
  logic [ADDR_W:0] wr_bin_nxt, wr_gray_nxt;
  logic [ADDR_W:0] rd_bin_q,  rd_gray_q;
  logic [ADDR_W:0] rd_bin_nxt, rd_gray_nxt;

  // Synchronised copies. Named _sync1 / _sync for the two stages so a reviewer
  // can see at a glance that there are exactly two and nothing between them.
  (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] rd_gray_sync1_q, rd_gray_sync_q;
  (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] wr_gray_sync1_q, wr_gray_sync_q;

  logic do_write;
  logic do_read;

  assign do_write = wr_en_i && !wr_full_o;
  assign do_read  = rd_en_i && !rd_empty_o;

  //==========================================================================
  // WRITE DOMAIN
  //==========================================================================
  assign wr_bin_nxt  = wr_bin_q + {{ADDR_W{1'b0}}, do_write};
  // bin -> gray: g = b ^ (b >> 1)
  assign wr_gray_nxt = wr_bin_nxt ^ (wr_bin_nxt >> 1);

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_bin_q  <= '0;
      wr_gray_q <= '0;
    end else begin
      wr_bin_q  <= wr_bin_nxt;
      wr_gray_q <= wr_gray_nxt;
    end
  end

  // Full when the next write pointer would reach the read pointer having
  // wrapped one extra time. In gray space that is: top two bits inverted,
  // remaining bits equal.
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_full_o <= 1'b0;
    end else begin
      wr_full_o <= (wr_gray_nxt ==
                    {~rd_gray_sync_q[ADDR_W:ADDR_W-1],
                      rd_gray_sync_q[ADDR_W-2:0]});
    end
  end

  // read pointer -> write domain. Two flops, nothing in between.
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      rd_gray_sync1_q <= '0;
      rd_gray_sync_q  <= '0;
    end else begin
      rd_gray_sync1_q <= rd_gray_q;
      rd_gray_sync_q  <= rd_gray_sync1_q;
    end
  end

  //==========================================================================
  // READ DOMAIN
  //==========================================================================
  assign rd_bin_nxt  = rd_bin_q + {{ADDR_W{1'b0}}, do_read};
  assign rd_gray_nxt = rd_bin_nxt ^ (rd_bin_nxt >> 1);

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_bin_q  <= '0;
      rd_gray_q <= '0;
    end else begin
      rd_bin_q  <= rd_bin_nxt;
      rd_gray_q <= rd_gray_nxt;
    end
  end

  // Empty when the next read pointer equals the synchronised write pointer.
  // Resets to 1: an empty FIFO is the safe initial claim.
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_empty_o <= 1'b1;
    end else begin
      rd_empty_o <= (rd_gray_nxt == wr_gray_sync_q);
    end
  end

  // write pointer -> read domain. Two flops, nothing in between.
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      wr_gray_sync1_q <= '0;
      wr_gray_sync_q  <= '0;
    end else begin
      wr_gray_sync1_q <= wr_gray_q;
      wr_gray_sync_q  <= wr_gray_sync1_q;
    end
  end

  //==========================================================================
  // DUAL-PORT MEMORY -- deliberately not reset.
  //==========================================================================
  logic [WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge wr_clk) begin
    if (do_write) begin
      mem[wr_bin_q[ADDR_W-1:0]] <= wr_data_i;
    end
  end

  assign rd_data_o = mem[rd_bin_q[ADDR_W-1:0]];

endmodule

`default_nettype wire
