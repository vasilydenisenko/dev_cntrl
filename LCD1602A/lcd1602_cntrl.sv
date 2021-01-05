/* 
	LCD 1602A Controller with Avalon MM interface
	
	DIVIDER should be (N-1),
	where N = ceil ( 450 ns / clk period )
	
	********************************************************************
	lcd1602_cntrl
	#(
		.DIVIDER 	(50),
		.CYCLE_TIME	(1)
	)
		lcd1602_cntrl_inst
	(
		.clk		(),
		.rst		(),	
			
		.wr			(),	// i
		.wrd		(),	// i[4 : 0]
		.rd			(),	// i
		.rdd		(),	// o[4 : 0]
		.wrq		(),	// o
			
		.rs			(),	// o
		.rw			(),	// o
		.e			(),	// o
		.db4		(),	// io	
		.db5		(),	// io	
		.db6		(),	// io	
		.db7		()	// io	
	);
*/

module lcd1602_cntrl
#(
	parameter DIVIDER = 13,
	parameter CYCLE_TIME = 100000
)
(
	input  logic  			clk,
	input  logic  			rst,	
	
	input  logic  			wr,
	input  logic [4 : 0]  	wrd,
	input  logic  			rd,
	output logic [4 : 0]  	rdd,
	output logic			wrq,
	
	output logic  			rs,
	output logic  			rw,
	output logic  			e,
	inout  wire 		 	db4,	
	inout  wire 		 	db5,	
	inout  wire 		 	db6,	
	inout  wire 		 	db7	
);


	logic [5 : 0] code;
	dff_ar
	#(
		.DWIDTH 	(6),
		.POR_VALUE 	(0)
	)
		code_reg_inst
	(
		.clk		(clk),
		.rst		(rst),		
		.in			({rd, wrd}),	// i[DWIDTH - 1 : 0]
		.ena		((wr || rd) && idle_st),	// i
		.out		(code)	// o[DWIDTH - 1 : 0]
	);
	
	
	assign rw = code[5];
	assign rs = code[4];
	assign db7 = (rw == 0) ? code[3] : 1'bz;
	assign db6 = (rw == 0) ? code[2] : 1'bz;
	assign db5 = (rw == 0) ? code[1] : 1'bz;
	assign db4 = (rw == 0) ? code[0] : 1'bz;
	

	dff_ar
	#(
		.DWIDTH 	(4),
		.POR_VALUE 	(0)
	)
		rdd_reg_inst
	(
		.clk		(clk),
		.rst		(rst),		
		.in			({db7, db6, db5, db4}),	// i[DWIDTH - 1 : 0]
		.ena		(rw && e_st && e_over),	// i
		.out		(rdd)	// o[DWIDTH - 1 : 0]
	);

	
	logic idle_st;
	logic e_st;
	logic cycle_st;
	logic final_st;
	fsm_oe4s_sequencer
		control_fsm_inst
	(
		.clk	(clk),
		.rst	(rst),
		
		.t01	(wr || rd),	// i
		.t12	(e_over),	// i
		.t23	(cycle_over),	// i
		.t30	(1'b1),	// i
		
		.st0	(idle_st),	// o
		.st1	(e_st),	// o
		.st2	(cycle_st),	// o
		.st3	(final_st)	// o
	);
	
	
	
	
	localparam E_CNT_WIDTH = $clog2(DIVIDER + 1);
	logic [E_CNT_WIDTH - 1 : 0] e_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(E_CNT_WIDTH),
		.DEFAULT_COUNT	(0)
	)
		e_counter_inst
	(
		.clk			(clk),
		.rst			(rst),		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(idle_st || e_over),	// i
		.cntrl__ena		(e_st || cycle_st),	// i
		.cntrl__data_in	('0),	// i[DWIDTH - 1 : 0]		
		.count			(e_count)	// o[DWIDTH - 1 : 0]
	);
	
	
	assign e = e_st;
	
	
	logic e_over;
	assign e_over = (e_count == DIVIDER);
	
	
	localparam CWIDTH = $clog2(CYCLE_TIME + 1);
	logic [CWIDTH - 1 : 0] cycle_count;
	counter_up_dw_ld
	#(
		.DWIDTH 		(CWIDTH),
		.DEFAULT_COUNT	(0)
	)
		cycle_counter_inst
	(
		.clk			(clk),
		.rst			(rst),		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(idle_st),	// i
		.cntrl__ena		(e_over),	// i
		.cntrl__data_in	('0),	// i[DWIDTH - 1 : 0]		
		.count			(cycle_count)	// o[DWIDTH - 1 : 0]
	);
	
	
	logic cycle_over;
	assign cycle_over = cycle_count == CYCLE_TIME;
	

	always_comb begin
		if (wr) 
			wrq = !idle_st;
		else
			wrq = (final_st && rw) ? 1'b0 : rd;			
	end
	
endmodule