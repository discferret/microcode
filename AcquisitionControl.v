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

	// Clock multiplexer
/*	// Latch clock-select only when all clocks are low
	wire MFM_clocks_low = (!CLK_PLL16MHZ) & (!CLK_PLL8MHZ) & (!CLK_PLL4MHZ);
	reg [1:0] MFM_CLKSEL_latched;
	always @(posedge MFM_clocks_low) MFM_CLKSEL_latched <= ACQCON_MFM_CLKSEL;
*/
	// Select the relevant clock
	reg DATASEP_CLK_pre;
	always @(DATASEP_CLKSEL or DatasepClkDiv or CLK_DATASEP) begin
		case (DATASEP_CLKSEL)
			2'b00:	DATASEP_CLK_pre = CLK_DATASEP;			// 1Mbps		(F/1 clk)
			2'b01:	DATASEP_CLK_pre = DatasepClkDiv[0];		// 500kbps	(F/2 clk)
			2'b10:	DATASEP_CLK_pre = DatasepClkDiv[1];		// 250kbps	(F/4 clk)
			default:	DATASEP_CLK_pre = DatasepClkDiv[2];		// 125kbps	(F/8 clk)
		endcase
	end
	
	// Sync clock against master clock to remove glitches
	reg DATASEP_MASTER_CLK;
	always @(posedge CLK_DATASEP) DATASEP_MASTER_CLK <= DATASEP_CLK_pre;


/////////////////////////////////////////////////////////////////////////////
// Sync-word detectors

	// Sync-detect status
	wire SYNCWD_START_EVT_DETECTED, SYNCWD_STOP_EVT_DETECTED;

	// Sync-word detector for START condition
	defparam _mfm_syncdet_start.PJL_COUNTER_MAX = PJL_COUNTER_MAX;
	MFMSyncWordDetector _mfm_syncdet_start(
		.CLK_DATASEP			(CLK_DATASEP),
		.CLK_DATASEP_DIVIDED	(DATASEP_MASTER_CLK),
		.FD_RDDATA_IN			(FD_RDDATA_IN),
		.SYNC_WORD_IN			(MFM_SYNCWORD_START),
		.MASK_IN					(MFM_MASK_START),
		.SYNC_WORD_DETECTED	(SYNCWD_START_EVT_DETECTED)
	);

	defparam _mfm_syncdet_stop.PJL_COUNTER_MAX = PJL_COUNTER_MAX;
	MFMSyncWordDetector _mfm_syncdet_stop(
		.CLK_DATASEP			(CLK_DATASEP),
		.CLK_DATASEP_DIVIDED	(DATASEP_MASTER_CLK),
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
	Signal_CrossDomain_As_Flag _scdaf_fd_index(
		.clkA (CLK_MASTER),		.SignalIn  (FD_INDEX_IN),
		.clkB (CLK_MASTER),		.SignalOut (FD_INDEX_IN_sync)
	);
	
	wire ACQ_STARTEVT_MATCH		=	((ACQ_START_MASK[1:0] == 2'b01) && FD_INDEX_IN_sync) ||
									((ACQ_START_MASK[1:0] == 2'b10) && SYNCWD_START_EVT_DETECTED_sync);
	// Delay 1tcy and limit to one clock cycle
	wire ACQ_STARTEVT_MATCH_sync;
	Flag_Delay1tcy_OneCycle _fd1oc_ACQ_STARTEVT_SYNC(CLK_MASTER, ACQ_STARTEVT_MATCH, ACQ_STARTEVT_MATCH_sync);


	//// STOP event triggers
	wire ACQ_STOPEVT_MATCH		=	((ACQ_STOP_MASK[1:0] == 2'b01) && FD_INDEX_IN) ||
									((ACQ_STOP_MASK[1:0] == 2'b10) && SYNCWD_STOP_EVT_DETECTED_sync) ||
									(SR_R_FULL);
	// Delay 1tcy and limit to one clock cycle
	wire ACQ_STOPEVT_MATCH_sync;
	Flag_Delay1tcy_OneCycle _fd1oc_ACQ_STOPEVT_SYNC(CLK_MASTER, ACQ_STOPEVT_MATCH, ACQ_STOPEVT_MATCH_sync);

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
								// If no start mask is set, then acq will start immediately.
								if (ACQ_STARTEVT_MATCH_sync || (ACQ_START_MASK[1:0] == 2'b00)) begin
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
								// ACQUIRE: Acquire until /n/ STOP events
								// Wait for a stop event
								if (ACQ_STOPEVT_MATCH_sync || (ACQ_STOP_MASK == 3'b0)) begin
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
