module AcquisitionControl(
	CLK_DATASEP,
	CLK_MASTER,
	CKE_500US,
	DATASEP_CLKSEL,
	START, ABORT,
	FD_INDEX_IN,
	FD_RDDATA_IN,
	SR_R_FULL,
	ACQ_START_MASK,
	ACQ_START_NUM,
	ACQ_STOP_MASK,
	ACQ_STOP_NUM,
	HSTMD_THRESH_START,
	HSTMD_THRESH_STOP,
	MFM_SYNCWORD_START,
	MFM_SYNCWORD_STOP,
	MFM_MASK_START,
	MFM_MASK_STOP,
	WAITING, ACQUIRING,
	debug
);

	input					CLK_DATASEP;				// Data-separator clock
	input					CLK_MASTER;					// Master clock
	input					CKE_500US;					// 500us-per-cycle clock enable
	input		[1:0]		DATASEP_CLKSEL;			// Data separator clock select bits
	input					START, ABORT;				// START and ABORT register bits
	input					FD_INDEX_IN;				// INDEX pulse, +ve active
	input					FD_RDDATA_IN;				// DATA READ from FDD, +ve active
	input					SR_R_FULL;					// RAM full (1=true)
	input		[7:0]		ACQ_START_MASK;			// Starting event mask
	input		[7:0]		ACQ_START_NUM;				// Number of start events req'd
	input		[7:0]		ACQ_STOP_MASK;				// Stopping event mask
	input		[7:0]		ACQ_STOP_NUM;				// Number of stop events req'd
	input		[7:0]		HSTMD_THRESH_START;		// Threshold for Start Event HSTMD
	input		[7:0]		HSTMD_THRESH_STOP;		// Threshold for Stop Event HSTMD
	input		[15:0]	MFM_SYNCWORD_START;		// MFM Syncword for starting acq
	input		[15:0]	MFM_SYNCWORD_STOP;		// MFM Syncword for stopping acq
	input		[15:0]	MFM_MASK_START;			// MFM Syncword mask for starting acq
	input		[15:0]	MFM_MASK_STOP;				// MFM Syncword mask for stopping acq

	output				WAITING;						// Status o/p: waiting for trigger
	output				ACQUIRING;					// Status o/p: acquiring
	
	output	[3:0]		debug;

	// Max counter value for PJL data separator.
	// 16 for 32-clock (16MHz=500kbps), 20 for 40-clock (20MHz=500kbps)
	parameter PJL_COUNTER_MAX = 8'd16;

/////////////////////////////////////////////////////////////////////////////
// Track-mark detectors

	wire HSTMD_START_EVT_DETECTED, HSTMD_STOP_EVT_DETECTED;
	TrackMarkDetector _trackmarkdetector_start(
		.clock					(CLK_MASTER),
		.cke						(CKE_500US),
		.reset					(ABORT),
		.index					(FD_INDEX_IN),
		.threshold				(HSTMD_THRESH_START),
		.detect					(HSTMD_START_EVT_DETECTED)
	);
	TrackMarkDetector _trackmarkdetector_stop(
		.clock					(CLK_MASTER),
		.cke						(CKE_500US),
		.reset					(ABORT),
		.index					(FD_INDEX_IN),
		.threshold				(HSTMD_THRESH_STOP),
		.detect					(HSTMD_STOP_EVT_DETECTED)
	);


/////////////////////////////////////////////////////////////////////////////
// Clock dividers and selectors for the data separator

	// Divide down the data separator clock to get F/2, F/4 and F/8
	// i.e. 16MHz, 8MHz, 4MHz for a 32MHz input.
	reg [2:0] DatasepClkDiv;
	always @(posedge CLK_DATASEP) DatasepClkDiv <= DatasepClkDiv + 3'd1;

	//// Clock divider and mux to produce clock enables for the data separators
	// First generate the one-in-two, one-in-four and one-in-eight signals
	reg DatasepClkCounter_Half;
	reg [1:0] DatasepClkCounter_Quarter;
	reg [2:0] DatasepClkCounter_Eighth;
	always @(posedge CLK_DATASEP) begin
		DatasepClkCounter_Half    <= DatasepClkCounter_Half    + 1'd1;
		DatasepClkCounter_Quarter <= DatasepClkCounter_Quarter + 2'd1;
		DatasepClkCounter_Eighth  <= DatasepClkCounter_Eighth  + 3'd1;
	end
	
	// Mux to select the desired CKE signal
	wire DATASEP_CLKEN =
		(DATASEP_CLKSEL == 2'b01) ?	(DatasepClkCounter_Half		== 1'b0) :	// Half clock rate		500kbps	(PC 1.44MB)
		(DATASEP_CLKSEL == 2'b10) ?	(DatasepClkCounter_Quarter	== 2'b0) :	// Quarter clock rate	250kbps	(PC 720K)
		(DATASEP_CLKSEL == 2'b11) ?	(DatasepClkCounter_Eighth	== 3'b0) :	// Eighth clock rate		125kbps	(Unknown)
		1'b1;																						// No clock division		1Mbps		(PC 2.88MB)
	
