module DataSeparator(MASTER_CLK, CLKEN, FD_RDDATA_IN, SHAPED_DATA, DWIN);

	input				MASTER_CLK;			// Master Clock -- Data rate * PJL_COUNTER_MAX
	input				CLKEN;				// Clock Enable -- allows input clock to be divided down
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
// Rewritten from scratch 2011-12-31 to fix all the timing violations.
//   Winners don't use asynchronous logic in FPGAs.....

	//// Input synchronisation (The Synchrotron)
	// This takes a pulse of arbitrary width from the floppy drive, and
	// converts it to a one clock wide negative pulse (U2B) and a two clock
	// wide negative pulse (SHAPED_DATA)
	reg [2:0] syncroniser_r;
	wire u2b = !(syncroniser_r == 3'bX01);
	assign SHAPED_DATA = !((syncroniser_r == 3'bX01) || (syncroniser_r == 3'b011));
	always @(negedge MASTER_CLK) begin
		if (CLKEN) begin
			syncroniser_r <= {syncroniser_r[1:0], FD_RDDATA_IN};
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
			if (CLKEN) begin
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
	end

endmodule

// vim: ts=3 sw=3
