module StepController(
	CLK,				// Clock signal for FSM
	STEPCLK,			// Step-rate clock
	RESET,			// Synchronous reset
	CTLBYTE,			// Control byte -- MSB=direction
	WRITE,			// Write input (+ve level triggered)
	IS_STEPPING,	// Output -- 1 if state machine is stepping
	STEP_OUT_n,		// Output to FDD: step signal
	DIR_OUT,			// Output to FDD: direction signal
	TRACK0_IN,		// Input from FDD: Track 0 state (1 = head over track 0)
	TRACK0_HIT		// Output status bit -- track 0 hit during seek
);

	input					CLK;
	input					STEPCLK;
	input					RESET;
	input		[7:0]		CTLBYTE;
	input					WRITE;
	output				IS_STEPPING;
	output				STEP_OUT_n;
	output	reg		DIR_OUT;
	input					TRACK0_IN;
	output	reg		TRACK0_HIT;

/////////////////////////////////////////////////////////////////////////////
// Stepping output
	reg STEP_REG;
	assign STEP_OUT_n = !STEP_REG;


/////////////////////////////////////////////////////////////////////////////
// Finite State Machine setup

	// FSM state encodings
	parameter	S_IDLE	= 3'b000,
					S_STEP1	= 3'b001,
					S_STEP2	= 3'b010,
					S_STEP3 = 3'b011;

	// Current FSM state
	reg [2:0] cur_state;

	// Number of disc steps remaining
	reg [6:0] num_steps;


/////////////////////////////////////////////////////////////////////////////
// Status outputs

	// Stepping status -- if cur_state != S_IDLE, then the controller is stepping
	// the drive head.
	assign IS_STEPPING = (cur_state != S_IDLE);


/////////////////////////////////////////////////////////////////////////////
// Finite State Machine logic

	// Set and Reset for track 0 sense state
	reg TKSENSE_SET, TKSENSE_RST;

	always @(posedge CLK) begin
		// Don't set or clear the track0 sensor (yet)
		TKSENSE_SET <= 1'b0;
		TKSENSE_RST <= 1'b0;
	
		// Positive edge on clock
		if (RESET == 1'b1) begin
			// Reset active, set state to IDLE
			cur_state <= S_IDLE;
			num_steps <= 7'b000_0000;
			DIR_OUT <= 1'b1;
			STEP_REG <= 1'b0;
		end else begin
			case (cur_state)
				S_IDLE:	begin
								// Idle state. Entered on reset.
								STEP_REG <= 1'b0;
								// Wait for WRITE=1, then latch number of steps
								// and direction and enter STEP1 on next clock
								if (WRITE == 1'b1) begin
									cur_state <= S_STEP1;
									num_steps <= CTLBYTE[6:0];
									DIR_OUT <= CTLBYTE[7];
								end else begin
									cur_state <= S_IDLE;
								end
							end

				S_STEP1:	begin
								// STEP1 state. Entered after control word written.
								// Waits for STEPCLK=1, then jumps to STEP2
								if (TRACK0_IN && DIR_OUT) begin
									// Seeking out and tk0 active; this is a track0 hit.
									TKSENSE_SET <= 1'b1;
									cur_state <= S_IDLE;
								end else begin
									TKSENSE_RST <= 1'b1;
									if (STEPCLK == 1'b1) begin
										cur_state <= S_STEP2;
									end else begin
										cur_state <= S_STEP1;
									end
								end
							end
				S_STEP2:	begin
								// STEP2 state. Entered after STEPCLK=1.
								// Waits for STEPCLK=0, lowers STEP line, then
								// jumps to STEP3.
								if (STEPCLK == 1'b0) begin
									STEP_REG <= 1'b1;
									cur_state <= S_STEP3;
								end else begin
									cur_state <= S_STEP2;
								end
							end
				S_STEP3:	begin
								// STEP3 state. Entered after STEPCLK=0.
								// Waits for STEPCLK=1, then raises STEP, decrements NUM
								// and jumps to STEP2 (if NUM>0) or IDLE (if NUM=0)
								if (TRACK0_IN && DIR_OUT) begin
									// Seeking out and tk0 active; this is a track0 hit.
									TKSENSE_SET <= 1'b1;
									cur_state <= S_IDLE;
								end else begin
									if (STEPCLK == 1'b1) begin
										num_steps <= num_steps - 7'd1;
										STEP_REG <= 1'b0;
										// Track 0 guard -- refuse to step if the drive is
										// at track 0 and direction = 1 (out)
										// Keep looping until num_steps rolls over
										if ((num_steps != 7'b000_0000) && (!(TRACK0_IN && DIR_OUT))) begin
											cur_state <= S_STEP1;
										end else begin
											cur_state <= S_IDLE;
										end
									end else begin
										cur_state <= S_STEP3;
									end
								end
							end
			endcase
		end
	end

	always @(posedge CLK) begin
		if (TKSENSE_SET) begin
			TRACK0_HIT <= 1'b1;
		end else if (TKSENSE_RST) begin
			TRACK0_HIT <= 1'b0;
		end
	end
	
endmodule

// vim: ts=3 sw=3
