/*****************************************************************************
 * Red Fox Engineering
 *
 * DiscFerret Magnetic Disc Analyser
 *
 * Testbench: DiscReader IP core
 *
 * Copyright (C) 2012 Philip Pemberton t/a Red Fox Engineering.
 * All rights reserved.
 * Distributed under the terms of the GNU General Public Licence, version 3.
 */

`timescale 1ns / 1ns

module main;

	//////////////////////////////////////////////////////////////////////////
	// Global pins / nets / regs
	reg reset;

	//////////////////////////////////////////////////////////////////////////
	// Clock generation
	reg clock;
	initial clock = 0;
	always begin
		#5 clock = ~clock;
	end

	//////////////////////////////////////////////////////////////////////////
	// Wait one clock cycle
	// TODO: Watchdog timer?
	task waitclk;
		begin
			@(posedge clock) begin
			end
		end
	endtask

	// Wait multiple clock cycles
	task waitclks;
		input [31:0] clks;
		integer i;
		for (i=0; i<clks; i=i+1) begin
			waitclk;
		end
	endtask

	//////////////////////////////////////////////////////////////////////////
	// RAM simulation -- actually emulates a FIFO...
	wire ram_write;
	wire [7:0] ram_data;

`ifndef MEMORY_SIZE
	parameter RAMBYTES = 8;
`else
	parameter RAMBYTES = `MEMORY_SIZE;
`endif
	reg [7:0] ram_buffer [RAMBYTES-1:0];
	integer rampos, ramcount;

	task ram_flush;
		begin
			rampos = 0;
			ramcount = 0;
		end
	endtask

	initial begin
		$display("RAM initialised with %d bytes of storage", RAMBYTES);
		ram_flush;
	end
	always @(posedge ram_write) begin
		if ((rampos + 1) >= RAMBYTES) begin
			$display("/!\\  TESTBENCH ABORTED:  RAM OVERFLOW!");
			$stop;
		end
		// store byte
		ram_buffer[rampos] = ram_data;
		rampos = rampos + 1;
	end

	//////////////////////////////////////////////////////////////////////////
	// main testbench block
	initial begin
		$display(">>>>>> DiscReader testbench started");
		$dumpfile("discreader_tb.vcd");
		$dumpvars(0, main);

		// Test reset
		$display(">>> TEST: Reset");
		waitclks(2);
		reset = 1;
		waitclks(10);
		reset = 0;

		$finish;
	end

endmodule
