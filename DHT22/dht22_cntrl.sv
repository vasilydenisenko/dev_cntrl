/*
	DHT22 (also named as AM2302) relative humidity and temperature sensor
	controller.
	
	********************************************************************
	
	dht22_cntrl
	#(
		.DIVIDER		(),
		.INIT_TIME		(),
		.REQUEST_TIME	()		
	)
		dht22_cntrl_inst
	(
		.clk			(),
		.rst			(),
		
		.start			(), // i
		
		.humidity		(), // o[15 : 0]
		.temperature	(), // o[15 : 0]
		.checksum		(), // o[7 : 0]
		.valid			(), // o
		
		.data			() // io
	);
*/

module dht22_cntrl
#(
	parameter DIVIDER = 1000,
	parameter INIT_TIME = 200_000,
	parameter REQUEST_TIME = 200	
)
(
	input  logic clk,
	input  logic rst,
	
	input  logic start,
	
	output logic [15 : 0] humidity,
	output logic [15 : 0] temperature,
	output logic [7 : 0] checksum,
	output logic valid,
	
	inout  wire  data
);


	logic data_r;
	synchronizer_up_dn
	#(
		.UnD 		(1)	
	)
		synchronizer_up_dn_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.async_in	(data),
		.sync_out	(data_r)
	);
	
	
	
	logic data_rise;
	logic data_fall;
	edge_detector
		edge_detector_inst
	(
		.clk	(clk),
		.rst	(rst),
		
		.in		(data_r), // i
		.rise	(data_rise), // o
		.fall	(data_fall) // o
	);
	
	
	
//	
	localparam T_UNIT_CNT_WIDTH = $clog2(DIVIDER + 1);
	logic [T_UNIT_CNT_WIDTH - 1 : 0] t_unit_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(T_UNIT_CNT_WIDTH),
		.DEFAULT_COUNT	(0)
	)
		t_unit_count_inst
	(
		.clk			(clk),
		.rst			(rst),		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(t_unit_over),	// i
		.cntrl__ena		(1'b1),	// i
		.cntrl__data_in	('0),	// i[DWIDTH - 1 : 0]		
		.count			(t_unit_count)	// o[DWIDTH - 1 : 0]
	);
	
	
	logic t_unit_over;
	assign t_unit_over = (t_unit_count == DIVIDER);
//!




//
	localparam INIT_RQST_TIME = INIT_TIME + REQUEST_TIME;
	localparam INIT_RQST_WIDTH = $clog2(INIT_RQST_TIME + 1);
	logic [INIT_RQST_WIDTH - 1 : 0] init_rqst_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(INIT_RQST_WIDTH),
		.DEFAULT_COUNT	(0)
	)
		init_rqst_count_count_inst
	(
		.clk			(clk),
		.rst			(rst),
		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(idle_st),	// i
		.cntrl__ena		((init_st || request_st) && t_unit_over),	// i
		.cntrl__data_in	('0),	// i[DWIDTH - 1 : 0]
		
		.count			(init_rqst_count)	// o[DWIDTH - 1 : 0]
	);
	
	
	logic init_timeout;
	assign init_timeout = init_rqst_count > INIT_TIME;
	
	
	logic request_timeout;
	assign request_timeout = init_rqst_count > INIT_RQST_TIME;
//!



//
	logic idle_st;
	logic init_st;
	logic request_st;
	logic wait_low_st;
	logic wait_high_st;
	logic start_st;
	logic read_st;
	logic end_st;
	fsm_oe8s_sequencer
		main_sequencer_inst
	(
		.clk	(clk),
		.rst	(rst),
		
		.t01	(start),	// i
		.t12	(init_timeout),	// i
		.t23	(request_timeout),	// i
		.t34	(data_fall),	// i
		.t45	(data_rise),	// i
		.t56	(1'b1),	// i
		.t67	(ready_st),	// i
		.t70	(data_r),	// i
		
		.st0	(idle_st),	// o
		.st1	(init_st),	// o
		.st2	(request_st),	// o
		.st3	(wait_low_st),	// o
		.st4	(wait_high_st),	// o
		.st5	(start_st),	// o
		.st6	(read_st),	// o
		.st7	(end_st)	// o
	);
//!



//
	localparam REPLY_BIT_COUNT = 40;
	logic ready_st;
	logic wait_prebyte_st;
	logic wait_byte_st;
	logic count_st;
	fsm_oe4s_universal
		read_fsm_inst
	(
		.clk	(clk),
		.rst	(rst),
		
		.t0x	(start_st ? 2'd1 : 2'd0),	// i[1 : 0]
		.t1x	(data_r ? 2'd1 : 2'd2),	// i[1 : 0]
		.t2x	(data_r ? 2'd3 : 2'd2),	// i[1 : 0]
		.t3x	(data_r ?
					 2'd3 : 
					 (bit_count < REPLY_BIT_COUNT) ? 2'd2 : 2'd0),	// i[1 : 0]
		
		.st0	(ready_st),	// o
		.st1	(wait_prebyte_st),	// o
		.st2	(wait_byte_st),	// o
		.st3	(count_st)	// o
	);
	
	
	logic bit_over;
	assign bit_over = count_st && !data_r;
//!	
	


//	
	logic [5 : 0] bit_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(6),
		.DEFAULT_COUNT	(0)
	)
		byte_count_inst
	(
		.clk			(clk),
		.rst			(rst),
		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(ready_st),	// i
		.cntrl__ena		(wait_byte_st && data_r),	// i
		.cntrl__data_in	(6'd0),	// i[DWIDTH - 1 : 0]
		
		.count			(bit_count)	// o[DWIDTH - 1 : 0]
	);
//!	
	



//	
	logic [3 : 0] bit_len_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(4),
		.DEFAULT_COUNT	(0)
	)
		bit_count_inst
	(
		.clk			(clk),
		.rst			(rst),
		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(wait_byte_st),	// i
		.cntrl__ena		(count_st && t_unit_over),	// i
		.cntrl__data_in	(4'd0),	// i[DWIDTH - 1 : 0]
		
		.count			(bit_len_count)	// o[DWIDTH - 1 : 0]
	);
	
	
	localparam BIT_LEN_COUNT_THRESHOLD = 5;
	logic rx_bit;
	assign rx_bit = bit_len_count > BIT_LEN_COUNT_THRESHOLD;
//!	
	
	
	
//	
	logic [REPLY_BIT_COUNT - 1 : 0] bitbuf;
	always_ff @ (posedge clk or posedge rst) begin
		if (rst)
			bitbuf <= 0;
		else if (bit_over)
			bitbuf <= {bitbuf[REPLY_BIT_COUNT - 2 : 0], rx_bit};
		else
			bitbuf <= bitbuf;
	end


	assign humidity = bitbuf[REPLY_BIT_COUNT - 1 : 24];
	assign temperature = bitbuf[23 : 8];
	assign checksum = bitbuf[7 : 0];
	assign valid = read_st && ready_st;
	assign data = request_st ? 1'b0 : 1'bz;
//!	
	

endmodule
