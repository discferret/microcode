/****************************************************************************
 * DiscReader.v: Magnetic disc reader module.
 * Philip Pemberton, 2012.
 *
 * This is a complete rewrite of the original DiscFerret MDR module, and fixes
 * a (rather large) number of race conditions and ambiguities which caused
 * data corruption issues when 
 *
 * This version both has a Verilog testbench, and has been tested against it.
 * Acquisition is proven to work (using Icarus Verilog and GTKWave).
 *
 */

module DiscReader(CLOCK, CLKEN, RUN, FD_RDDATA_IN, FD_INDEX_IN, RESET, DATA, WRITE);
	parameter					BITS		= 16;		// number of data bits
															// counter will have two less bits
															// (there are two flag bits)

	input							CLOCK;				// counter clock
	input							CLKEN;				// counter clock enable
	input							RUN;					// enable input -- 1 to acquire
	input							FD_RDDATA_IN;		// read data
	input							FD_INDEX_IN;		// index pulse
	input							RESET;				// asynchronous reset

	output reg	[BITS-1:0]	DATA;					// data output to RAM
	output reg					WRITE;				// write output to RAM


/////////////////////////////////////////////////////////////////////////////
// Input synchronisation
	wire FD_RDDATA_IN_tcysync, FD_INDEX_IN_tcysync;
	Flag_Delay1tcy_OneCycle _fcd_rddata	(CLOCK,	FD_RDDATA_IN,	FD_RDDATA_IN_tcysync);
	Flag_Delay1tcy_OneCycle _fcd_index	(CLOCK,	FD_INDEX_IN,	FD_INDEX_IN_tcysync);

/////////////////////////////////////////////////////////////////////////////
// Frequency counter

	// current counter value
	reg [BITS-3:0] counter;
	// has the counter overflowed?
	wire counter_overflow = (counter == ('d1 << BITS-2) - 'd2);
	// state of INDEX in the previous clock cycle

	always @(posedge CLOCK) begin
		// clear write flag if it is set
		WRITE <= 1'b0;

		// -- frequency counter --
		if (RESET || !RUN) begin
			// reset active -- clear counter
			counter <= 'd0;
		end else if (CLKEN) begin
			// otherwise increment
			if (counter < ('d1 << BITS-2) - 'd2) begin
				counter <= counter + 'd1;
			end else begin
				counter <= 'd0;
			end
		end

		if (!RESET && RUN) begin
			if ((counter_overflow && CLKEN) && !(FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync)) begin
				// Counter overflow, but RD_DATA and INDEX are inactive. Write an
				// overflow byte.
				DATA[BITS-3:0] <= ('d1 << BITS-2) - 'd1;
				DATA[BITS-1:BITS-2] <= 2'b0;	// overflow
				WRITE <= 'd1;
			end else if (FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync) begin
				// No overflow, either RDDATA or INDEX is active.
				// Write current counter value
				DATA[BITS-3:0] <= counter;
				WRITE <= 1'b1;

				// Set index and data state bits
				DATA[BITS-1] <= FD_INDEX_IN_tcysync;
				DATA[BITS-2] <= FD_RDDATA_IN_tcysync;

				// Reset the counter
				counter <= 'd0;
			end
		end
	end

endmodule

// vim: ts=3 sw=3
