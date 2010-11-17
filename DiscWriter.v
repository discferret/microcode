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
module DiscWriter(reset, clock, mdat, maddr_inc, wrdata, wrgate, trkmark, index, start, running);
	input							reset;		// state machine reset
	input							clock;		// master state machine clock
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
	parameter	ST_TIMER			=	4'd2;		// Timer load
	parameter	ST_TIMERWAIT	=	4'd3;		// Timer wait
	parameter	ST_STROBE		=	4'd4;		// Send write pulse
	parameter	ST_WRGATE		=	4'd5;		// Set write gate
	parameter	ST_WAITIDX		=	4'd6;		// Wait for index pulse (#1)
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
			case (state)
				ST_IDLE:	begin
								// IDLE: State machine idle

								// Clear MADDR_INC (increment memory address -- set if MADDR incremented)
								maddr_inc <= 1'b0;
								// Terminate write data pulse
								wrdat_r <= 1'b0;
								wrgate <= 1'b1;
								
								// stay in current state unless START=1
								if (start) begin
									state <= ST_LOOP;
								end else begin
									state <= ST_IDLE;
								end
							end

				ST_LOOP: begin
								// LOOP: Main state machine loop
								
								// Clear any active write-data pulses or memory increments
								wrdat_r <= 1'b0;
								maddr_inc <= 1'b0;

								// Latch current instruction
								cur_instr <= mdat;
								
								if (mdat[7] == 1'b1) begin
									// 0b1nnn_nnnn: TIMER LOAD n
									state <= ST_TIMER;
								end else
								if (mdat == 8'b0111_1111) begin
									// 0b0111_1111: STOP
									state <= ST_IDLE;
								end else
								if (mdat[7:6] == 2'b01) begin
									// 0b01nn_nnnn: WAIT n INDEX PULSES
									state <= ST_WAITIDX;
								end else
								if (mdat == 8'b0000_0011) begin
									// 0b0000_0011: WAIT HSTMD
									state <= ST_WAITHSTM;
								end else
								if (mdat == 8'b0000_0010) begin
									// 0b0000_0010: WRITE PULSE
									state <= ST_STROBE;
								end else
								if (mdat[7:1] == 7'b0000_000) begin
									// 0b0000_000n: SET WRITE GATE
									state <= ST_WRGATE;
								end else begin
									// nothing happens if we don't recognise the command...
									state <= ST_LOOP;
								end
							end

				ST_TIMER: begin
						// TIMER state 0: load the timer value
						// Note that the logic below loads and decrements the counter
						// Jump to "wait for timer to clear" state
						state <= ST_TIMERWAIT;
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
					
				ST_STROBE: begin
						// Send a write strobe
						wrdat_r <= 1'b1;
						maddr_inc <= 1'b1;
						state <= ST_LOOP;
					end

				ST_WRGATE: begin
						// SET WRITE GATE						
						// Load write gate, increment PC and jump back to INIT state
						wrgate <= ~cur_instr[0];
						maddr_inc <= 1'b1;
						state <= ST_LOOP;
					end
				
				ST_WAITIDX: begin
						// WAIT FOR N INDEX PULSES state 0
						// Note that the load logic for the counter is located below, outside of the state machine
						state <= ST_INDEXWAIT;
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

	// "RUNNING" output
	assign running = (state != ST_IDLE);

	// write timer logic
	reg	[6:0]	timerreg;
	always @(posedge clock) begin
		if (reset) begin
			// reset timer to zero
			timerreg <= 7'd0;
		end else if (state == ST_TIMER) begin
			// load timer from lowest 7 bits of current instruction
			timerreg <= cur_instr[6:0];
		end else begin
			// decrement timer register, unless it's already zero
			if (timerreg > 7'd0) begin
				timerreg <= timerreg - 7'd1;
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
			// shift in index bit
			indexdetect <= {indexdetect[0], index};
		end
	end
	
	// index counter logic
	reg	[5:0]	indexcounter;
	always @(posedge clock) begin
		if (reset) begin
			// reset index counter to zero
			indexcounter <= 6'd0;
		end else if (state == ST_WAITIDX) begin
			// load counter from lowest 6 bits of current instruction byte
			indexcounter <= cur_instr[5:0];
		end else begin
			// when an index pulse occurs, decrement the counter
			// unless it's already =0, in which case, hold at zero.
			if ((indexdetect == 2'b01) && (indexcounter > 6'd0)) begin
				indexcounter <= indexcounter - 6'd1;
			end
		end
	end
	
	// write pulse logic
	reg	[7:0]	writetimer;
	always @(posedge clock) begin
		if (reset) begin
			writetimer <= 1'b0;
			wrdata <= 1'b1;
		end else if (wrdat_r == 1'b1) begin
			writetimer <= 8'd30;
			wrdata <= 1'b0;
		end else if (writetimer > 1'b0) begin
			writetimer <= writetimer - 1'b1;
			wrdata <= 1'b0;
		end else begin
			writetimer <= 1'b0;
			wrdata <= 1'b1;
		end
	end

endmodule
