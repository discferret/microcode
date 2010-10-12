/**
 * Synchronises a flag against clk, delays it by one clock cycle and ensures
 * that it does not remain active for more than one clock cycle.
 */
module Flag_Delay1tcy_OneCycle(clk, in, out);
	input		clk, in;
	output	out;

	reg[1:0] in_Delayed;
	always @(posedge clk) in_Delayed <= {in_Delayed[0], in};
	assign out = (in_Delayed[0] && !in_Delayed[1]);
endmodule

// vim: ts=3 sw=3
