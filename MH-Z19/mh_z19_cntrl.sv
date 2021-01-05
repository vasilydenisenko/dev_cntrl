/*
	MH-Z19 CO2 concentration sensor controller with Avalon MM
	interface.
	
	Modules uart_transmitter and uart_receiver are taken from
	https://github.com/roman-pogorelov/verlib/tree/master/ifaces/usart
	
	********************************************************************
	Writedata:
		wrd[7 : 0] 		- UART byte 2 (Command);
		wrd[15 : 8] 	- UART byte 3;
		wrd[23 : 16] 	- UART byte 4;
		wrd[31 : 24] 	- UART byte 8 (Checksum).
	
	Readdata:
		addr == 0:
		rdd[7 : 0] 		- Command;
		rdd[15 : 8] 	- Concentration (high byte);
		rdd[23 : 16] 	- Concentration (low byte);
		rdd[31 : 24] 	- Byte4;
		
		addr == 1:
		rdd[7 : 0] 		- Byte5;
		rdd[15 : 8] 	- Byte6;
		rdd[23 : 16] 	- Byte7;
		rdd[31 : 24] 	- Checksum;
*/

module mh_z19_cntrl
#(
	parameter BAUDDIVISOR = 31
)	
(
	input  logic 			clk,
	input  logic 			rst,
	
	input  logic 			rxd,
	output logic 			txd,
	
	input  logic 			addr,
	input  logic 			wr,
	input  logic [31 : 0] 	wrd,
	output logic [31 : 0] 	rdd,
	output logic 			wrq
);


