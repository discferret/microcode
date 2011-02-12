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
// Time counter and latch
	reg [7:0] timer;
	reg [7:0] tlatch;
	always @(posedge clock or posedge index) begin
		if (index) begin
			tlatch <= timer;
			timer <= 8'b0;
		end else begin
			if (cke) begin
				timer <= timer + 8'd1;
			end
		end
	end

/////////////////////////////////////////////////////////////////////////////
// Track last few output states -- must see delta>threshold, THEN
// delta<=threshold twice in order to trigger. To do this, we track the
// previous and current index pulse states.
	reg [2:0] prevstate;
	always @(posedge index) begin
		prevstate <= {prevstate[1:0], (tlatch <= threshold)};
	end

/////////////////////////////////////////////////////////////////////////////
// Detect logic -- 
//   First delta:             longer than threshold
//   Second and third deltas: shorter than threshold
//
// In a sense, we're after:
//          _          _      _      _
//   ______/ \________/ \____/ \____/ \_____
// sector: n-1         n     n.5     1
//                                  ^^^ INDEX HERE
//
	assign detect = (!prevstate[2] && prevstate[1] && prevstate[0]);

endmodule

// vim: ts=3 sw=3
