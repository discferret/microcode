/**************
 * DiscReader: Data Acquisition Module for floppy disc reader
 *
 * P. Pemberton, 2009.
 *
 * A complete rewrite of the "DAS1" module, based on a state machine instead
 * of random logic. Slightly less register-efficient, but far easier to
 * maintain, and more reliable too.
 *
 * TODO: Timing analysis -- step through this in a simulator under various
 *       conditions, and make sure the timer is accurately measuring the
 *       deltas between flux transition pulses.
 *
 *       Also need to check the logic -- does this code react to the same
 *       flux transition multiple times (if the pulse is longer than 1tcy)?
 *
 *       If so, and a SYNC1tcy element is added to counteract this, what
 *       happens if there's a flux transition mid-way through the TMROVFL
 *       path?
 */

module DiscReader(CLOCK, CLKEN, RUN, FD_RDDATA_IN, FD_INDEX_IN, RESET, DATA, WRITE);
	input					CLOCK;				// counter clock
	input					CLKEN;				// counter clock enable
	input					RUN;					// enable input -- 1 to acquire
	input					FD_RDDATA_IN;		// read data
	input					FD_INDEX_IN;		// index pulse
	input					RESET;				// asynchronous reset
	
	output reg	[7:0]	DATA;					// data output to RAM
	output				WRITE;				// write output to RAM

/////////////////////////////////////////////////////////////////////////////
// Input synchronisation
	wire FD_RDDATA_IN_tcysync, FD_RDDATA_IN_tcysync2;
	Flag_Delay1tcy_OneCycle _fcd_rddata1(CLOCK, FD_RDDATA_IN, FD_RDDATA_IN_tcysync);
	Flag_Delay1tcy_OneCycle _fcd_rddata2(CLOCK, FD_RDDATA_IN_tcysync, FD_RDDATA_IN_tcysync2);


/////////////////////////////////////////////////////////////////////////////
// Transition period timer
	wire			ResetTimer;
	reg		[6:0]	timer;
	always @(posedge CLOCK or posedge ResetTimer) begin
		if (ResetTimer) begin
			// reset -- clear the counter's internal state
			timer <= 7'd1;
		end else begin
			// clock pulses must be qualified by a clock enable
			if (CLKEN) begin
				// clock pulse -- increment the timer
				if (timer == 7'b111_1111) begin
					// timer overflow
					timer <= 7'd1;
				end else begin
					// increment normally
					timer <= timer + 7'd1;
				end
			end
		end
	end


/////////////////////////////////////////////////////////////////////////////
// State machine

	// FSM states
	parameter	ST_IDLE		= 2'd0;
	parameter	ST_WAITDAT	= 2'd1;
	parameter	ST_WRITE	= 2'd2;
	
	// Current state
	reg		[1:0]	state;
	
	always @(posedge CLOCK or posedge RESET) begin
		if (RESET) begin
			// Reset -- clear to initial state
			state <= ST_IDLE;
		end else if (!RUN) begin
			// RUN inactive -- go back to idle state
			state <= ST_IDLE;
		end else begin
			case (state)
				ST_IDLE:	begin
								// ST_IDLE: Idle state
								if (!RUN) begin
									// RUN inactive, keep spinning in the IDLE state
									state <= ST_IDLE;
								end else begin
									// RUN active -- start timing
									state <= ST_WAITDAT;
								end
							end
							
				ST_WAITDAT:	begin
								// ST_WAITDAT: Wait for DATA pulses (flux transitions)
								if (FD_RDDATA_IN_tcysync) begin
									// Flux transition detected. Store timer value.
									DATA <= {FD_INDEX_IN, timer};
									state <= ST_WRITE;
								end else if (timer == 7'b111_1111) begin
									// Timer is going to overflow.
									// The timer will handle this itself, but we need to store
									// a special value in the acq buffer to signify that an
									// overflow has occurred.
									DATA <= {FD_INDEX_IN, 7'd0};
									state <= ST_WRITE;
								end else begin
									// No transition; keep waiting
									state <= ST_WAITDAT;
								end
							end
							
				ST_WRITE:	begin
								// ST_WRITE: Write the timing byte to RAM. Waits for the FT pulse
								// to drop first. Write signal is generated elsewhere.
								state <= ST_WAITDAT;
							end
			endcase
		end
	end
	
	// WRITE is active during the two RAM write states -- Timer Overflow and Write Timing.
	assign WRITE = (state == ST_WRITE);

	// Reset the timer in the IDLE state, when there's a transition, and when RESET is active
	assign ResetTimer = (state == ST_IDLE) || (FD_RDDATA_IN_tcysync2) || (RESET);
endmodule

// vim ts=3 sw=3
