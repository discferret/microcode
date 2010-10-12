module DataSeparator(MASTER_CLK, FD_RDDATA_IN, SHAPED_DATA, DWIN);

	input				MASTER_CLK;			// Master Clock -- Data rate * 16
	input				FD_RDDATA_IN;		// L->H on flux transition
	output			SHAPED_DATA;		// Reshaped data pulses
	output			DWIN;					// Data Window

/////////////////////////////////////////////////////////////////////////////
// "Phase-jerked loop" data separator
// Designed by James Thompson, Analog Innovations, Phoenix AZ.
//   Original schematic: http://www.analog-innovations.com/SED/FloppyDataExtractor.pdf
// Verilog implementation by Phil Pemberton

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
	
	// PJL shift register
	reg [7:0] pjl_shifter;
	always @(posedge MASTER_CLK or negedge u2b) begin
		if (!u2b) begin
			// Asynchronous CLEAR
			pjl_shifter <= 8'b0000_0000;
		end else begin
			// Clock
			pjl_shifter <= {pjl_shifter[6:0], !pjl_shifter[7]};
		end
	end
	
/*	// Latch the state of the SR output
	reg srout;
	always @(posedge MASTER_CLK) begin
		srout <= pjl_shifter[7];
	end
	
	// PJL output register
	reg DWIN;
	always @(posedge srout) begin
		DWIN <= ~DWIN;
	end
*/
	// Slightly different data-window implementation that uses a clock enable
	// instead of a ripple clock, thus keeping everything synchronous to
	// MASTER_CLK. Also saves a flipflop. Win-win.
	wire pjcke;
	Flag_Delay1tcy_OneCycle _fd1_pjls7(MASTER_CLK, pjl_shifter[7], pjcke);

	reg DWIN;
	always @(posedge MASTER_CLK) begin
		if (pjcke) begin
			DWIN <= ~DWIN;
		end
	end

endmodule

// vim: ts=3 sw=3
