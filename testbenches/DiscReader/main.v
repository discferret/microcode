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
`define FINISH_ON_ABORT

module main;

	//////////////////////////////////////////////////////////////////////////
	// Global pins / nets / regs
	reg reset, run, rddata;
	// Set initial states
	initial begin
		reset = 0;
		run = 0;
		rddata = 0;
	end

	//////////////////////////////////////////////////////////////////////////
	// Clock generation
	reg clock;
	initial clock = 0;
	always begin
		#5 clock = ~clock;
	end

	// Include testbench utilities
	`include "tb_utils.v"

	//////////////////////////////////////////////////////////////////////////
	// FIFO, or a reasonable facsimile of one.
	wire fifo_write;
	wire [7:0] fifo_data;

`ifndef MEMORY_SIZE
	parameter FIFOSIZE = 512;
`else
	parameter FIFOSIZE = `MEMORY_SIZE;
`endif
	reg [7:0] fifo_buffer [FIFOSIZE-1:0];
	integer fifo_wrptr, fifo_rdptr, fifo_count;

	task fifo_flush;
		begin
			fifo_wrptr = 0;
			fifo_rdptr = 0;
			fifo_count = 0;
		end
	endtask

	function [31:0] fifo_read;
		input dummy;
		reg [7:0] x;
		begin
			if (fifo_count < 1) begin
				$display("/!\\  TESTBENCH ABORTED:  FIFO UNDERFLOW");
`ifndef FINISH_ON_ABORT
				$stop;
`else
				$finish;
`endif
			end else begin
`ifdef DEBUG
				$display("FIFO POP  >> 0x%0x", fifo_buffer[fifo_rdptr]);
`endif
				fifo_read = fifo_buffer[fifo_rdptr];
				fifo_rdptr = (fifo_rdptr + 1) % FIFOSIZE;
				fifo_count = fifo_count - 1;
			end
		end
	endfunction

	function [31:0] fifo_sum;
		input dummy;
		integer j, k, l;
		begin
			if (fifo_count < 1) begin
				$display("/!\\  TESTBENCH ABORTED:  Attempt to sum an empty FIFO!");
`ifndef FINISH_ON_ABORT
				$stop;
`else
				$finish;
`endif
			end else begin
				j=0; k=fifo_count; l=0;
				while (k > 0) begin
					j = j + fifo_read(0);
					k = k - 1;
					l = l + 1;
				end
				fifo_sum=j;
`ifdef DEBUG
				$display("(i)  Sum of %0d fifo bytes is %0d", l, fifo_sum);
`endif
			end
		end
	endfunction

	task fifo_dump;
		integer j, k, l;
		begin
			if (fifo_count < 1) begin
				$display("/!\\  TESTBENCH ABORTED:  Attempt to dump an empty FIFO!");
`ifndef FINISH_ON_ABORT
				$stop;
`else
				$finish;
`endif
			end else begin
				k=fifo_count; l=1;
				while (k > 0) begin
					j = fifo_read(0);
					$display("FIFO byte %0d is 0x%0x", l, j);
					k = k - 1;
					l = l + 1;
				end
			end
		end
	endtask

	initial begin
		$display("FIFO initialised with %0d bytes of storage", FIFOSIZE);
		fifo_flush;
	end
	always @(posedge clock) begin
		if (fifo_write) begin
			if ((fifo_count + 1) >= FIFOSIZE) begin
				abort("FIFO Overflow!");
			end else begin
				// store byte
				fifo_buffer[fifo_wrptr] = fifo_data;
				fifo_wrptr = (fifo_wrptr + 1) % FIFOSIZE;
				fifo_count = fifo_count + 1;
`ifdef DEBUG
				$display("FIFO PUSH >> 0x%0x", fifo_data);
`endif
			end
		end
	end

	//////////////////////////////////////////////////////////////////////////
	// main testbench block
	integer i, j;
	parameter TEST2_COUNT_MAX = 512;
	reg [512*8:0] str;
	initial begin
		$display(">>>>>> DiscReader testbench started");
`ifdef ENABLE_VCD_DUMP
		$dumpfile("discreader_tb.vcd");
		$dumpvars(0, main);
