module AddressCounter(
		CLK,										/* Master clock						*/
		ADDR,										/* Address outputs					*/
		INCREMENT,								/* L->H increments address			*/
		EMPTY, FULL,							/* Empty / Full status outputs	*/
		RESET,									/* Reset input							*/
		DATA,										/* Input data (used by LOAD_*)	*/
		LOAD_U, LOAD_H, LOAD_L				/* L->H loads upper/hi/lo byte	*/
);

	output reg	[18:0]	ADDR;			// Current address
	output					EMPTY;		// EMPTY is 1 whenever ADDR == 0.
	output reg				FULL;			// FULL is 1 if the last INCREMENT caused
												// the address counter to roll over.
	input						CLK;			// Master clock
	input						INCREMENT;	// L->H edge on clock with INCREMENT=1 causes
												// address to be incremented
	input						RESET;		// L->H edge causes ADDR and the FULL flag
												// to be cleared.
	input		LOAD_U, LOAD_H, LOAD_L;	// LOAD_[UHL]: L->H edge on CLK with LOAD[UHL]=1
												// loads contents of DATA into the upper, high
												// or low byte of the counter register respectively.
	input			[7:0]		DATA;			// DATA: Data that is loaded in by LOAD_[UHL].

/////////////////////////////////////////////////////////////////////////////
// EMPTY output logic
	assign EMPTY = (ADDR == 0) && (!FULL);

/////////////////////////////////////////////////////////////////////////////
// Counting logic
	always @(posedge CLK or posedge RESET) begin
		if (RESET) begin
			// Reset -- clear ADDR to 0 and clear FULL flag
			ADDR <= 0;
			FULL <= 0;
		end else begin
			if (LOAD_L) begin
				// Load Low Byte
				ADDR[7:0] <= DATA;
				FULL <= 0;
			end else if (LOAD_H) begin
				// Load High Byte
				ADDR[15:8] <= DATA;
				FULL <= 0;
			end else if (LOAD_U) begin
				// Load Upper Byte
				ADDR[18:16] <= DATA[2:0];
				FULL <= 0;
			end else if (INCREMENT) begin
				// Increment
				if (FULL) begin
					ADDR <= ADDR + 1'b1;
					FULL <= 1'b1;
				end else begin
					{FULL, ADDR} <= ADDR + 1'b1;
				end
			end
		end
	end
endmodule

// vim: ts=3 sw=3