/////////////////////////////////////////////////////////////////////////////
// Sync-word detectors

	// Sync-detect status
	wire SYNCWD_START_EVT_DETECTED, SYNCWD_STOP_EVT_DETECTED;

	// Sync-word detector for START condition
	defparam _mfm_syncdet_start.PJL_COUNTER_MAX = PJL_COUNTER_MAX;
	MFMSyncWordDetector _mfm_syncdet_start(
		.CLK_DATASEP			(CLK_DATASEP),
		.CLKEN_DATASEP			(DATASEP_CLKEN),
		.FD_RDDATA_IN			(FD_RDDATA_IN),
		.SYNC_WORD_IN			(MFM_SYNCWORD_START),
		.MASK_IN					(MFM_MASK_START),
		.SYNC_WORD_DETECTED	(SYNCWD_START_EVT_DETECTED)
	);

	defparam _mfm_syncdet_stop.PJL_COUNTER_MAX = PJL_COUNTER_MAX;
	MFMSyncWordDetector _mfm_syncdet_stop(
		.CLK_DATASEP			(CLK_DATASEP),
		.CLKEN_DATASEP			(DATASEP_CLKEN),
		.FD_RDDATA_IN			(FD_RDDATA_IN),
		.SYNC_WORD_IN			(MFM_SYNCWORD_STOP),
		.MASK_IN					(MFM_MASK_STOP),
		.SYNC_WORD_DETECTED	(SYNCWD_STOP_EVT_DETECTED)
	);

	// Synchronise sync-detect flags from PLL32 to CLK40
	wire SYNCWD_START_EVT_DETECTED_sync;
	Signal_CrossDomain_As_Flag _scdaf_syncwd_start_detected(
		.clkA (CLK_DATASEP),	.SignalIn  (SYNCWD_START_EVT_DETECTED), 
		.clkB (CLK_MASTER),	.SignalOut (SYNCWD_START_EVT_DETECTED_sync)
	);

	wire SYNCWD_STOP_EVT_DETECTED_sync;
	Signal_CrossDomain_As_Flag _scdaf_syncwd_stop_detected(
		.clkA (CLK_DATASEP),	.SignalIn  (SYNCWD_STOP_EVT_DETECTED), 
		.clkB (CLK_MASTER),	.SignalOut (SYNCWD_STOP_EVT_DETECTED_sync)
	);

assign debug={
			SYNCWD_START_EVT_DETECTED,SYNCWD_START_EVT_DETECTED_sync,
			SYNCWD_STOP_EVT_DETECTED,SYNCWD_STOP_EVT_DETECTED_sync
			};