`endif

		//////////////////////////////////////////////////////////////////////
		// Reset to sane default state
		test_start("Reset logic");
		waitclks(2);
		reset = 1;
		waitclks(10);
		reset = 0;

		// Flush the counter
		run = 1;
		rddata = 1;
		waitclk;
		rddata = 0;
		waitclks(2);

		// That should have caused a STORE of 1 clock
		i = fifo_sum(0);
		if (i != 1) begin
			$sformat(str, "Test failed. RAMSUM=%0d, wanted %0d", i, 1);
			abort(str);
		end
		test_done;

		//////////////////////////////////////////////////////////////////////
		// Make sure long data pulses are counted as one pulse

		//////////////////////////////////////////////////////////////////////
		// Make sure long index pulses are counted as one pulse

		//////////////////////////////////////////////////////////////////////
		// Check timing -- num clock cycles matches sum
		// Ierate over all sane timing values to make sure the timer and
		// overflow logic works.
		$sformat(str, "Counter/carry, simple, from 1 to %0d clocks", TEST2_COUNT_MAX);
		test_start(str);
		for (i=1; i<TEST2_COUNT_MAX; i=i+1) begin
			// start with a pulse to force a store of whatever's in the
			// timer register
			rddata = 1;
			waitclk;
			rddata = 0;
			// wait the desired number of clocks
			waitclks(i);
			// strobe read-data again
			rddata = 1;
			waitclk;
			rddata = 0;
			// give the disc writer chance to write to the fifo
			waitclks(5+(i/127));
			// now dump the first byte of the fifo (we don't care what it's
			// set to, it'll be fairly arbitrary).
			j = fifo_read(0);
			// and get the sum of the remaining bytes
			j = fifo_sum(0);
			if (i != j) begin
				$sformat(str, "Test failed. FIFO_SUM=%0d, wanted %0d", j, i);
				abort(str);
			end
		end
		test_done;

		//////////////////////////////////////////////////////////////////////
		// Collision between counter overflow and data store
		test_start("Collision between counter overflow and data store");
		// Start by sending a clear pulse, same as we did with the previous
		// test.
		rddata = 1;
		waitclk;
		rddata = 0;
		// Wait 127 clocks then send another pulse
		waitclks(127);
		rddata = 1;
		waitclk;
		rddata = 0;
		// Wait 5 clocks for the DWE to finish storing
		waitclks(5);
		// Ditch the first byte
		i = fifo_read(0);
		// Make sure we got the expected data in the FIFO
		i = fifo_read(0);
		if (i != 'h7F) begin
			$sformat(str, "First FIFO byte incorrect, expected carry (0x7F), got 0x%0x", i);
			abort(str);
		end
		i = fifo_read(0);
		if (i != 'h00) begin
			$sformat(str, "Second FIFO byte incorrect, expected carry (0x00), got 0x%0x", i);
			abort(str);
		end
		test_done;

		//////////////////////////////////////////////////////////////////////
		// Collision between counter overflow and index store

		//////////////////////////////////////////////////////////////////////
		// Collision between index store and data store

		//////////////////////////////////////////////////////////////////////
		// Collision between counter overflow, data store and index store

		//////////////////////////////////////////////////////////////////////
		// Count with clock enable disabled (timer should freeze at current
		// value while CLKEN == 0)

		//////////////////////////////////////////////////////////////////////
		// Count with RUN disabled (timer should reset and should NOT allow
		// store if RUN == 0)

		////////// end of tests //////////
		waitclks(10);
		$finish;
	end

	////////////
	// Instantiate a DiscReader
	DiscReader _reader(
		.CLOCK			(clock),
		.CLKEN			(1'b1),		// TODO: clock enable
		.RUN			(run),
		.FD_RDDATA_IN	(rddata),
		.FD_INDEX_IN	(1'b0),		// TODO: index
		.RESET			(reset),
		.DATA			(fifo_data),
		.WRITE			(fifo_write)
	);

endmodule
