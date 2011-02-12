module DataSeparator(MASTER_CLK, FD_RDDATA_IN, SHAPED_DATA, DWIN);

	input				MASTER_CLK;			// Master Clock -- Data rate * PJL_COUNTER_MAX
	input				FD_RDDATA_IN;		// L->H on flux transition
	output			SHAPED_DATA;		// Reshaped data pulses
	output			DWIN;					// Data Window

	// Max counter value for PJL data separator.
	// 16 for 32-clock (16MHz=500kbps), 20 for 40-clock (20MHz=500kbps)
	parameter PJL_COUNTER_MAX = 8'd16;

/////////////////////////////////////////////////////////////////////////////
// "Phase-jerked loop" data separator
// Designed by James Thompson, Analog Innovations, Phoenix AZ.
//   Original schematic: http://www.analog-innovations.com/SED/FloppyDataExtractor.pdf
// Verilog implementation by Phil Pemberton
// Core rewritten 2010-01-29 to get more flexibility for clocking

	// Declare flipflops
	reg u2a, u2b;

	// U2A -- first synchroniser.
	wire u2a_nPreset = u2b;
	always @(posedge FD_RDDATA_IN or negedge u2a_nPreset) begin
		if (!u2a_nPreset) begin
			u2a <= 1'b1;
		end else begin
			u2a <= 1'b0;
		end
	end

	// U2B -- second synchroniser
	wire u2b_clk = !MASTER_CLK;
	always @(posedge u2b_clk) begin
		u2b <= u2a;
	end

	// U4A -- provides SHAPED_DATA
	reg SHAPED_DATA;
	always @(posedge u2b_clk or negedge u2b) begin
		if (!u2b) begin		// clear
			SHAPED_DATA <= 1'b0;
		end else begin
			SHAPED_DATA <= u2b;		// clock; D=u2b's output
		end
	end

	//// PJL counter
	reg [7:0] pjl_counter;
	reg DWIN;
	always @(posedge MASTER_CLK or negedge u2b) begin
		if (!u2b) begin
			// Asynchronous clear
			pjl_counter <= 8'd0;
		end else begin
			// Increment PJL counter
			pjl_counter <= pjl_counter + 8'd1;

			if (pjl_counter == (PJL_COUNTER_MAX / 8'd2)) begin
				// Hit half-way point. Flip data window.
				DWIN <= ~DWIN;
			end else if (pjl_counter == PJL_COUNTER_MAX) begin
				// Hit max count. Reset counter.
				pjl_counter <= 8'd0;
			end
		end
	end

endmodule

// vim: ts=3 sw=3
