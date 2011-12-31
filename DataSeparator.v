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
//   Winners don't use asynchronous logic in FPGAs...
//
// This is a total rewrite, with a completely different synchroniser-decoder
// arrangement, and is far more suited to FPGA implementation. Everything is
// implemented in a single clock domain, and there's only one asynchronous
// reset (which is generated from MASTER_CLK anyway).
//
// Basically, we have a counter and an input signal source. When the counter
// hits max-count, we reset it to zero. When it hits the half-way point, we
// flip DATA_WINDOW (although in this implementation DWIN is a pulse output,
// not a toggle). If the input signal goes high, we clear the counter.
//
// This leaves us with a fairly primitive digital phase-locked loop.

	//// Input synchronisation (The Synchrotron)
	// This takes a pulse of arbitrary width from the floppy drive, and
	// converts it to a one clock wide negative pulse (U2B) and a two clock
	// wide negative pulse (SHAPED_DATA)
	reg [2:0] syncroniser_r;
	always @(posedge MASTER_CLK) begin
			syncroniser_r <= {syncroniser_r[1:0], FD_RDDATA_IN};
	end

	wire u2b = (!syncroniser_r[1] && syncroniser_r[0]);
	assign SHAPED_DATA = (!syncroniser_r[2] && syncroniser_r[1] && syncroniser_r[0]) || u2b;

	//// PJL counter
	reg [7:0] pjl_counter;
	reg DWIN;
	always @(posedge MASTER_CLK or posedge u2b) begin
		if (u2b) begin
			// Asynchronous clear
			pjl_counter <= 8'd0;
		end else begin
			DWIN <= 1'b0;
			if (CLKEN) begin
				// Increment PJL counter
				pjl_counter <= pjl_counter + 8'd1;

				if (pjl_counter == (PJL_COUNTER_MAX / 8'd2)) begin
					// Hit half-way point. Flag a data window.
					DWIN <= 1'b1;
				end else if (pjl_counter == PJL_COUNTER_MAX) begin
					// Hit max count. Reset counter.
					pjl_counter <= 8'd0;
				end
			end
		end
	end

endmodule

// vim: ts=3 sw=3
