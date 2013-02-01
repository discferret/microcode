/*****************************************************************************
 * Red Fox Engineering
 *
 * DiscFerret Magnetic Disc Analyser
 *
 * Testbench: DiscWriter IP core
 *
 * Copyright (C) 2012 Philip Pemberton t/a Red Fox Engineering.
 * All rights reserved.
 * Distributed under the terms of the GNU General Public Licence, version 3.
 */

`timescale 1ns / 1ns
`define FINISH_ON_ABORT

module main;

	//////////////////////////////////////////////////////////////////////////
	// Global pins / nets / regs
	reg reset, index, trkmark, start;
	wire wrdata, wrgate, running;

	// Set initial states
	initial begin
		reset	= 0;
		index	= 0;
		trkmark = 0;
		start = 0;
	end


	//////////////////////////////////////////////////////////////////////////
	// Clock generation
	reg clock;
	initial clock = 0;
	always begin
		#5 clock = ~clock;
	end

	// Include testbench utilities
	`include "../tb_utils.v"


	//////////////////////////////////////////////////////////////////////////
	// Memory emulator
	wire maddr_inc;
	wire [7:0] memdata;

	reg [7:0] memory [31:0];
	initial begin
		$readmemb("rom.dat", memory);
	end

	reg [4:0] memaddr;
	always @(posedge clock) begin
		if (maddr_inc) begin
			memaddr <= memaddr + 'd1;
		end else if (reset) begin
			memaddr <= 'd0;
		end
	end
	assign memdata = memory[memaddr];


	//////////////////////////////////////////////////////////////////////////
	// main testbench block
	integer i, j;
	parameter TEST2_COUNT_MAX = 512;
	reg [512*8:0] str;
	initial begin
		$display(">>>>>> DiscWriter testbench started");
`ifdef ENABLE_VCD_DUMP
		$dumpfile("discwriter_tb.vcd");
		$dumpvars(0, main);
`endif

		//////////////////////////////////////////////////////////////////////
		// Reset to sane default state
		test_start("Reset logic");
		waitclks(2);
		reset = 1;
		waitclks(10);
		reset = 0;
		test_done;


		test_start("ROM Run");
		waitclks(10);
		start = 1;
		waitclks(1);
		start = 0;
		waitclks(100);
		test_done;


		////////// end of tests //////////
		waitclks(10);
		$finish;
	end

	////////////
	// Instantiate a Disc Writer
	//
	DiscWriter _writer(
		.reset			(reset),
		.clock			(clock),
		.clken			(1'b1),			// TODO: clock enable
		.mdat			(memdata),		// memory data
		.maddr_inc		(maddr_inc),	// memory address increment
		.wrdata			(wrdata),
		.wrgate			(wrgate),
		.trkmark		(trkmark),
		.index			(index),
		.start			(start),
		.running		(running)
	);
endmodule