// State Register
	localparam SR_WIDTH = 3;	
	enum logic [SR_WIDTH - 1 : 0] {
		IDLE 		= 3'd0,
		TXD 		= 3'd1, 
		SEL_BYTE 	= 3'd2, 
		RXE 		= 3'd3, 	
		RXD 		= 3'd4,
		RXD_VALID 	= 3'd5,
		TIMEOUT 	= 3'd6,
		DONE 		= 3'd7			 
	} cstate, nstate;
	
	
	dff_ar
	#(
		.DWIDTH 	(SR_WIDTH),
		.POR_VALUE 	(IDLE)
	)
		state_reg_inst
	(
		.clk		(clk),
		.rst		(rst),		
		.in			(nstate),	// i[DWIDTH - 1 : 0]
		.ena		(1'b1),	// i
		.out		(cstate)	// o[DWIDTH - 1 : 0]
	);
//! State Register



// Next State Logic
	always_comb begin
		case (cstate)
			IDLE:		nstate = wr ? TXD : IDLE;
			TXD:		nstate = tx_ready ? 
									((current_byte == 4'd8) ?
										(rx_request ?
											RXE :
											DONE) :
										SEL_BYTE) :
									TXD;
			SEL_BYTE:	nstate = TXD;
			RXE:		nstate = RXD;
			RXD:		nstate = rx_valid ? 
									((current_byte == 4'd8) ?
										RXD_VALID :
										RXD) :
									(timeout ?
										TIMEOUT :
										RXD);
			RXD_VALID:	nstate = DONE;
			TIMEOUT:	nstate = DONE;
			DONE:		nstate = IDLE;					
			default:	nstate = IDLE;
		endcase
	end
//! Next State Logic



//
	logic [7 : 0] tx_data;	
	always_comb begin
		case (current_byte)
			4'd0:		tx_data = 8'hFF;
			4'd1:		tx_data = 8'h01; 
			4'd2:		tx_data = wrd[7 : 0]; 
			4'd3:		tx_data = wrd[15 : 8]; 
			4'd4:		tx_data = wrd[23 : 16]; 
			4'd5:		tx_data = 8'h00; 
			4'd6:		tx_data = 8'h00; 
			4'd7:		tx_data = 8'h00; 
			4'd8:		tx_data = wrd[31 : 24]; 
			default:	tx_data = 8'h00; 
		endcase
	end
//!



//
	logic tx_valid;
	assign tx_valid = (cstate == TXD);
//!	



//
	logic [3 : 0] current_byte;	
	counter_up_dw_ld
	#(
		.DWIDTH 		(4),
		.DEFAULT_COUNT	(0)
	)
		byte_selector_inst
	(
		.clk			(clk),
		.rst			(rst),
		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	((cstate == RXE) || (cstate == DONE)),	// i
		.cntrl__ena		((cstate == SEL_BYTE) || rx_valid),	// i
		.cntrl__data_in	(4'd0),	// i[DWIDTH - 1 : 0]
		
		.count			(current_byte)	// o[DWIDTH - 1 : 0]
	);
//!	



//
	logic [6 : 0] rx_time;	
	counter_up_dw_ld
	#(
		.DWIDTH 		(7),
		.DEFAULT_COUNT	(0)
	)
		rx_time_counter_inst
	(
		.clk			(clk),
		.rst			(rst),
		
		.cntrl__up_dwn	(1'b1),	// i
		.cntrl__load	(cstate == DONE),	// i
		.cntrl__ena		(cstate == RXD),	// i
		.cntrl__data_in	(7'd0),	// i[DWIDTH - 1 : 0]
		
		.count			(rx_time)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic timeout;
	assign timeout = (rx_time == '1);
//!




//
	logic rx_request;
	assign rx_request = (wrd[7 : 0] == 8'h86);
//!
	
	
	
//	
	logic rx_init;
	assign rx_init = (cstate == RXE);
//!	





// 
	always_comb begin
		case (cstate)
			IDLE: 		wrq = wr;
			TXD: 		wrq = 1'b1;
			SEL_BYTE: 	wrq = 1'b1;
			RXE: 		wrq = 1'b1; 	
			RXD: 		wrq = 1'b1;
			RXD_VALID: 	wrq = 1'b1;
			TIMEOUT: 	wrq = 1'b1;
			DONE: 		wrq = 1'b0;
			default:	wrq = 1'b0;
		endcase
	end
//!





// 	
	logic [7 : 0] cmd_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		cmd_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd1)),	// i
		.out		(cmd_reg)	// o[DWIDTH - 1 : 0]
	);
	
	

	logic [7 : 0] concentration_high_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		concetration_high_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd2)),	// i
		.out		(concentration_high_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] concentration_low_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		concetration_low_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd3)),	// i
		.out		(concentration_low_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] byte4_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		byte4_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd4)),	// i
		.out		(byte4_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] byte5_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		byte5_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd5)),	// i
		.out		(byte5_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] byte6_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		byte6_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd6)),	// i
		.out		(byte6_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] byte7_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		byte7_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd7)),	// i
		.out		(byte7_reg)	// o[DWIDTH - 1 : 0]
	);
	
	
	
	logic [7 : 0] checksum_reg;	
	dff_ar
	#(
		.DWIDTH 	(8),
		.POR_VALUE 	(0)
	)
		checksum_reg_inst
	(
		.clk		(clk),
		.rst		(rst),
		
		.in			(rx_data),	// i[DWIDTH - 1 : 0]
		.ena		(rx_valid && (current_byte == 4'd8)),	// i
		.out		(checksum_reg)	// o[DWIDTH - 1 : 0]
	);
	

	assign rdd = addr ? 
					{	checksum_reg,
						byte7_reg, 
						byte6_reg,
						byte5_reg} :
					{	byte4_reg,
						concentration_low_reg,
						concentration_high_reg, 
						cmd_reg};
//!

	
	
// UART Transmitter	
	logic tx_ready;	
	uart_transmitter
    #(
        .BDWIDTH            ($clog2(BAUDDIVISOR + 1))  // Разрядность делителя
    )
		transmitter_inst
    (
        // Сброс и тактирование
        .reset              (rst), // i
        .clk                (clk), // i
        
        // Интерфейс управления
        .ctrl_init          (1'b0), // i                    Инициализация (синхронный сброс)
        .ctrl_baud_divisor  (BAUDDIVISOR), // i  [BDWIDTH - 1 : 0] Значение делителя
        .ctrl_stop_bits     (1'b0), // i                    Количество стоп-бит: 0 - один бит, 1 - два бита
        .ctrl_parity_ena    (1'b0), // i                    Признак использования контроля паритета чет/нечет
        .ctrl_parity_type   (1'b0), // i                    Типа контроля паритета: 0 - чет, 1 - нечет
        
        // Входной потоковый интерфейс
        .tx_data            (tx_data), // i  [7 : 0]
        .tx_valid           (tx_valid), // i
        .tx_ready           (tx_ready), // o
        
        // Линия передачи UART
        .uart_txd           (txd)  // o
    );
//! UART Transmitter	
	
	


// UART Receiver	
	logic [7 : 0] rx_data;
	logic rx_valid;
	
	uart_receiver
    #(
        .BDWIDTH            ($clog2(BAUDDIVISOR + 1))  // Разрядность делителя
    )
		uart_receiver_inst
    (
        // Сброс и тактирование
        .reset              (rst), // i
        .clk                (clk), // i
        
        // Интерфейс управления
        .ctrl_init          (rx_init), // i                    Инициализация (синхронный сброс)
        .ctrl_baud_divisor  (BAUDDIVISOR), // i  [BDWIDTH - 1 : 0] Значение делителя
        .ctrl_stop_bits     (1'b0), // i                    Количество стоп-бит: 0 - один бит, 1 - два бита
        .ctrl_parity_ena    (1'b0), // i                    Признак использования контроля паритета чет/нечет
        .ctrl_parity_type   (1'b0), // i                    Типа контроля паритета: 0 - чет, 1 - нечет
        
        // Интерфейс статусных сигналов
        .stat_err_parity    ( ), // o                    Признак ошибки паритета чет/нечет
        .stat_err_start     ( ), // o                    Признак ошибки приема старт-бита
        .stat_err_stop      ( ), // o                    Признак ошибки приема стоп-бита
        
        // Выходной потоковый интерфейс без возможности остановки
        .rx_data            (rx_data), // o  [7 : 0]
        .rx_valid           (rx_valid), // o
        
        // Линия приема UART
        .uart_rxd           (rxd)  // i
    );
//! UART Receiver	
	
	
endmodule