module top(
	FD_DENS_OUT,									/* Density O/P							*/
	FD_DENS_IN,										/* Density I/P							*/
	FD_INUSE,										/* In Use O/P							*/
	FD_DRVSEL,										/* Drive Select O/Ps					*/
	FD_MOTEN,										/* Motor Enable O/P					*/
	FD_DIR, FD_STEP,								/* Head direction and step O/Ps	*/
	FD_WRDATA, FD_WRGATE,						/* Write Data and Gate O/P			*/
	FD_SIDESEL,										/* Side select O/P					*/
	FD_INDEX_IN,									/* Index pulse I/P					*/
	FD_TRACK0_IN,									/* Track 0 status I/P				*/
	FD_WRPROT_IN,									/* Write Protect status I/P		*/
	FD_RDDATA_IN,									/* Read Data I/P						*/
	FD_RDY_DCHG_IN,								/* Ready/Disc Changed I/P			*/
	
	HSIO_PORT,										/* High Speed I/Os					*/

	SRAM_A,											/* SRAM address bus					*/
	SRAM_DQ,											/* SRAM data bus						*/
	SRAM_WE_n, SRAM_OE_n,						/* SRAM write & output enables	*/
	SRAM_CE_n,										/* SRAM chip enable					*/

	MCU_PMD,											/* MCU data bus						*/
	MCU_PMALH, MCU_PMALL, 						/* MCU address load signals		*/
	MCU_PMRD, MCU_PMWR,							/* MCU read and write				*/
	STATUS_LED,										/* Status LED							*/
	CLOCK												/* 20MHz main clock					*/
	);

	///// Declare inputs and outputs
	/// Disc drive
	output				FD_DENS_OUT;
	input					FD_DENS_IN;
	output				FD_INUSE;
	output	[3:0]		FD_DRVSEL;
	output				FD_MOTEN;
	output				FD_DIR, FD_STEP;
	output				FD_WRDATA, FD_WRGATE;
	output				FD_SIDESEL;
	input					FD_INDEX_IN;
	input					FD_TRACK0_IN;
	input					FD_WRPROT_IN;
	input					FD_RDDATA_IN;
	input					FD_RDY_DCHG_IN;

	/// High Speed I/O
	inout		[3:0]		HSIO_PORT;
	
	/// Switches and LEDs
	output				STATUS_LED;

	/// SRAM
	output	[18:0]	SRAM_A;
	inout		[7:0]		SRAM_DQ;
	output				SRAM_WE_n, SRAM_OE_n;
	output				SRAM_CE_n;

	/// Microcontroller interface
	inout		[7:0]		MCU_PMD;
	input					MCU_PMALH, MCU_PMALL, MCU_PMRD, MCU_PMWR;

	/// Clocks
	input					CLOCK;


/////////////////////////////////////////////////////////////////////////////
// Unused I/O pins
//	assign	FD_WRDATA	= 1'b1;
//	assign	FD_WRGATE	= 1'b1;
	assign	HSIO_PORT	= 4'hZ;

	// SRAM -- chip select, etc.
	assign	SRAM_CE_n	= 1'b0;

	
/////////////////////////////////////////////////////////////////////////////
// Clock generation
	// Instantiate a PLL to convert from 20MHz to 32MHz and 40MHz
	wire CLK_PLL32MHZ, CLK_MASTER;
	ClockGenerator clkgen(
		.inclk0	(CLOCK),							// 20MHz input clock from the XTAL OSC
		.c0		(CLK_PLL32MHZ),				// 32MHz DPLL clock (sync detector)
		.c1		(CLK_MASTER)					// Master clock (40MHz as standard)
		);


/////////////////////////////////////////////////////////////////////////////
// System version numbers
	localparam	MCO_TYPE		= 16'hDD55;		// Microcode type
	localparam	MCO_VERSION	= 16'h001A;		// Microcode version


/////////////////////////////////////////////////////////////////////////////
// Status LED
/*
	reg [31:0] status_led_counter;
	reg status_led_r;
	assign STATUS_LED = status_led_r;

	always @(posedge CLK_MASTER) begin
		if (status_led_counter > 32'd20_000_000) begin
			status_led_counter <= 32'd0;
			status_led_r <= ~status_led_r;
		end else begin
			status_led_counter <= status_led_counter + 1;
		end
	end
*/
	// Status LED should be on if we're acquiring, or waiting for a trigger event
	assign STATUS_LED = !(ACQSTAT_WAITING | ACQSTAT_ACQUIRING | ACQSTAT_WRITING);

	
