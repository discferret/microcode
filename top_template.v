module ate(
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
	CLOCK												/* 20MHz clock							*/
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

	assign SRAM_A = 19'd0;
	assign SRAM_DQ = 8'hZZ;
	assign SRAM_WE_n = 1'b1;
	assign SRAM_OE_n = 1'b0;
	assign SRAM_CE_n = 1'b0;

	assign FD_DRVSEL = 3'b000;
	assign FD_DENS_OUT = 1'b0;
	assign FD_INUSE = 1'b0;
	assign FD_MOTEN = 1'b0;
	assign FD_DIR = 1'b1;
	assign FD_STEP = 1'b1;
	assign FD_WRDATA = 1'b1;
	assign FD_WRGATE = 1'b1;
	assign FD_SIDESEL = 1'b1;

	assign HSIO_PORT = 4'd0;

/////////////////////////////////////////////////////////////////////////////
// System version numbers
	localparam	MCO_TYPE		= 16'hDD55;		// Microcode type
	localparam	MCO_VERSION	= 16'h001A;		// Microcode version


/////////////////////////////////////////////////////////////////////////////
// Status LED
	reg [31:0] status_led_counter;
	reg status_led_r;
	assign STATUS_LED = status_led_r;

	always @(posedge CLOCK) begin
		if (status_led_counter > 32'd20_000_000) begin
			status_led_counter <= 32'd0;
			status_led_r <= ~status_led_r;
		end else begin
			status_led_counter <= status_led_counter + 1;
		end
	end


/////////////////////////////////////////////////////////////////////////////
// MCU Bus

	// Data bus driver
	/*reg*/wire [7:0] MCU_PMD_OUT;
	assign MCU_PMD = MCU_PMRD ? MCU_PMD_OUT : 8'hZZ;

	// Address bus demultiplexing.
	// TODO: make this synchronous to CLOCK if possible?
	reg [7:0] MCU_ADDRH, MCU_ADDRL;
	always @(negedge MCU_PMALH)
		MCU_ADDRH <= MCU_PMD;
	always @(negedge MCU_PMALL)
		MCU_ADDRL <= MCU_PMD;

	// hey look, it's a 32-byte static RAM! what an absolutely amazing thing to do
	// with a 20 quid, 8-kilocell FPGA!
	reg [7:0] regs [31:0];
	always @(posedge MCU_PMWR)
		regs[MCU_ADDRL[5:0]] <= MCU_PMD;

	assign MCU_PMD_OUT = regs[MCU_ADDRL[5:0]];

endmodule

// vim: ts=3
