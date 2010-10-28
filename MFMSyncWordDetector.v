module MFMSyncWordDetector(
	CLK_PLL32MHZ,
	DATASEP_MASTER_CLK,
	FD_RDDATA_IN,
	SYNC_WORD_IN,
	SYNC_WORD_DETECTED
);

	input					CLK_PLL32MHZ;				// Master clock
	input					DATASEP_MASTER_CLK;		// Data separator master clock
	input					FD_RDDATA_IN;				// Floppy disc read-data in
	input		[15:0]	SYNC_WORD_IN;				// Syncword to look for
	output				SYNC_WORD_DETECTED;		// 1 if sync word detected


/////////////////////////////////////////////////////////////////////////////
// MFM sync word detector

	// Data separator
	wire SHAPED_DATA, DWIN;
	DataSeparator _datasep(DATASEP_MASTER_CLK, FD_RDDATA_IN, SHAPED_DATA, DWIN);
	
	// Detect transitions on DWIN
	reg [1:0] dwin_transition_detector;
	reg dwin_transition_r;
	always @(posedge CLK_PLL32MHZ) begin
		dwin_transition_detector <= {dwin_transition_detector[0], DWIN};
		dwin_transition_r <= (dwin_transition_detector[0] ^ dwin_transition_detector[1]);
	end
		
	// MFM sync shift register
	reg [15:0] sync_shift_r;

	// Detect if a transition occurred inside the data window
	reg flux_detected;
	always @(negedge SHAPED_DATA or posedge dwin_transition_r) begin
		if (!SHAPED_DATA) begin
			// Data pulse. Set the transition bit.
			flux_detected <= 1'b1;
		end else /*if (dwin_transition)*/ begin
			// DWIN transition. Shift the transition bit into the SR and clear the
			// transition bit afterwards.
			sync_shift_r <= {sync_shift_r[14:0], flux_detected};
			flux_detected <= 1'b0;
		end
	end

	reg SYNC_WORD_DETECTED;
	always @(posedge DATASEP_MASTER_CLK) SYNC_WORD_DETECTED <= (sync_shift_r == SYNC_WORD_IN);

//	assign SYNC_WORD_DETECTED = (sync_shift_r == SYNC_WORD_IN);
	
endmodule

// vim: ts=3 sw=3
