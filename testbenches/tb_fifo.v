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
