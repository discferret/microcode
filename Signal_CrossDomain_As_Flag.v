/*****
 * Synchronises a signal from the clkA clock domain to the clkB clock domain.
 * Signal may be active for one or more clkA clock cycles, but will only be active
 * for one clkB cycle on the rising edge.
 *
 * NOTE: May miss single pulses -- input should be active for at least one clock
 *       cycle.
 *****/
    
module Signal_CrossDomain_As_Flag(
    clkA, SignalIn, 
    clkB, SignalOut);

// clkA domain signals
input clkA;
input SignalIn;

// clkB domain signals
input clkB;
output SignalOut;

/*
/// This code is from fpga4fun.com and doesn't "quite" work right...

// Now let's transfer SignalIn into the clkB clock domain
// We use a two-stages shift-register to synchronize the signal
reg [1:0] SyncA_clkB;
always @(posedge clkB) SyncA_clkB[0] <= SignalIn;      // notice that we use clkB
always @(posedge clkB) SyncA_clkB[1] <= SyncA_clkB[0]; // notice that we use clkB

assign SignalOut = SyncA_clkB[1];  // new signal synchronized to (=ready to be used in) clkB domain
*/

reg [1:0] SrA;
reg outbuf;

always @(posedge clkA) SrA <= {SrA[0], SignalIn};
always @(posedge clkB) outbuf <= (SrA[0] && !SrA[1]);
assign SignalOut = outbuf;

endmodule
