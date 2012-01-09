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
	if (clks > 0) begin
		for (i=0; i<clks; i=i+1) begin
			waitclk;
		end
	end
endtask

task abort;
	input [512*8:0] str;
	begin
		$display("/!\\  ABORT: %0s", str);
`ifndef FINISH_ON_ABORT
		$stop;
`else
		$finish;
`endif
	end
endtask

reg [60*8:0] last_test;
task test_start;
	input [60*8:0] str;
	begin
		$display(">>> Test started:  %0s", str);
		last_test = str;
	end
endtask

task test_done;
	begin
		$display(">>> Test finished: %0s\n", last_test);
	end
endtask
