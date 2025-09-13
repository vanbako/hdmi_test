// Simple HDMI test pattern at 1280x720p60 using Gowin DVI_TX IP
// Assumes 27.000 MHz input clock; generates 371.25 MHz serial and 74.25 MHz pixel clocks
// If your board uses a different osc (e.g., 25/50 MHz), adjust PLL params or replace with a PLL IP.

`timescale 1ns/1ps

module hdmi_top (
    input  wire sys_clk,        // Board oscillator, default 27.000 MHz
    input  wire sys_rst_n,      // Active-low reset

    // Tang Mega 60K pins file expects these names
    output wire tmds_clk_p_0,
    output wire tmds_clk_n_0,
    output wire [2:0] tmds_d_p_0,
    output wire [2:0] tmds_d_n_0
);

    // --------------------------------------------------------------------
    // Clock generation: 27.000 MHz -> 371.25 MHz (serial) and /5 -> 74.25 MHz (pixel)
    // --------------------------------------------------------------------
    wire pll_lock;
    wire clk_serial;  // ~371.25 MHz (PLL clkout)
    wire clk_pix;     // ~74.25 MHz (PLL clkoutd = /5)

    // Use the generated Gowin PLL wrapper (Gowin_PLL):
    // - clkout0: ~371.25 MHz (TMDS 5x serial clock)
    // - clkout1: ~74.25  MHz (pixel clock)
    // The PLL expects a management clock (mdclk) and an active-high reset.
    Gowin_PLL u_pll (
        .clkin   (sys_clk),
        .clkout0 (clk_serial),
        .clkout1 (clk_pix),
        .lock    (pll_lock),
        .mdclk   (sys_clk),
        .reset   (~sys_rst_n)
    );

    // --------------------------------------------------------------------
    // 720p60 timing and test pattern
    // --------------------------------------------------------------------
    wire        de;
    wire        hs;
    wire        vs;
    wire [11:0] x;
    wire [11:0] y;

    // Reset sync into pixel domain (active-low sys_rst_n and PLL lock)
    reg [1:0] rst_sync = 2'b00;
    wire rstn_pix = rst_sync[1];
    always @(posedge clk_pix or negedge sys_rst_n) begin
        if (!sys_rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], pll_lock};
    end

    timing_720p u_tmg (
        .clk (clk_pix),
        .rstn(rstn_pix),
        .de  (de),
        .hs  (hs),
        .vs  (vs),
        .x   (x),
        .y   (y)
    );

    wire [7:0] r, g, b;
    test_pattern_bars u_pat (
        .clk (clk_pix),
        .rstn(rstn_pix),
        .de  (de),
        .x   (x),
        .y   (y),
        .r   (r),
        .g   (g),
        .b   (b)
    );

    // --------------------------------------------------------------------
    // DVI/HDMI (TMDS) transmitter
    // --------------------------------------------------------------------
    dvi_tx u_dvi (
        .I_rst_n     (rstn_pix),
        .I_serial_clk(clk_serial),
        .I_rgb_clk   (clk_pix),
        .I_rgb_vs    (vs),
        .I_rgb_hs    (hs),
        .I_rgb_de    (de),
        .I_rgb_r     (r),
        .I_rgb_g     (g),
        .I_rgb_b     (b),
        .O_tmds_clk_p(tmds_clk_p_0),
        .O_tmds_clk_n(tmds_clk_n_0),
        .O_tmds_data_p(tmds_d_p_0),
        .O_tmds_data_n(tmds_d_n_0)
    );

endmodule

// 1280x720 @ 60 Hz, CEA-861 timings (positive polarity HS/VS)
module timing_720p (
    input  wire        clk,
    input  wire        rstn,
    output reg         de,
    output reg         hs,
    output reg         vs,
    output reg [11:0]  x,
    output reg [11:0]  y
);
    localparam H_ACTIVE = 12'd1280;
    localparam H_FP     = 12'd110;
    localparam H_SYNC   = 12'd40;
    localparam H_BP     = 12'd220;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP; // 1650

    localparam V_ACTIVE = 12'd720;
    localparam V_FP     = 12'd5;
    localparam V_SYNC   = 12'd5;
    localparam V_BP     = 12'd20;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP; // 750

    reg [11:0] hcnt;
    reg [11:0] vcnt;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            hcnt <= 0;
            vcnt <= 0;
            de   <= 1'b0;
            hs   <= 1'b0;
            vs   <= 1'b0;
            x    <= 0;
            y    <= 0;
        end else begin
            // Counters
            if (hcnt == H_TOTAL-1) begin
                hcnt <= 0;
                if (vcnt == V_TOTAL-1) vcnt <= 0; else vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end

            // Data enable and coordinates
            de <= (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
            x  <= (hcnt < H_ACTIVE) ? hcnt : 12'd0;
            y  <= (vcnt < V_ACTIVE) ? vcnt : 12'd0;

            // Syncs (positive polarity per CEA-861 for 720p)
            hs <= (hcnt >= (H_ACTIVE + H_FP)) && (hcnt < (H_ACTIVE + H_FP + H_SYNC));
            vs <= (vcnt >= (V_ACTIVE + V_FP)) && (vcnt < (V_ACTIVE + V_FP + V_SYNC));
        end
    end
endmodule

// Simple 8-bar color test pattern across active area
module test_pattern_bars (
    input  wire       clk,
    input  wire       rstn,
    input  wire       de,
    input  wire [11:0] x,
    input  wire [11:0] y,
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);
    // Vertical bars across 1280: 8 bars of 160 pixels each
    wire [2:0] bar = x[10:8]; // 1280/8 => 160 px per bar; bits [10:8] gives 0..7
    wire [7:0] lo = 8'h20;    // minimum level for visible colors
    wire [7:0] hi = 8'hFF;    // full-scale

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r <= 8'h00; g <= 8'h00; b <= 8'h00;
        end else if (de) begin
            case (bar)
                3'd0: begin r<=hi; g<=hi; b<=hi; end // white
                3'd1: begin r<=hi; g<=hi; b<=lo; end // yellow
                3'd2: begin r<=lo; g<=hi; b<=hi; end // cyan
                3'd3: begin r<=lo; g<=hi; b<=lo; end // green
                3'd4: begin r<=hi; g<=lo; b<=hi; end // magenta
                3'd5: begin r<=hi; g<=lo; b<=lo; end // red
                3'd6: begin r<=lo; g<=lo; b<=hi; end // blue
                default: begin r<=8'h00; g<=8'h00; b<=8'h00; end // black
            endcase
            // Add a white border (10 px) to help detect alignment
            if (x < 12'd10 || x >= 12'd1270 || y < 12'd10 || y >= 12'd710) begin
                r <= hi; g <= hi; b <= hi;
            end
        end else begin
            r <= 8'h00; g <= 8'h00; b <= 8'h00;
        end
    end
endmodule
