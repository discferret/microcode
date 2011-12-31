module MFMSyncWordDetector(
	CLK_DATASEP,
	CLKEN_DATASEP,
	FD_RDDATA_IN,
	SYNC_WORD_IN,
	MASK_IN,
	SYNC_WORD_DETECTED
);

	input					CLK_DATASEP;				// Master clock
	input					CLKEN_DATASEP;				// Data separator clock enable
	input					FD_RDDATA_IN;				// Floppy disc read-data in
	input		[15:0]	SYNC_WORD_IN;				// Syncword to look for
	input		[15:0]	MASK_IN;						// Syncword mask
	output				SYNC_WORD_DETECTED;		// 1 if sync word detected

	// Max counter value for PJL data separator.
	// 16 for 32-clock (16MHz=500kbps), 20 for 40-clock (20MHz=500kbps)
	parameter PJL_COUNTER_MAX = 8'd20;

/////////////////////////////////////////////////////////////////////////////
// MFM sync word detector

	// Data separator
	wire SHAPED_DATA, DWIN;
	defparam _datasep.PJL_COUNTER_MAX = PJL_COUNTER_MAX;
	DataSeparator _datasep(
		.MASTER_CLK		(CLK_DATASEP),
		.CLKEN			(CLKEN_DATASEP),
		.FD_RDDATA_IN	(FD_RDDATA_IN),
		.SHAPED_DATA	(SHAPED_DATA),
		.DWIN				(DWIN)
		);
		
	// MFM sync shift register
	reg [15:0] sync_shift_r;

	// Detect if a transition occurred inside the data window
	reg flux_detected;
	always @(posedge CLK_DATASEP) begin
		if (SHAPED_DATA) begin
			// Data pulse. Set the transition bit.
			flux_detected <= 1'b1;
		end else if (DWIN) begin
			// DWIN transition. Shift the transition bit into the SR and clear the
			// transition bit afterwards.
			sync_shift_r <= {sync_shift_r[14:0], flux_detected};
			flux_detected <= 1'b0;
		end
	end

	reg SYNC_WORD_DETECTED;
	always @(posedge CLK_DATASEP) begin
		if (CLKEN_DATASEP) begin
			SYNC_WORD_DETECTED <= ((sync_shift_r & MASK_IN) == (SYNC_WORD_IN & MASK_IN));
		end
	end

endmodule

// vim: ts=3 sw=3
