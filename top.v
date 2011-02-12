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
// System version numbers
	localparam	MCO_TYPE		= 16'hDD55;		// Microcode type
	localparam	MCO_VERSION	= 16'h001F;		// Microcode version


/////////////////////////////////////////////////////////////////////////////
// Unused I/O pins

	// SRAM chip select -- we keep the SRAM selected to get the fastest
	// access times.
	assign	SRAM_CE_n	= 1'b0;

	
/////////////////////////////////////////////////////////////////////////////
// Clock generation
	// Instantiate a PLL to generate the master and data-separator clocks from
	// the 20MHz crystal oscillator input
	wire CLK_DATASEP, CLK_MASTER, PLL_LOCKED;
	ClockGenerator clkgen(
		.inclk0	(CLOCK),							// 20MHz input clock from the XTAL OSC
		.c0		(CLK_DATASEP),					// 40MHz DPLL clock (sync detector)
		.c1		(CLK_MASTER),					// 100MHz master clock
		.locked	(PLL_LOCKED)					// PLL Lock status output
		);

	// NOTE: If you change the frequency of CLK_MASTER, then update this value!
	localparam CLK_MASTER_FREQ = 32'd100_000_000;
	// NOTE: If you change the frequency of CLK_DATASEP, then update this value!
	localparam CLK_DATASEP_FREQ = 32'd40_000_000;
		
	// Clock divider to produce pulses 500us and 250us apart from CLK_MASTER
	// 250us = 4kHz. We set the counter for 500us pulses, then generate an extra pulse.
	reg [15:0] master_clk_counter;
	always @(posedge CLK_MASTER) begin
		if (master_clk_counter < (CLK_MASTER_FREQ / 32'd2_000)) begin
			master_clk_counter <= master_clk_counter + 16'd1;
		end else begin
			master_clk_counter <= 16'd0;
		end
	end

	// 500us only generates one pulse per counter cycle
	wire CKE_500US	=	(master_clk_counter == 16'd0);
	// 250us generates an extra pulse mid-count
	wire CKE_250US	=	(master_clk_counter == 16'd0) || (master_clk_counter == (CLK_MASTER_FREQ / 32'd4_000));

	// Clock divider -- converts CLK_MASTER into a 10us repetitive pulse train
	reg [15:0] index_clk_counter;
	always @(posedge CLK_MASTER) begin
		if (index_clk_counter < (CLK_MASTER_FREQ / 32'd100_000)) begin
			index_clk_counter <= index_clk_counter + 16'd1;
		end else begin
			index_clk_counter <= 16'd0;
		end
	end

	// Index frequency reference clock
	wire CKE_INDEXFREQ	=	(master_clk_counter == 16'd0);

	
/////////////////////////////////////////////////////////////////////////////
// Clock counter

// These 8-bit counters are incremented once per clock tick, and are used by
// the ATE diagnostics to prove that the FPGA clock oscillator is functioning.
// One clock counter handles the 20MHz clock, the other handles the PLL'd clock.
reg [7:0] clock_ticker, clock_ticker_pll;

always @(posedge CLOCK) clock_ticker <= clock_ticker + 8'b1;
always @(posedge CLK_MASTER) clock_ticker_pll <= clock_ticker_pll + 8'b1;


/////////////////////////////////////////////////////////////////////////////
// Status LED

// Set this parameter to a nonzero value to make the Status LED blink at ~2Hz
// instead of lighting when the FPGA is busy.
localparam STATUSLED_BLINK_ONLY = 0;

	generate
	if (STATUSLED_BLINK_ONLY) begin
		// Uncomment this block to make the status LED 
		reg [31:0] status_led_counter;
		reg status_led_r;
		assign STATUS_LED = status_led_r;

		always @(posedge CLK_MASTER) begin
			if (status_led_counter > (CLK_MASTER_FREQ / 2)) begin
				status_led_counter <= 32'd0;
				status_led_r <= ~status_led_r;
			end else begin
				status_led_counter <= status_led_counter + 1;
			end
		end
	end else begin
		// Status LED should be on if we're acquiring, or waiting for a trigger event
		// It will also stick on if the PLL is jammed...
		assign STATUS_LED = !(ACQSTAT_WAITING | ACQSTAT_ACQUIRING | ACQSTAT_WRITING | !PLL_LOCKED);
	end
	endgenerate
	
	
/////////////////////////////////////////////////////////////////////////////
// High Speed I/O Port

	// HSIO Direction and Data registers
	reg [3:0] HSIO_DIR, HSIO_DATA;

	// HSIO I/O logic
	generate
		genvar i;
		for (i = 0; i < 4; i = i + 1)
		begin : hsioloop
			assign HSIO_PORT[i] = HSIO_DIR[i] ? 1'bZ : HSIO_DATA[i];
		end
	endgenerate

	
/////////////////////////////////////////////////////////////////////////////
// SRAM interface

// Read/write signalling
	// Write signal from Data Acquisition (DiscReader) module
	wire			DAM_SRAM_WR;

// Data out from the Acquisition (DiscReader) module
	wire[7:0]	DAM_SRAM_WRITE_BUS;

// Data bus from the MCU Interface
	reg[7:0]		PMD_LATCHED;
	always @(posedge MWC_WRITE_SRAM_DATA) begin
		PMD_LATCHED <= MCU_PMD;
	end

// SRAM data bus is driven by us if OE is inactive, else it's Hi-Z
	wire[7:0]	FIFO_Q;
	assign		SRAM_DQ		= SRAM_OE_n ? /*SRAM_DQ_WR*/ FIFO_Q : 8'hzz;


/////////////////////////////////////////////////////////////////////////////
// Memory write controller

	// TODO: FIFO Full should cause an acquisition abort
	wire FIFO_EMPTY, FIFO_FULL;
	ramfifo _ramfifo(
		.clock		(CLK_MASTER),
		// Bus arbitration: DAM has the write bus when ACQSTAT_WAITING or ACQSTAT_ACQUIRING
		.data			(((ACQSTAT_WAITING) || (ACQSTAT_ACQUIRING)) ? DAM_SRAM_WRITE_BUS : PMD_LATCHED),
		.rdreq		(MWC_CUR_STATE == MWC_S_OEIA),
		.sclr			(ACQCON_ABORT_sync),
		.wrreq		(MWC_WRITE_SRAM_DATA || DAM_SRAM_WR),
		.empty		(FIFO_EMPTY),
		.full			(FIFO_FULL),
		.q				(FIFO_Q)
	);

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

	// SRAM Write command bit from register address decoder (below)
	wire MWC_WRITE_SRAM_DATA, MWC_WRITE_SRAM_DATA_pre;
	Flag_Delay1tcy_OneCycle _fd1oc_ramwr_sync(CLK_MASTER, MCU_PMWR_sync && (MCU_ADDR[7:0] == 8'h03), MWC_WRITE_SRAM_DATA);

	// MWC State machine
	always @(posedge CLK_MASTER) begin
		case (MWC_CUR_STATE)
			MWC_S_IDLE:		begin
								// S_IDLE: Idle state. Write bit inactive, OE active.
								SRAM_WE_n_r			<= 1'b1;
								SRAM_OE_n_r			<= 1'b0;
								SRA_INCREMENT_MWC	<= 1'b0;

								if (!FIFO_EMPTY) begin
									MWC_CUR_STATE	<= MWC_S_OEIA;
								end else begin
									MWC_CUR_STATE	<= MWC_S_IDLE;
								end
							end

			MWC_S_OEIA:		begin
								// S_OEIA: Make OE inactive and load data
								// FIFO latches data into its output FF
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
								// S_WRITEEND: End write cycle
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

	// Generate a falling-edge-detect signal for PMRD
	// Delay increment 
	wire SRA_INCREMENT_RAMRD_DONE;
	Flag_Delay1tcy_OneCycle _fd1oc_ramread_done(CLK_MASTER, !((MCU_ADDR[7:0] == 8'h03) && MCU_PMRD_sync), SRA_INCREMENT_RAMRD_DONE);

	// SRAM address should increment after an SRAM read or write operation.
	// DWC = Disc Write Controller
	// MWC = Memory Write Controller
	// RAMRD = RAM Read
	wire SRA_INCREMENT_DWC;
	wire SRA_INCREMENT = (SRA_INCREMENT_DWC) || (SRA_INCREMENT_MWC) || (SRA_INCREMENT_RAMRD_DONE);

	wire ACO_WRITE_UPPER, ACO_WRITE_HIGH, ACO_WRITE_LOW;
	Flag_Delay1tcy_OneCycle _fd1oc_aco_wr_u(CLK_MASTER, MCU_PMWR && (MCU_ADDR[7:0] == 8'h02),
					ACO_WRITE_UPPER);
	Flag_Delay1tcy_OneCycle _fd1oc_aco_wr_h(CLK_MASTER, MCU_PMWR && (MCU_ADDR[7:0] == 8'h01),
					ACO_WRITE_HIGH);
	Flag_Delay1tcy_OneCycle _fd1oc_aco_wr_l(CLK_MASTER, MCU_PMWR && (MCU_ADDR[7:0] == 8'h00),
					ACO_WRITE_LOW);

	AddressCounter addr_count(
		CLK_MASTER,				// Master clock
		SRAM_A,					// SRAM address output
		SRA_INCREMENT,			// Increment input
		SR_R_EMPTY,				// Empty flag (status register read)
		SR_R_FULL,				// Full flag (status register read)
		1'b0, //SR_W_RESET,	// Reset (status register write)
		MCU_PMD,					// Data source for load operations
		ACO_WRITE_UPPER,		// Write upper address bits
		ACO_WRITE_HIGH,		// Write high  address bits
		ACO_WRITE_LOW			// Write low   address bits
	);


/////////////////////////////////////////////////////////////////////////////
// Index frequency measurement logic

	// Synchronise index with clock
	reg [2:0] INDEX_SYNC_r;
	always @(posedge CLK_MASTER) INDEX_SYNC_r <= {INDEX_SYNC_r[0], FD_INDEX_IN};
	
	// Detect rising edge of index pulse
	wire INDEX_RISING_EDGE = !INDEX_SYNC_r[1] && INDEX_SYNC_r[0];

	// Measure index frequency
	reg	[15:0]	INDEX_FREQ;				// index frequency counter
	reg	[15:0]	INDEX_FREQ_LAT;		// index frequency latch
	reg	[7:0]		INDEX_FREQ_LOW;		// Index frequency low, latched when index freq high reg is read
	
	always @(posedge CLK_MASTER) begin
		if (INDEX_RISING_EDGE) begin
			// index pulse -- save current frequency count and clear counter
			INDEX_FREQ_LAT <= INDEX_FREQ;
			INDEX_FREQ <= 16'd0;
		end else begin
			if (CKE_INDEXFREQ) begin
				// Increment index frequency count if CKE is active
				INDEX_FREQ <= INDEX_FREQ + 16'd1;
			end
		end
	end
	
	// Latch low byte of INDEX_FREQ_LAT when the high byte is read
	// This stops us getting the high byte of one measurement and the low byte of the next.
	// Well, as long as we read the index frequency in HIBYTE-LOBYTE order, at least.
	wire DO_LATCH_INDEX_LOW;
	Flag_Delay1tcy_OneCycle _fd1oc_ixhi_rd(CLK_MASTER, MCU_PMRD && (MCU_ADDR[7:0] == 8'h40),
				DO_LATCH_INDEX_LOW);
	always @(posedge CLK_MASTER) begin
		if (DO_LATCH_INDEX_LOW) begin
			INDEX_FREQ_LOW <= INDEX_FREQ_LAT[7:0];
		end
	end


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
	
	reg	[7:0]		SRAM_DQ_LAT;			// Read-data from the SRAM, latched on L->H edge on PMRD

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
/*	always @(negedge MCU_PMALH)
		MCU_ADDRH <= MCU_PMD;
	always @(negedge MCU_PMALL)
		MCU_ADDRL <= MCU_PMD;
*/
	always @(posedge CLK_MASTER) begin
		if (MCU_PMALH) MCU_ADDRH <= MCU_PMD;
		if (MCU_PMALL) MCU_ADDRL <= MCU_PMD;
	end

// Sync PMWR and PMRD against master clock and limit to one cycle
	wire MCU_PMRD_sync, MCU_PMWR_sync;
	Flag_Delay1tcy_OneCycle _fd1oc_pmwr_sync(CLK_MASTER, MCU_PMWR, MCU_PMWR_sync);
	Flag_Delay1tcy_OneCycle _fd1oc_pmrd_sync(CLK_MASTER, MCU_PMRD, MCU_PMRD_sync);
	
// Handle host interface reads and writes
	always @(posedge CLK_MASTER) begin
		// Hold SRAM data steady when PMRD goes high
		if (!MCU_PMRD_sync && (MCU_ADDR[7:0] == 8'h03)) begin
			SRAM_DQ_LAT <= SRAM_DQ;
		end
	
		if (MCU_PMWR_sync) begin
		/// Register Write
		case (MCU_ADDR[7:0])
			8'h00,
			8'h01,
			8'h02: begin			// SRAM_ADDR_{LOW,HIGH,UPPER}
						// Note: other logic for this state below.
					 end

				8'h03: begin			// SRAM_DATA
							// Note: handled by Memory Write Controller (above)
					 end

				8'h04: begin			// DRIVE_CONTROL
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

			8'hE0: begin			// HSIO_DIR
						HSIO_DIR <= MCU_PMD[3:0];
					 end

			8'hE1: begin			// HSIO_DATA
						HSIO_DATA <= MCU_PMD[3:0];
					 end

			8'hF0: begin			// STEP_RATE -- Disc drive step rate
						STEP_RATE <= MCU_PMD;
					 end

			8'hFF: begin			// STEP_CMD  -- Disc drive step command
						// Note: other logic for this state below.
					 end

			default: begin
					 end
		endcase
		end
	end

	// Multiplexer for readback (MCU_PMD_OUT)
	always @(*) begin
		case (MCU_ADDR[7:0])
			8'h00:	MCU_PMD_OUT = SRAM_A[7:0];						// SRAM_ADDR_LOW
			8'h01:	MCU_PMD_OUT = SRAM_A[15:8];					// SRAM_ADDR_HIGH
			8'h02:	MCU_PMD_OUT = {5'b00000, SRAM_A[18:16]};	// SRAM_ADDR_UPPER
			8'h03:	MCU_PMD_OUT = SRAM_DQ_LAT[7:0];				// SRAM_DATA_LOW
			8'h04:	MCU_PMD_OUT = MCO_TYPE[7:0];					// Microcode type low
			8'h05:	MCU_PMD_OUT = MCO_TYPE[15:8];					// Microcode type high
			8'h06:	MCU_PMD_OUT = MCO_VERSION[7:0];				// Microcode version low
			8'h07:	MCU_PMD_OUT = MCO_VERSION[15:8];				// Microcode version high
			8'h0E:	MCU_PMD_OUT =										// STATUS1 register
							// ACQUIRING is set active if the fifo is still draining.
							{5'b0, ACQSTAT_WRITING, ACQSTAT_WAITING, ACQSTAT_ACQUIRING | (!FIFO_EMPTY)};
			8'h0F:	MCU_PMD_OUT =										// STATUS2 register
							{FD_INDEX_IN, FD_TRACK0_IN, FD_WRPROT_IN, FD_RDY_DCHG_IN,
							 FD_DENS_IN, SR_FDS_STEPPING, SR_R_EMPTY, SR_R_FULL};
			8'h30:	MCU_PMD_OUT = SCRATCHPAD;						// Scratchpad register
			8'h31:	MCU_PMD_OUT = ~SCRATCHPAD;						// Inverse Scratchpad register
			8'h32:	MCU_PMD_OUT = 8'h55;								// Fixed 0x55 register
			8'h33:	MCU_PMD_OUT = 8'hAA;								// Fixed 0xAA register
			8'h34:	MCU_PMD_OUT = clock_ticker;					// Clock ticker (20MHz)
			8'h35:	MCU_PMD_OUT = clock_ticker_pll;				// Clock ticker (PLL)
			8'h40:	begin													// Index frequency high-byte
							MCU_PMD_OUT = INDEX_FREQ_LAT[15:8];
							// INDEX_FREQ_LOW latched above
						end
			8'h41:	MCU_PMD_OUT = INDEX_FREQ_LOW;					// Index frequency low-byte
			8'hE1:	MCU_PMD_OUT = HSIO_PORT;						// HSIO readback
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
// Stepping controller
	
	// Divide the 250us pulses down to generate the stepping clock
	reg [7:0] step_rate_counter;
	reg step_ck_div_tgl;
	always @(posedge CLK_MASTER) begin
		if (CKE_250US) begin
			if (step_rate_counter != STEP_RATE) begin
				step_rate_counter <= step_rate_counter + 8'd1;
			end else begin
				step_ck_div_tgl <= ~step_ck_div_tgl;
				step_rate_counter <= 8'd0;
			end
		end
	end

	wire STEP_CLK = step_ck_div_tgl;

	// The stepping controller itself
	StepController stepper(
		CLK_MASTER,
		STEP_CLK,
		1'b0,	/// TODO: connect to main reset
		MCU_PMD,
		(MCU_ADDR[7:0] == 8'hFF) && MCU_PMWR_sync,
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
	// NOTE: Set PJL_COUNTER_MAX to half of the data separator clock frequency in MHz.
	//   e.g. If CLK_DATASEP = 40MHz, set this to 20.
	//        If CLK_DATASEP = 32MHz, set this to 16.
	// This is done auto-magically, assuming CLK_DATASEP_FREQ is set correctly above!
	defparam _acqcontrol.PJL_COUNTER_MAX = CLK_DATASEP_FREQ / 32'd2_000_000;
	AcquisitionControl _acqcontrol(
		.CLK_DATASEP			(CLK_DATASEP),
		.CLK_MASTER				(CLK_MASTER),
		.CKE_500US				(CKE_500US),
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
	wire TMD_DISCWRITER;
	TrackMarkDetector _trackmarkdetector_discwriter(
		.clock					(CLK_MASTER),
		.cke						(CKE_500US),
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
