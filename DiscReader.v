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

	// current counter value
	reg [BITS-2:0] counter;
	// has the counter overflowed?
	wire counter_overflow = (counter == ('d1 << BITS-1) - 'd2);
	// set true if we missed an index
	reg missed_index;

	always @(posedge CLOCK) begin
		// clear write flag if it is set
		WRITE <= 1'b0;
		// assume we didn't miss an index on this cycle
		missed_index <= 1'b0;

		// -- frequency counter --
		if (RESET || !RUN) begin
			// reset active -- clear counter
			counter <= 'd0;
			missed_index <= 1'b0;
			WRITE <= 1'b0;
		end else if (CLKEN) begin
			// otherwise increment
			if (counter < ('d1 << BITS-1) - 'd2) begin
				counter <= counter + 'd1;
			end else begin
				counter <= 'd0;
			end
		end

		if (!RESET && RUN) begin
			if ((counter_overflow && CLKEN) && !(FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync)) begin
				// Counter overflow, but RD_DATA and INDEX are inactive. Write an
				// overflow byte.
				DATA <= ('d1 << BITS-1) - 'd1;
				WRITE <= 'd1;
			end else if (FD_RDDATA_IN_tcysync | FD_INDEX_IN_tcysync) begin
				// No overflow, either RDDATA or INDEX is active.
				// Write current counter value
				DATA[BITS-2:0] <= counter;
				WRITE <= 1'b1;

				// Right then. Did INDEX and DATA occur at the same time?
				if (FD_INDEX_IN_tcysync && FD_RDDATA_IN_tcysync) begin
					// Yep, we missed the index. Make a note to flag it on the next cycle.
					missed_index <= 1'b1;
				end
				
				// Set index state bit. We don't use index directly, otherwise we'd have... problems with collisions.
				// So what we do is use the MSB to say "this store was caused by something other than a data bit."
				DATA[BITS-1] <= !FD_RDDATA_IN_tcysync;

				// Reset the counter
				counter <= 'd0;
			end else if (missed_index) begin
				// We missed an index on the last cycle. Write one on this cycle.
				DATA				<= 'd0;			// Set tick count to zero
				DATA[BITS-1]	<= 1'b1;			// This store was caused by an index pulse
			end
		end
	end

endmodule

// vim: ts=3 sw=3
