/**
 * Track-mark detector for hard-sectored discs
 */

module TrackMarkDetector(clock, cke, reset, index, threshold, detect);
	input					clock;			// clock input, positive-edge-triggered
	input					cke;				// clock enable, positive-true
	input					reset;			// reset input, positive-edge-triggered
	input					index;			// index pulse input, active high
	input		[7:0]		threshold;		// threshold value
	output				detect;			// detection state output

/////////////////////////////////////////////////////////////////////////////
// Time counter
	reg [7:0] timer;
	always @(posedge clock or posedge index) begin
		if (index) begin
			timer <= 8'b0;
		end else begin
			if (cke) begin
				timer <= timer + 8'd1;
			end
		end
	end

/////////////////////////////////////////////////////////////////////////////
// Time latch
	reg [7:0] tlatch;
	always @(posedge index) begin
		tlatch <= timer;
	end

/////////////////////////////////////////////////////////////////////////////
// Track last few output states -- must see delta>threshold, THEN
// delta<=threshold in order to trigger. To do this, we track the
// previous and current index pulse states.
	reg [1:0] prevstate;
	always @(posedge index) begin
		prevstate <= {prevstate[0], (tlatch <= threshold)};
	end

/////////////////////////////////////////////////////////////////////////////
// Detect logic -- prevdelta > threshold, thisdelta <= threshold.
	assign detect = (!prevstate[1] && prevstate[0]);

endmodule

// vim: ts=3 sw=3
