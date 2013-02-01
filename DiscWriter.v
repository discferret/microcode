`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    21:26:27 05/05/2007 
// Design Name: 
// Module Name:    DiscWriter 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module DiscWriter(reset, clock, clken, mdat, maddr_inc, wrdata, wrgate, trkmark, index, start, running);
	input							reset;		// state machine reset
	input							clock;		// master state machine clock
	input							clken;		// master state machine clock enable
	input				[7:0]		mdat;			// memory data in
	output	reg				maddr_inc;	// memory address increment
	output	reg				wrdata;		// write data
	output	reg				wrgate;		// write gate
	input							trkmark;		// track mark detect input
	input							index;		// index pulse detect input
	input							start;		// START WRITE input
	output						running;		// write engine running

	// write data input to pulse stretcher
	reg	wrdat_r;

	// current machine state
	reg	[3:0]	state;
	
	// latched copy of current instruction byte
	reg	[7:0]	cur_instr;
	
	// machine states
	parameter	ST_IDLE			=	4'd0;		// Idle state
	parameter	ST_LOOP			=	4'd1;		// Main loop
	parameter	ST_TIMERWAIT	=	4'd3;		// Timer wait
	parameter	ST_INDEXWAIT	=	4'd7;		// Wait for index pulse (#2)
	parameter	ST_WAITHSTM		=	4'd8;		// Wait for track mark

	// state machine logic
	always @(posedge clock or posedge reset) begin
		if (reset) begin
			// Reset pulse -- clear internal state
			state <= ST_IDLE;
			wrgate <= 1'b1;
			wrdat_r <= 1'b0;
			maddr_inc <= 1'b0;
			cur_instr <= 8'b0111_1111;		// STOP
		end else begin
			if (clken) begin
				// Clear any active write-data pulses or memory increments
				wrdat_r <= 1'b0;
				maddr_inc <= 1'b0;
				
				case (state)
					ST_IDLE:	begin
									// IDLE: State machine idle

									// Terminate write data pulse
									wrdat_r <= 1'b0;
									wrgate <= 1'b1;

									// stay in current state unless START=1
									if (start) begin
										// Start requested -- increment memory address and advance to the processing loop
										maddr_inc <= 1'b1;
										state <= ST_LOOP;
									end else begin
										state <= ST_IDLE;
									end
								end

					ST_LOOP: begin
									// LOOP: Main state machine loop
									
									// Latch current instruction
									cur_instr <= mdat;
									
									if (mdat[7] == 1'b1) begin
										// 0b1nnn_nnnn: TIMER LOAD n
										state <= ST_TIMERWAIT;
									end else
									if (mdat[7:6] == 2'b01) begin
										// 0b01nn_nnnn: WAIT n INDEX PULSES
										state <= ST_INDEXWAIT;
									end else
									if (mdat == 8'b0011_1111) begin
										// 0b0011_1111: STOP
										state <= ST_IDLE;
									end else
									if (mdat == 8'b0000_0011) begin
										// 0b0000_0011: WAIT HSTMD
										state <= ST_WAITHSTM;
									end else
									if (mdat == 8'b0000_0010) begin
										// 0b0000_0010: WRITE PULSE
										// Send a write strobe
										wrdat_r <= 1'b1;
										maddr_inc <= 1'b1;
										state <= ST_LOOP;
									end else
									if (mdat[7:1] == 7'b0000_000) begin
										// 0b0000_000n: SET WRITE GATE
										// Load write gate, increment PC and jump back to LOOP
										wrgate <= ~cur_instr[0];
										maddr_inc <= 1'b1;
										state <= ST_LOOP;
									end else begin
										// nothing happens if we don't recognise the command...
										state <= ST_LOOP;
									end
								end

					ST_TIMERWAIT: begin
							// TIMER state 1:
							// Wait for the timer to clear
							if (timerreg == 0) begin
								// Timer has hit zero. Increment the PC...
								maddr_inc <= 1'b1;
								// And go back to the LOOP state
								state <= ST_LOOP;
							end
						end

					ST_INDEXWAIT: begin
							// WAIT FOR N INDEX PULSES state 1
							// Wait for the index counter to clear
							if (indexcounter == 0) begin
								// Counter has cleared.
								// Increment the PC...
								maddr_inc <= 1;
								// And go back to the LOOP state
								state <= ST_LOOP;
							end
							// Else we just keep spinning here until the counter decrements
						end

					ST_WAITHSTM: begin
							// WAIT HARD SECTOR TRACK MARKER
							if (trkmark) begin
								maddr_inc <= 1;
								state <= ST_IDLE;
							end else begin
								state <= ST_WAITHSTM;
							end
						end

					default: begin
							// Fallback state
							state <= ST_IDLE;
						end
				endcase
			end
		end
	end

	// "RUNNING" output
	assign running = (state != ST_IDLE);

	// write timer logic
	reg	[6:0]	timerreg;
	always @(posedge clock) begin
		if (reset) begin
			// reset timer to zero
			timerreg <= 7'd0;
		end else if (clken) begin
			if ((state == ST_LOOP) && (mdat[7] == 1'b1)) begin
				// load timer from lowest 7 bits of current instruction
				timerreg <= mdat[6:0];
			end else begin
				// decrement timer register, unless it's already zero
				if (timerreg > 7'd0) begin
					timerreg <= timerreg - 7'd1;
				end
			end
		end
	end

	// index detector logic
	reg [1:0] indexdetect;
	always @(posedge clock) begin
		if (reset) begin
			// reset: clear index detector
			indexdetect <= 2'b00;
		end else begin
			if (clken) begin
				// shift in index bit
				indexdetect <= {indexdetect[0], index};
			end
		end
	end
	
	// index counter logic
	reg	[5:0]	indexcounter;
	always @(posedge clock) begin
		if (reset) begin
			// reset index counter to zero
			indexcounter <= 6'd0;
		end else if (clken) begin
			if ((state == ST_LOOP) && (mdat[7:6] == 2'b01)) begin
				// load counter from lowest 6 bits of current instruction byte
				indexcounter <= mdat[5:0];
			end else begin
				// when an index pulse occurs, decrement the counter
				// unless it's already =0, in which case, hold at zero.
				if ((indexdetect == 2'b01) && (indexcounter > 6'd0)) begin
					indexcounter <= indexcounter - 6'd1;
				end
			end
		end
	end
	
	// write pulse logic
	reg	[7:0]	writetimer;
	always @(posedge clock) begin
		if (reset) begin
			writetimer <= 1'b0;
			wrdata <= 1'b1;
		end else if (clken) begin
			if (wrdat_r == 1'b1) begin
				writetimer <= 8'd60;				/// FIXME: Magic number.
				wrdata <= 1'b0;
			end else if (writetimer > 1'b0) begin
				writetimer <= writetimer - 1'b1;
				wrdata <= 1'b0;
			end else begin
				writetimer <= 1'b0;
				wrdata <= 1'b1;
			end
		end
	end

endmodule

// vim: ts=3
