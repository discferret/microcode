/*****
 * Source: fpga4fun.com
 *
 * Synchronises a pulse (flag) from clock domain clkA to the clkB clock domain.
 *
 * NOTE: Will misbehave if the input flag is active for more than one clock cycle.
 * Symptom = output appears to toggle...
 *****/

module Flag_CrossDomain(
    clkA, FlagIn_clkA, 
    clkB, FlagOut_clkB);

// clkA domain signals
input clkA, FlagIn_clkA;

// clkB domain signals
input clkB;
output FlagOut_clkB;

reg FlagToggle_clkA;
reg [2:0] SyncA_clkB;

// this changes level when a flag is seen
always @(posedge clkA) if(FlagIn_clkA) FlagToggle_clkA <= ~FlagToggle_clkA;

// which can then be synched to clkB
always @(posedge clkB) SyncA_clkB <= {SyncA_clkB[1:0], FlagToggle_clkA};

// and recreate the flag from the level change
assign FlagOut_clkB = (SyncA_clkB[2] ^ SyncA_clkB[1]);

endmodule
