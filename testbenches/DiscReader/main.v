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
	wire fifo_write;
	wire [7:0] fifo_data;

`ifndef MEMORY_SIZE
	parameter RAMBYTES = 8;
`else
	parameter RAMBYTES = `MEMORY_SIZE;
`endif
	reg [7:0] fifo_buffer [RAMBYTES-1:0];
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
				$stop;
			end
`ifdef DEBUG
			$display("FIFO POP  >> 0x%02x", fifo_buffer[fifo_rdptr]);
`endif
			fifo_read = fifo_buffer[fifo_rdptr];
			fifo_rdptr = (fifo_rdptr + 1) % RAMBYTES;
			fifo_count = fifo_count - 1;
		end
	endfunction

	function [31:0] fifo_sum;
		input dummy;
		integer j, k, l;
		begin
			if (fifo_count < 1) begin
				$display("/!\\  TESTBENCH ABORTED:  Attempt to sum an empty FIFO!");
				$stop;
			end
			j=0; k=fifo_count; l=0;
			while (k > 0) begin
				j = j + fifo_read(0);
				k = k - 1;
				l = l + 1;
			end
			fifo_sum=j;
`ifdef DEBUG
			$display("(i)  Sum of %d fifo bytes is %d", l, fifo_sum);
`endif
		end
	endfunction

	initial begin
		$display("FIFO initialised with %d bytes of storage", RAMBYTES);
		fifo_flush;
	end
	always @(posedge clock) begin
		if (fifo_write) begin
			if ((fifo_count + 1) >= RAMBYTES) begin
				$display("/!\\  TESTBENCH ABORTED:  FIFO OVERFLOW!");
				$stop;
			end
			// store byte
			fifo_buffer[fifo_wrptr] = fifo_data;
			fifo_wrptr = (fifo_wrptr + 1) % RAMBYTES;
			fifo_count = fifo_count + 1;
`ifdef DEBUG
			$display("FIFO PUSH >> 0x%x", fifo_data);
`endif
		end
	end

	//////////////////////////////////////////////////////////////////////////
	// main testbench block
	integer i;
	initial begin
		$display(">>>>>> DiscReader testbench started");
		$dumpfile("discreader_tb.vcd");
		$dumpvars(0, main);

		//////////////////////////////////////////////////////////////////////
		// Reset to sane default state
		$display(">>> TEST: Reset");
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
			$display(":-(   Test failed -- RAMSUM %d, expected %d", i, 1);
			$stop;
		end

		//////////////////////////////////////////////////////////////////////
		// Make sure long data pulses are counted as one pulse
		// Make sure long index pulses are counted as one pulse
		// Check timing -- num clock cycles matches sum
		// Collision between counter overflow and data store
		// Collision between counter overflow and index store
		// Collision between index store and data store
		// Collision between counter overflow, data store and index store
		// Count with clock enable

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
