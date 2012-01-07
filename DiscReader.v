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
	parameter					BITS		= 8;		// data bits

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

reg[BITS:0] trap;

	// current counter value
	reg [BITS-2:0] counter;
	// has the counter overflowed?
	wire counter_overflow = (counter == ('d1 << BITS-1) - 'd2);
	// state of INDEX in the previous clock cycle
	reg last_index_state;

	always @(posedge CLOCK) begin
		// clear write flag if it is set
		WRITE <= 1'b0;
		// save index state from this cycle
		last_index_state <= FD_INDEX_IN_tcysync;

		// -- frequency counter --
		if (RESET || !RUN) begin
			// reset active -- clear counter
			counter <= 'd0;
		end else if (CLKEN) begin
			// otherwise increment
			if (counter < ('d1 << BITS-1) - 'd2) begin
				counter <= counter + 'd1;
			end else begin
				counter <= 'd0;
			end
		end

		if (!RESET && RUN) begin
			if (counter_overflow && !(FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync)) begin
				// Counter overflow, but RD_DATA and INDEX are inactive. Write an
				// overflow byte.
				DATA <= ('d1 << BITS-1) - 'd1;
				WRITE <= 'd1;
			end else if (FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync) begin
				// No overflow, either RDDATA or INDEX is active.
				// Write current counter value
				DATA[BITS-2:0] <= counter;
				WRITE <= 1'b1;

				// Set index state bit
				DATA[BITS-1] <= (last_index_state | FD_INDEX_IN_tcysync);

				// Reset the counter
				counter <= 'd0;
			end
		end
	end

endmodule

// vim: ts=3 sw=3