/////////////////////////////////////////////////////////////////////////////
// Acquisition control state machine
//
// See documentation for more information on the design of this section.

	//// START event triggers

	// Sync index pulse to clk40MHZ
	wire FD_INDEX_IN_sync;
	Flag_Delay1tcy_OneCycle _fd1oc_fd_index(.clk(CLK_MASTER), .in(FD_INDEX_IN), .out(FD_INDEX_IN_sync));

	wire ACQ_STARTEVT_MATCH		=	((ACQ_START_MASK[0]) && FD_INDEX_IN_sync) ||				// Index
									((ACQ_START_MASK[1]) && SYNCWD_START_EVT_DETECTED_sync) ||	// MFM Syncword detect
									(ACQ_START_MASK[2]);														// Always


	//// STOP event triggers
	// Yes, I know STOP ALWAYS is silly, but it's here for consistency with the
	// START EVENT MASK register.
	wire ACQ_STOPEVT_MATCH		=	((ACQ_STOP_MASK[0]) && FD_INDEX_IN_sync) ||				// Index
									((ACQ_STOP_MASK[1]) && SYNCWD_STOP_EVT_DETECTED_sync) ||		// MFM Syncword detect
									(ACQ_STOP_MASK[2]);														// Always

	// event detection state machine
	parameter SSFSM_S_IDLE			= 3'b000;
	parameter SSFSM_S_HSTMD			= 3'b001;
	parameter SSFSM_S_WAIT			= 3'b010;
	parameter SSFSM_S_WAITHSACQ	= 3'b011;
	parameter SSFSM_S_ACQ			= 3'b100;
	
	reg [2:0] SSFSM_CUR_STATE;
	reg [7:0] SCOUNT, ECOUNT;
	
	always @(posedge CLK_MASTER) begin
		// Abort logic -- if ABORT goes high, reset the FSM
		if (ABORT) begin
			SSFSM_CUR_STATE <= SSFSM_S_IDLE;
		end else case (SSFSM_CUR_STATE)
			SSFSM_S_IDLE:	begin
								// IDLE: Wait for ACQCON.START=1
								if (START) begin
									SCOUNT <= ACQ_START_NUM;
									ECOUNT <= ACQ_STOP_NUM;
									if (ACQ_START_MASK[7] == 1'b1) begin
										// HSTMD-then-ACQ enabled, wait for HSTMD
										SSFSM_CUR_STATE <= SSFSM_S_HSTMD;
									end else begin
										// HSTMD-then-ACQ disabled, wait for start event
										SSFSM_CUR_STATE <= SSFSM_S_WAIT;
									end
								end
							end

			SSFSM_S_HSTMD:	begin
								// WAIT_HSTMD: Wait for Hard-Sector Track Mark
								if (HSTMD_START_EVT_DETECTED) begin
									SSFSM_CUR_STATE <= SSFSM_S_WAIT;
								end
							end

			SSFSM_S_WAIT:	begin
								// WAIT: Wait for START event
								if (ACQ_STARTEVT_MATCH) begin
									if (SCOUNT > 0) begin
										// counter nonzero, decrement and keep waiting
										SCOUNT <= SCOUNT - 8'd1;
										SSFSM_CUR_STATE <= SSFSM_S_WAIT;
									end else begin
										// counter reached zero, start acquiring
										if (ACQ_STOP_MASK[7]) begin
											// need to wait for TMD
											SSFSM_CUR_STATE <= SSFSM_S_WAITHSACQ;
										end else begin
											// no need to wait for TMD
											SSFSM_CUR_STATE <= SSFSM_S_ACQ;
										end
									end
								end
							end

			SSFSM_S_WAITHSACQ: begin
								// WAITHSACQ -- Wait for Track Mark before stopping Acquisition
								if (HSTMD_STOP_EVT_DETECTED) begin
									SSFSM_CUR_STATE <= SSFSM_S_ACQ;
								end
							end

			SSFSM_S_ACQ:	begin
								// ACQUIRE: Acquire until /n/ STOP events, or RAM full
								// Wait for a stop event
								if (SR_R_FULL) begin
									// RAM Full causes an immediate abort
									SSFSM_CUR_STATE <= SSFSM_S_IDLE;
								end else begin
									// RAM not full yet, is this a valid stop event?
									if (ACQ_STOPEVT_MATCH) begin
										if (ECOUNT > 0) begin
											// end counter nonzero, keep acquiring
											ECOUNT <= ECOUNT - 8'd1;
											SSFSM_CUR_STATE <= SSFSM_S_ACQ;
										end else begin
											// counter=0, we're done. end the acq cycle and go home.
											SSFSM_CUR_STATE <= SSFSM_S_IDLE;
										end
									end
								end
							end

			default:		begin
								// some other state, kick the FSM into IDLE
								SSFSM_CUR_STATE <= SSFSM_S_IDLE;
							end
		endcase
	end

	// Output logic
	assign WAITING		= ((SSFSM_CUR_STATE == SSFSM_S_HSTMD) || (SSFSM_CUR_STATE == SSFSM_S_WAIT));
	assign ACQUIRING	= ((SSFSM_CUR_STATE == SSFSM_S_WAITHSACQ) || (SSFSM_CUR_STATE == SSFSM_S_ACQ));

endmodule

// vim: ts=3 sw=3
