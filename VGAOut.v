`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    04:44:19 04/23/2014
// Design Name:
// Module Name:    VGAOut
// Project Name:
// Target Devices:
// Tool versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module VGAOut(Clk, vga_h_sync, vga_v_sync, inDisplayArea, vblank, hblank, CounterX, CounterY);
input Clk;
output vga_h_sync, vga_v_sync;
output inDisplayArea;
output reg vblank;
output reg hblank;
output reg [15:0] CounterX;
output reg [15:0] CounterY;

//////////////////////////////////////////////////
wire CounterXmaxed = (CounterX==10'd799);

always @(posedge Clk) begin
	if(CounterXmaxed)
		CounterX <= 15'd0;
	else
		CounterX <= CounterX + 1;
end

always @(posedge Clk) begin
	if (CounterXmaxed) begin
		CounterY <= CounterY + 1;
		if (CounterY > 523)
			CounterY <= 15'd0;
	end
end

reg	vga_HS, vga_VS;
always @(posedge Clk)
begin
	vga_HS <= (CounterX >= 655) && (CounterX < 752); // change this value to move the display horizontally
	vga_VS <= (CounterY >= 490) && (CounterY < 492); // change this value to move the display vertically
end

//reg inDisplayArea;
always @(posedge Clk) begin
	vblank <= (CounterY > 478);
	hblank <= (CounterX > 639);

	// if(inDisplayArea==0) begin
	// 	inDisplayArea <= (CounterXmaxed) && (CounterY<480);
	// end else begin
	// 	inDisplayArea <= !(CounterX==639);
	// end
end

assign inDisplayArea = ~(vblank | hblank);

assign vga_h_sync = vga_HS;
assign vga_v_sync = vga_VS;

endmodule