/////////////////////////////////////////////////////////////////////////////
// SRAM interface

// Read/write signalling
	// Write signal from Data Acquisition (DiscReader) module
	wire		DAM_SRAM_WR;

// Data out from the Acquisition (DiscReader) module
	wire[7:0]	DAM_SRAM_WRITE_BUS;
	
// Data bus from the MCU Interface
	reg[7:0]		SRAM_DATA_OUT;
	
// Bus arbitration: DAM has the write bus when ACQSTAT_WAITING or ACQSTAT_ACQUIRING
	wire[7:0]	SRAM_DQ_WR;
	assign		SRAM_DQ_WR	= ((ACQSTAT_WAITING) || (ACQSTAT_ACQUIRING)) ? DAM_SRAM_WRITE_BUS : SRAM_DATA_OUT;

// SDRAM data bus is driven by us if OE is inactive, else it's Hi-Z
	assign		SRAM_DQ		= SRAM_OE_n ? SRAM_DQ_WR : 8'hzz;


/////////////////////////////////////////////////////////////////////////////
// Memory write controller

	// SRAM write/output enable
	reg SRAM_WE_n_r, SRAM_OE_n_r;
	assign SRAM_WE_n = SRAM_WE_n_r;
	assign SRAM_OE_n = SRAM_OE_n_r;
	
	// SRAM address increment
	reg SRA_INCREMENT_MWC;

	// Current MWC state
	reg [2:0] MWC_CUR_STATE;
	
	// Valid MWC states
	parameter MWC_S_IDLE			= 3'h0;		// Idle (waiting for write)
	parameter MWC_S_OEIA			= 3'h1;		// OE Inactive (disable SRAM outputs)
	parameter MWC_S_WRITE		= 3'h2;		// Writing to RAM
	parameter MWC_S_INCADDR		= 3'h3;		// End write and increment address
	parameter MWC_S_WRITEEND	= 3'h4;

	// Synchronise input bits from other clock domains
	wire MWC_WRITE_SRAM_DATA;
	Flag_CrossDomain _fcd_write_sram_data(
					MCU_PMWR, MCU_PMWR && (MCU_ADDR[7:0] == 8'h03),
					CLK_MASTER, MWC_WRITE_SRAM_DATA);

	// MWC State machine
	always @(posedge CLK_MASTER) begin
		case (MWC_CUR_STATE)
			MWC_S_IDLE:		begin
								// S_IDLE: Idle state. Write bit inactive, OE active.
								SRAM_WE_n_r			<= 1'b1;
								SRAM_OE_n_r			<= 1'b0;
								SRA_INCREMENT_MWC	<= 1'b0;

								if ((MWC_WRITE_SRAM_DATA) || (DAM_SRAM_WR)) begin
									MWC_CUR_STATE	<= MWC_S_OEIA;
								end else begin
									MWC_CUR_STATE	<= MWC_S_IDLE;
								end
							end

			MWC_S_OEIA:		begin
								// S_OEIA: Make OE inactive
								SRAM_OE_n_r			<= 1'b1;
								MWC_CUR_STATE		<= MWC_S_WRITE;
							end

			MWC_S_WRITE:	begin
								// S_WRITE: write to RAM
								SRAM_WE_n_r			<= 1'b0;
								SRA_INCREMENT_MWC	<= 1'b0;
								MWC_CUR_STATE		<= MWC_S_WRITEEND;
							end
							
			MWC_S_WRITEEND:begin
								SRAM_WE_n_r			<= 1'b1;
								MWC_CUR_STATE		<= MWC_S_INCADDR;
							end

			MWC_S_INCADDR:	begin
								// S_INCADDR: End write and increment Address
								SRAM_WE_n_r			<= 1'b1;
								SRA_INCREMENT_MWC	<= 1'b1;
								MWC_CUR_STATE		<= MWC_S_IDLE;
							end
		
			default:	MWC_CUR_STATE <= MWC_S_IDLE;
		endcase
	end


/////////////////////////////////////////////////////////////////////////////
// Memory address counter

	// Synchronise the three WRITE_ADDR signals against the 40MHz clock
	wire WRITE_SRAM_ADDR_U, WRITE_SRAM_ADDR_H, WRITE_SRAM_ADDR_L;
	Flag_Delay1tcy_OneCycle _fcd_write_sram_addr_l(
					CLK_MASTER, (MCU_ADDR[7:0] == 8'h00),
					WRITE_SRAM_ADDR_L);
	Flag_Delay1tcy_OneCycle _fcd_write_sram_addr_h(
					CLK_MASTER, (MCU_ADDR[7:0] == 8'h01),
					WRITE_SRAM_ADDR_H);
	Flag_Delay1tcy_OneCycle _fcd_write_sram_addr_u(
					CLK_MASTER, (MCU_ADDR[7:0] == 8'h02),
					WRITE_SRAM_ADDR_U);

	// Sync the READ_DATA signal as well
	wire READ_SRAM_DATA_REG_SYNC;
	Flag_CrossDomain _fcd_read_sram_data_reg(
					MCU_PMRD, (MCU_ADDR[7:0] == 8'h03),
					CLK_MASTER, READ_SRAM_DATA_REG_SYNC);

	// SRAM address should increment after an SRAM read or write operation.
	wire SRA_INCREMENT_DWC;
	wire SRA_INCREMENT = (SRA_INCREMENT_DWC) || (SRA_INCREMENT_MWC) || (READ_SRAM_DATA_REG_SYNC);

	AddressCounter addr_count(
		CLK_MASTER,				// Master clock
		SRAM_A,					// SRAM address output
		SRA_INCREMENT,			// Increment input
		SR_R_EMPTY,				// Empty flag (status register read)
		SR_R_FULL,				// Full flag (status register read)
		1'b0, //SR_W_RESET,	// Reset (status register write)
		SYNC_WRITE_REG,		// Get data from sync-write
		MCU_PMWR && (MCU_ADDR[7:0] == 8'h02),	// Write upper address bits
		MCU_PMWR && (MCU_ADDR[7:0] == 8'h01),	// Write high  address bits
		MCU_PMWR && (MCU_ADDR[7:0] == 8'h00)	// Write low   address bits
	);


/////////////////////////////////////////////////////////////////////////////
// Registers
	reg	[7:0]		STEP_RATE;				// step rate in units of 500us
	reg	[7:0]		DRIVE_CONTROL;			// Disc drive control register

	reg	[1:0]		MFM_CLKSEL;				// MFM decoder clock select (for syncword detectors)

	reg	[7:0]		ACQ_START_MASK;		// Acquisition start mode
	reg	[7:0]		ACQ_STOP_MASK;			// Acquisition stop mode
	reg	[7:0]		ACQ_START_NUM;			// Number of start events before acq starts
	reg	[7:0]		ACQ_STOP_NUM;			// Number of stop events before acq ends
	
	reg	[7:0]		HSTMD_THRESH_START;	// HSTMD threshold, start event
	reg	[7:0]		HSTMD_THRESH_STOP;	// HSTMD threshold, stop  event
	reg	[7:0]		HSTMD_THRESH_WRITE;	// HSTMD threshold, write controller
	
	reg	[15:0]	MFM_SYNCWORD_START;	// MFM sync word, start event
	reg	[15:0]	MFM_SYNCWORD_STOP;	// MFM sync word, stop  event
	reg	[15:0]	MFM_MASK_START;		// MFM mask word, start event
	reg	[15:0]	MFM_MASK_STOP;			// MFM mask word, stop  event

	reg	[7:0]		SCRATCHPAD;				// 8-bit scratchpad register (used by ATE for bus interface testing)

// Nets for status register bits
	wire SR_R_EMPTY, SR_R_FULL;			// Empty/full flags from address counter
	wire SR_FDS_STEPPING;					// =1 if stepping controller is stepping
													// SR = Status Register
													// FDS = Floppy Drive, Stepping / Floppy Drive Subsystem
													// STEPPING = (take a wild guess...)
	
	wire ACQSTAT_WAITING;					// Acquisition engine waiting for event
	wire ACQSTAT_ACQUIRING;					// Acquisition engine acquiring data
	wire ACQSTAT_WRITING;					// Write engine is writing data


/////////////////////////////////////////////////////////////////////////////
// Microcontroller interface

// Hi-Z logic for SPP
// When PMRD=1, DIO should be O/P  (FPGA is writing).
// When PMRD=0, DIO should be Hi-Z (PIC  is writing).
	reg[7:0]	MCU_PMD_OUT;
	assign MCU_PMD = MCU_PMRD ? MCU_PMD_OUT : 8'hZZ;

// Latch the address on an Address Write
	reg [7:0] MCU_ADDRH, MCU_ADDRL;
	wire [15:0] MCU_ADDR = {MCU_ADDRH, MCU_ADDRL};
	always @(negedge MCU_PMALH)
		MCU_ADDRH <= MCU_PMD;
	always @(negedge MCU_PMALL)
		MCU_ADDRL <= MCU_PMD;

// Temporary synch register for incoming data from the MCU
	reg [7:0] SYNC_WRITE_REG;
	
// Handle host interface reads and writes
	always @(posedge MCU_PMWR) begin
		/// Register Write
		case (MCU_ADDR[7:0])
			8'h00,
			8'h01,
			8'h02: begin			// SRAM_ADDR_{LOW,HIGH,UPPER}
						// Note: other logic for this state below.
						SYNC_WRITE_REG <= MCU_PMD;
					 end

			8'h03: begin			// SRAM_DATA_LOW
						SRAM_DATA_OUT[7:0] <= MCU_PMD;
					 end

			8'h04: begin			// DRIVE_CONTROL_LOW
						DRIVE_CONTROL[7:0] <= MCU_PMD;
					 end

			8'h05: begin
						// ACQCON
						//    bit 0 = START  }
						//    bit 1 = ABORT   }--- handled elsewhere
						//		bit 2 = WRITE  }
					 end

			8'h06: begin			// ACQ_START_EVT
						// Load the acq start counter and mask
						ACQ_START_MASK <= MCU_PMD;
					 end

			8'h07: begin			// ACQ_STOP_EVT
						// Load the acq stop counter and mask
						ACQ_STOP_MASK <= MCU_PMD;
					 end

			8'h08: begin			// ACQ_START_NUM
						ACQ_START_NUM <= MCU_PMD;
					 end

			8'h09: begin			// ACQ_STOP_NUM
						ACQ_STOP_NUM <= MCU_PMD;
					 end

			8'h10: begin			// HSTMD_THR_START
						// Load HSTMD start threshold
						HSTMD_THRESH_START <= MCU_PMD;
					 end

 			8'h11: begin			// HSTMD_THR_STOP
						// Load HSTMD stop threshold
						HSTMD_THRESH_STOP <= MCU_PMD;
					 end

			8'h12: begin			// HSTMD_THR_WRITE
						// Load HSTMD threshold for the write controller
						HSTMD_THRESH_WRITE <= MCU_PMD;
					 end

			8'h20: begin			// MFM_SYNCWORD_START_L
						MFM_SYNCWORD_START[7:0] <= MCU_PMD;
					 end

 			8'h21: begin			// MFM_SYNCWORD_START_H
						MFM_SYNCWORD_START[15:8] <= MCU_PMD;
					 end

			8'h22: begin			// MFM_SYNCWORD_STOP_L
						MFM_SYNCWORD_STOP[7:0] <= MCU_PMD;
					 end

			8'h23: begin			// MFM_SYNCWORD_STOP_H
						MFM_SYNCWORD_STOP[15:8] <= MCU_PMD;
					 end

			8'h24: begin			// MFM_MASK_START_L
						MFM_MASK_START[7:0] <= MCU_PMD;
					 end

 			8'h25: begin			// MFM_MASK_START_H
						MFM_MASK_START[15:8] <= MCU_PMD;
					 end

			8'h26: begin			// MFM_MASK_STOP_L
						MFM_MASK_STOP[7:0] <= MCU_PMD;
					 end

			8'h27: begin			// MFM_MASK_STOP_H
						MFM_MASK_STOP[15:8] <= MCU_PMD;
					 end

 			8'h2F: begin			// MFM_CLKSEL -- MFM Clock Select
						// Bits 1,0: MFM clock select bits
						MFM_CLKSEL <= MCU_PMD[1:0];
					 end

			8'h30: begin			// Scratchpad register for ATE testing
						SCRATCHPAD <= MCU_PMD[7:0];
					 end

			8'hF0: begin			// STEP_RATE -- Disc drive step rate
						STEP_RATE <= MCU_PMD;
					 end

			8'hFF: begin			// STEP_CMD  -- Disc drive step command
						// Note: other logic for this state below.
						SYNC_WRITE_REG <= MCU_PMD;
					 end

			default: begin
					 end
		endcase
	end

	// Multiplexer for readback (MCU_PMD_OUT)
	always @(*) begin
		case (MCU_ADDR[7:0])
			8'h00:	MCU_PMD_OUT = SRAM_A[7:0];						// SRAM_ADDR_LOW
			8'h01:	MCU_PMD_OUT = SRAM_A[15:8];					// SRAM_ADDR_HIGH
			8'h02:	MCU_PMD_OUT = {5'b00000, SRAM_A[18:16]};	// SRAM_ADDR_UPPER
			8'h03:	MCU_PMD_OUT = SRAM_DQ[7:0];					// SRAM_DATA_LOW
			8'h04:	MCU_PMD_OUT = MCO_TYPE[7:0];					// Microcode type low
			8'h05:	MCU_PMD_OUT = MCO_TYPE[15:8];					// Microcode type high
			8'h06:	MCU_PMD_OUT = MCO_VERSION[7:0];				// Microcode version low
			8'h07:	MCU_PMD_OUT = MCO_VERSION[15:8];				// Microcode version high
			8'h0E:	MCU_PMD_OUT =										// STATUS1 register
							{5'b0, ACQSTAT_WRITING, ACQSTAT_WAITING, ACQSTAT_ACQUIRING};
			8'h0F:	MCU_PMD_OUT =										// STATUS2 register
							{FD_INDEX_IN, FD_TRACK0_IN, FD_WRPROT_IN, FD_RDY_DCHG_IN,
							 FD_DENS_IN, SR_FDS_STEPPING, SR_R_EMPTY, SR_R_FULL};
			8'h30:	MCU_PMD_OUT = SCRATCHPAD;						// Scratchpad register
			8'h31:	MCU_PMD_OUT = ~SCRATCHPAD;						// Inverse Scratchpad register
			default: MCU_PMD_OUT = 8'hXX;
		endcase		
	end
	

/////////////////////////////////////////////////////////////////////////////
// Disc drive interface

	assign FD_DENS_OUT	= ~DRIVE_CONTROL[0];
	assign FD_INUSE		= ~DRIVE_CONTROL[1];
	assign FD_DRVSEL		= ~DRIVE_CONTROL[5:2];
	assign FD_MOTEN		= ~DRIVE_CONTROL[6];
	assign FD_SIDESEL		= ~DRIVE_CONTROL[7];


/////////////////////////////////////////////////////////////////////////////
// Stepping rate generator

// Clock divider to produce 250us pulses from CLK_MASTER
	reg [15:0] master_clk_counter;
	reg STEP_GEN_MASTER_CLK;
	always @(posedge CLK_MASTER) begin
		if (master_clk_counter != 16'd5000) begin
			master_clk_counter <= master_clk_counter + 16'd1;
		end else begin
			master_clk_counter <= 16'd0;
			STEP_GEN_MASTER_CLK <= ~STEP_GEN_MASTER_CLK;
		end
	end

// Divide the 250us pulses down
	reg [7:0] step_rate_counter;
	reg step_ck_div_tgl;
	always @(posedge STEP_GEN_MASTER_CLK) begin
		if (step_rate_counter != STEP_RATE) begin
			step_rate_counter <= step_rate_counter + 8'd1;
		end else begin
			step_ck_div_tgl <= ~step_ck_div_tgl;
			step_rate_counter <= 8'd0;
		end
	end

	wire STEP_CLK = step_ck_div_tgl;


/////////////////////////////////////////////////////////////////////////////
// Stepping controller
	wire WRITE_STEP_REG;
	Flag_CrossDomain _fcd_write_step_reg(
					MCU_PMWR, MCU_PMWR && (MCU_ADDR[7:0] == 8'hFF),
					CLK_MASTER, WRITE_STEP_REG);
	StepController stepper(
		CLK_MASTER,
		STEP_CLK,
		1'b0,	/// TODO: connect to main reset
		SYNC_WRITE_REG,
		WRITE_STEP_REG,
		SR_FDS_STEPPING,
		FD_STEP,
		FD_DIR,
		FD_TRACK0_IN
		);


/////////////////////////////////////////////////////////////////////////////
// Acquisition

	// Clock-synchronised Start and Abort signals -- derived from writes to ACQCON
	wire ACQCON_START_sync, ACQCON_ABORT_sync, ACQCON_WRITE_sync;
	Flag_CrossDomain _fcd_write_acqcon_start(
					MCU_PMWR, MCU_PMWR && (MCU_ADDR[7:0] == 8'h05) && (MCU_PMD[0] == 1'b1),
					CLK_MASTER, ACQCON_START_sync);
	Flag_CrossDomain _fcd_write_acqcon_abort(
					MCU_PMWR, MCU_PMWR && (MCU_ADDR[7:0] == 8'h05) && (MCU_PMD[1] == 1'b1),
					CLK_MASTER, ACQCON_ABORT_sync);
	Flag_CrossDomain _fcd_write_acqcon_write(
					MCU_PMWR, MCU_PMWR && (MCU_ADDR[7:0] == 8'h05) && (MCU_PMD[2] == 1'b1),
					CLK_MASTER, ACQCON_WRITE_sync);

	// Acquisition control unit
	AcquisitionControl _acqcontrol(
		.CLK_32MHZ				(CLK_PLL32MHZ),
		.CLK_MASTER				(CLK_MASTER),
		.CLK_250US				(STEP_GEN_MASTER_CLK),
		.DATASEP_CLKSEL		(MFM_CLKSEL),
		.START					(ACQCON_START_sync),
		.ABORT					(ACQCON_ABORT_sync),
		.FD_INDEX_IN			(FD_INDEX_IN),
		.FD_RDDATA_IN			(FD_RDDATA_IN),
		.SR_R_FULL				(SR_R_FULL),
		.ACQ_START_MASK		(ACQ_START_MASK),
		.ACQ_START_NUM			(ACQ_START_NUM),
		.ACQ_STOP_MASK			(ACQ_STOP_MASK),
		.ACQ_STOP_NUM			(ACQ_STOP_NUM),
		.HSTMD_THRESH_START	(HSTMD_THRESH_START),
		.HSTMD_THRESH_STOP	(HSTMD_THRESH_STOP),
		.MFM_SYNCWORD_START	(MFM_SYNCWORD_START),
		.MFM_SYNCWORD_STOP	(MFM_SYNCWORD_STOP),
		.MFM_MASK_START		(MFM_MASK_START),
		.MFM_MASK_STOP			(MFM_MASK_STOP),
		.WAITING					(ACQSTAT_WAITING),
		.ACQUIRING				(ACQSTAT_ACQUIRING),
		.debug					()
	);

	// Data Acquisition Module
	DiscReader _discreader(
		.CLOCK					(CLK_MASTER),
		.RUN						(ACQSTAT_ACQUIRING),
		.FD_RDDATA_IN			(FD_RDDATA_IN),
		.FD_INDEX_IN			(FD_INDEX_IN),
		.RESET					(ACQCON_ABORT_sync),
		.DATA						(DAM_SRAM_WRITE_BUS),
		.WRITE					(DAM_SRAM_WR)
	);

	// Disc Writer track mark detector
	reg CLK_500US;
	always @(posedge STEP_GEN_MASTER_CLK) CLK_500US <= ~CLK_500US;
	wire TMD_DISCWRITER;
	TrackMarkDetector _trackmarkdetector_discwriter(
		.clock					(CLK_500US),
		.reset					(ACQCON_ABORT_sync),
		.index					(FD_INDEX_IN),
		.threshold				(HSTMD_THRESH_WRITE),
		.detect					(TMD_DISCWRITER)
	);

	// Disc Writer Module
	DiscWriter _discwriter(
		.reset					(ACQCON_ABORT_sync),
		.clock					(CLK_MASTER),
		.mdat						(SRAM_DQ),
		.maddr_inc				(SRA_INCREMENT_DWC),
		.wrdata					(FD_WRDATA),
		.wrgate					(FD_WRGATE),
		.trkmark					(TMD_DISCWRITER),
		.index					(FD_INDEX_IN),
		.start					(ACQCON_WRITE_sync),
		.running					(ACQSTAT_WRITING)
	);

endmodule

// vim: ts=3 sw=3
