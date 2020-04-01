module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;

assign AUDIO_S   = 1'b0;
assign AUDIO_L   = audio;
assign AUDIO_R   = AUDIO_L;
assign AUDIO_MIX = 0;

assign LED_USER  = 0;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = status[8] ? 8'd16 : 4;
assign VIDEO_ARY = status[8] ? 8'd9  : 3;

assign VGA_F1 = 0;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CKE, SDRAM_CLK, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

`include "build_id.v"
parameter CONF_STR = {
	"FLAPPY;;",
	"O8,Aspect Ratio,4:3,16:9;",
	"-;",
	"R0,Reset;",
	"J1,Flap,Reset;",
	"jn,Flap,Reset;",
	"jp,Flap,Reset;",
	"V,v",`BUILD_DATE
};

wire reset = RESET | status[0] | buttons[1];


reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire  [7:0] filetype;
wire        ioctl_downloading;
reg         ioctl_download;
wire [24:0] ioctl_addr;
reg         ioctl_wait;

wire [24:0] ps2_mouse;
wire [15:0] joy_analog0, joy_analog1;
wire  [7:0] pdl[4];
wire        forced_scandoubler;

wire [21:0] gamma_bus;
wire [63:0] status;

wire [2:0] buttons;
wire [15:0] joyA;

hps_io #(.STRLEN(($size(CONF_STR)>>3))) hps_io
(
	.clk_sys(clk),
	.HPS_BUS(HPS_BUS),
	.conf_str(CONF_STR),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

	.joystick_0(joyA),

	.status(status),
	.status_menumask(),

	.gamma_bus(gamma_bus)
);


wire clock_locked;
wire clk;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk),
	.outclk_1(),
	.locked(clock_locked)
);

wire [15:0] audio = {1'b0, speaker, 14'd0};
wire speaker;

wire vsync, hsync, vblank, hblank, red, green, blue;

TopModule Flappy (
	.Clk(clk),
	.Button(~joyA[4]),
	.sys_reset(~(reset | joyA[5])),
	.vga_h_sync(hsync),
	.vga_v_sync(vsync),
	.vga_h_blank(hblank),
	.vga_v_blank(vblank),
	.vga_R(red),
	.vga_G(green),
	.vga_B(blue),
	.Speaker(speaker)
);

wire [2:0] scale = status[3:1];

assign VGA_F1 = 0;
assign CLK_VIDEO = clk;

video_mixer #(.LINE_LENGTH(640), .HALF_DEPTH(0), .GAMMA(1)) video_mixer
(
	.*,

	.clk_vid(clk),
	.ce_pix(1),
	.ce_pix_out(CE_PIXEL),

	.scanlines(0),
	.scandoubler(0),
	.hq2x(0),

	.mono(0),

	.R({1'b0, {15{red}}}),
	.G({1'b0, {15{green}}}),
	.B({1'b0, {15{blue}}}),

	// Positive pulses.
	.HSync(hsync),
	.VSync(vsync),
	.HBlank(hblank),
	.VBlank(vblank)
);


endmodule

