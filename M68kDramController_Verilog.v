//////////////////////////////////////////////////////////////////////////////////////-
// Simple DRAM controller for the DE1 board, assuming a 50MHz controller/memory clock
// Assuming 64Mbytes SDRam organised as 32Meg x16 bits with 8192 rows (13 bit row addr
// 1024 columns (10 bit column address) and 4 banks (2 bit bank address)
// CAS latency is 2 clock periods
//
// designed to work with 68000 cpu using 16 bit data bus and 32 bit address bus
// separate upper and lower data stobes for individual byte and 16 bit word access
//
// Copyright PJ Davies June 2020
//////////////////////////////////////////////////////////////////////////////////////-


module M68kDramController_Verilog (
			input Clock,								// used to drive the state machine- stat changes occur on positive edge
			input Reset_L,     						// active low reset 
			input unsigned [31:0] Address,		// address bus from 68000
			input unsigned [15:0] DataIn,			// data bus in from 68000
			input UDS_L,								// active low signal driven by 68000 when 68000 transferring data over data bit 15-8
			input LDS_L, 								// active low signal driven by 68000 when 68000 transferring data over data bit 7-0
			input DramSelect_L,     				// active low signal indicating dram is being addressed by 68000
			input WE_L,  								// active low write signal, otherwise assumed to be read
			input AS_L,									// Address Strobe
			
			output reg unsigned[15:0] DataOut, 				// data bus out to 68000
			output reg SDram_CKE_H,								// active high clock enable for dram chip
			output reg SDram_CS_L,								// active low chip select for dram chip
			output reg SDram_RAS_L,								// active low RAS select for dram chip
			output reg SDram_CAS_L,								// active low CAS select for dram chip		
			output reg SDram_WE_L,								// active low Write enable for dram chip
			output reg unsigned [12:0] SDram_Addr,			// 13 bit address bus dram chip	
			output reg unsigned [1:0] SDram_BA,				// 2 bit bank address
			inout  reg unsigned [15:0] SDram_DQ,			// 16 bit bi-directional data lines to dram chip NEED FOR SYNTHESIS
			
			output reg Dtack_L,									// Dtack back to CPU at end of bus cycle
			output reg ResetOut_L,								// reset out to the CPU
	
			// Use only if you want to simulate dram controller state (e.g. for debugging)
			output reg [4:0] DramState
		); 	
		
		//reg unsigned [15:0] SDram_DQ; //remove when synthesising
		// WIRES and REGs
		
		reg  	[4:0] Command;										// 5 bit signal containing Dram_CKE_H, SDram_CS_L, SDram_RAS_L, SDram_CAS_L, SDram_WE_L

		reg	TimerLoad_H ;										// logic 1 to load Timer on next clock
		reg   TimerDone_H ;										// set to logic 1 when timer reaches 0
		reg 	unsigned	[15:0] Timer;							// 16 bit timer value
		reg 	unsigned	[15:0] TimerValue;					// 16 bit timer preload value

		reg	RefreshTimerLoad_H;								// logic 1 to load refresh timer on next clock
		reg   RefreshTimerDone_H ;								// set to 1 when refresh timer reaches 0
		reg 	unsigned	[15:0] RefreshTimer;					// 16 bit refresh timer value
		reg 	unsigned	[15:0] RefreshTimerValue;			// 16 bit refresh timer preload value

		reg   unsigned [4:0] CurrentState;					// holds the current state of the dram controller
		reg   unsigned [4:0] NextState;						// holds the next state of the dram controller
		reg   unsigned [4:0] ReturnState;						// holds the next state when returning from common loop ex 3 NOP

		reg		unsigned [3:0] RefreshCount;			//number of refresh operations to be performed
		
		reg  	unsigned [1:0] BankAddress;
		reg  	unsigned [12:0] DramAddress;
		
		reg	DramDataLatch_H;									// used to indicate that data from SDRAM should be latched and held for 68000 after the CAS latency period
		reg  	unsigned [15:0]SDramWriteData;
		
		reg  FPGAWritingtoSDram_H;								// When '1' enables FPGA data out lines leading to SDRAM to allow writing, otherwise they are set to Tri-State "Z"
		reg  CPU_Dtack_L;												// Dtack back to CPU
		reg  CPUReset_L;		

		// 5 bit Commands to the SDRam

		parameter PoweringUp = 5'b00000 ;					// take CKE & CS low during power up phase, address and bank address = dont'care
		parameter DeviceDeselect  = 5'b11111;				// address and bank address = dont'care
		parameter NOP = 5'b10111;								// address and bank address = dont'care
		parameter BurstStop = 5'b10110;						// address and bank address = dont'care
		parameter ReadOnly = 5'b10101; 						// A10 should be logic 0, BA0, BA1 should be set to a value, other addreses = value
		parameter ReadAutoPrecharge = 5'b10101; 			// A10 should be logic 1, BA0, BA1 should be set to a value, other addreses = value
		parameter WriteOnly = 5'b10100; 						// A10 should be logic 0, BA0, BA1 should be set to a value, other addreses = value
		parameter WriteAutoPrecharge = 5'b10100 ;			// A10 should be logic 1, BA0, BA1 should be set to a value, other addreses = value
		parameter AutoRefresh = 5'b10001;
	
		parameter BankActivate = 5'b10011;					// BA0, BA1 should be set to a value, address A11-0 should be value
		parameter PrechargeSelectBank = 5'b10010;			// A10 should be logic 0, BA0, BA1 should be set to a value, other addreses = don't care
		
		parameter PrechargeAllBanks = 5'b10010;			// A10 should be logic 1, BA0, BA1 are dont'care, other addreses = don't care
		parameter ModeRegisterSet = 5'b10000;				// A10=0, BA1=0, BA0=0, Address = don't care
		parameter ExtModeRegisterSet = 5'b10000;			// A10=0, BA1=1, BA0=0, Address = value
		parameter ModeRegisterData = 13'h0220;
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-
// Define some states for our dram controller add to these as required - only 5 will be defined at the moment - add your own as required
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-
	
		parameter InitialisingState = 5'd00;				// power on initialising state
		parameter WaitingForPowerUpState = 5'd01	;		// waiting for power up state to complete
		parameter IssueFirstNOP = 5'd02;						// issuing 1st NOP after power up
		parameter PrechargingAllBanks = 5'd03;			// precharge banks after power up
		parameter SecondNOP = 5'd04;								// issuing 2nd NOP after power up
		parameter Wait = 5'd05;											// Idle state
		parameter WaitStart = 5'd06;								// initializes refresh timer
		parameter RefreshLoop = 5'd07;
		parameter RefreshFirstNOP = 5'd08;
		parameter RefreshSecondNOP = 5'd09;
		parameter RefreshThirdNOP = 5'd10;
		parameter ProgramModeRegister = 5'd11;		// issues command to program mode register after power up
		parameter AutoRefreshPrecharge = 5'd12;
		parameter AutoRefreshNOP = 5'd13;
		parameter BeginRead = 5'd14;							// issues read command
		parameter BeginWrite = 5'd15;							// write; wait for 68k’s UDS or LDS or both to go low
		parameter WriteNOP = 5'd16;								// wait for one clock cycle after a write 
		parameter WaitCurrentBusCycle = 5'd17;			// waits for current cpu bus cycle to terminate
		parameter WaitCASLatency = 5'd18;
		
		// TODO - Add your own states as per your own design
		

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// General Timer for timing and counting things: Loadable and counts down on each clock then produced a TimerDone signal and stops counting
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	always@(posedge Clock)
		if(TimerLoad_H == 1) 				// if we get the signal from another process to load the timer
			Timer <= TimerValue ;			// Preload timer
		else if(Timer != 16'd0) 			// otherwise, provided timer has not already counted down to 0, on the next rising edge of the clock		
			Timer <= Timer - 16'd1 ;		// subtract 1 from the timer value

	always@(Timer) begin
		TimerDone_H <= 0 ;					// default is not done
	
		if(Timer == 16'd0) 					// if timer has counted down to 0
			TimerDone_H <= 1 ;				// output '1' to indicate time has elapsed
	end

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Refresh Timer: Loadable and counts down on each clock then produces a RefreshTimerDone signal and stops counting
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	always@(posedge Clock)
		if(RefreshTimerLoad_H == 1) 						// if we get the signal from another process to load the timer
			RefreshTimer  <= RefreshTimerValue ;		// Preload timer
		else if(RefreshTimer != 16'd0) 					// otherwise, provided timer has not already counted down to 0, on the next rising edge of the clock		
			RefreshTimer <= RefreshTimer - 16'd1 ;		// subtract 1 from the timer value

	always@(RefreshTimer) begin
		RefreshTimerDone_H <= 0 ;							// default is not done

		if(RefreshTimer == 16'd0) 								// if timer has counted down to 0
			RefreshTimerDone_H <= 1 ;						// output '1' to indicate time has elapsed
	end
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-
// concurrent process state registers
// this process RECORDS the current state of the system.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

   always@(posedge Clock, negedge Reset_L)
	begin
		if(Reset_L == 0) 	begin // asynchronous reset
			CurrentState <= InitialisingState;
			CPUReset_L <= 0;
		end						
				
		else 	begin									// state can change only on low-to-high transition of clock
			CurrentState <= NextState;
			DramState <= NextState ;					// output current state - useful for debugging so you can see you state machine changing states etc		
			
			if(CurrentState == WaitStart)
				CPUReset_L <= 1 ;
			else
				CPUReset_L <= CPUReset_L ;
			// these are the raw signals that come from the dram controller to the dram memory chip. 
			// This process expects the signals in the form of a 5 bit bus within the signal Command. The various Dram commands are defined above just beneath the architecture)

			SDram_CKE_H <= Command[4];			// produce the Dram clock enable
			SDram_CS_L  <= Command[3];			// produce the Dram Chip select
			SDram_RAS_L <= Command[2];			// produce the dram RAS
			SDram_CAS_L <= Command[1];			// produce the dram CAS
			SDram_WE_L  <= Command[0];			// produce the dram Write enable
			
			SDram_Addr  <= DramAddress;		// output the row/column address to the dram
			SDram_BA   	<= BankAddress;		// output the bank address to the dram

			// signals back to the 68000

			Dtack_L 		<= CPU_Dtack_L ;			// output the Dtack back to the 68000
			ResetOut_L 	<= CPUReset_L ;			// output the Reset out back to the 68000
			
			// The signal FPGAWritingtoSDram_H can be driven by you when you need to turn on or tri-state the data bus out signals to the dram chip data lines DQ0-15
			// when you are reading from the dram you have to ensure they are tristated (so the dram chip can drive them)
			// when you are writing, you have to drive them to the value of SDramWriteData so that you 'present' your data to the dram chips
			// of course during a write, the dram WE signal will need to be driven low and it will respond by tri-stating its outputs lines so you can drive data in to it
			// remember the Dram chip has bi-directional data lines, when you read from it, it turns them on, when you write to it, it turns them off (tri-states them)

			
			if(FPGAWritingtoSDram_H == 1) 			// if CPU is doing a write, we need to turn on the FPGA data out lines to the SDRam and present Dram with CPU data 
				SDram_DQ	<= SDramWriteData ;
			else
				SDram_DQ	<= 16'bZZZZZZZZZZZZZZZZ;			// otherwise tri-state the FPGA data output lines to the SDRAM for anything other than writing to it
				
		end
	end	
	
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-
// Concurrent process to Latch Data from Sdram after Cas Latency during read
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-

// this process will latch whatever data is coming out of the dram data lines on the FALLING edge of the clock you have to drive DramDataLatch_H to logic 1
// remember there is a programmable CAS latency for the Zentel dram chip on the DE1 board it's 2 or 3 clock cycles which has to be programmed by you during the initialisation
// phase of the dram controller following a reset/power on
//
// During a read, after you have presented CAS command to the dram chip you will have to wait 2 clock cyles and then latch the data out here and present it back
// to the 68000 until the end of the 68000 bus cycle
	
	always@(negedge Clock)
	begin
		if(DramDataLatch_H == 1)      			// asserted during the read operation
			DataOut <= SDram_DQ ;					// store 16 bits of data regardless of width - don't worry about tri state since that will be handled by buffers outside dram controller
	end
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////-
// next state and output logic
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////	
	
	always@(*)
	begin
	
	// In Verilog/VHDL - you will recall - that combinational logic (i.e. logic with no storage) is created as long as you
	// provide a specific value for a signal in each and every possible path through a process
	// 
	// You can do this of course, but it gets tedious to specify a value for each signal inside every process state and every if-else test within those states
	// so the common way to do this is to define default values for all your signals and then override them with new values as and when you need to.
	// By doing this here, right at the start of a process, we ensure the compiler does not infer any storage for the signal, i.e. it creates
	// pure combinational logic (which is what we want)
	//
	// Let's start with default values for every signal and override as necessary, 
	//
	
		Command 	<= NOP ;												// assume no operation command for Dram chip
		NextState <= InitialisingState ;							// assume next state will always be idle state unless overridden the value used here is not important, we cimple have to assign something to prevent storage on the signal so anything will do
		
		TimerValue <= 16'h0000;										// no timer value 
		RefreshTimerValue <= 16'd375 ;							// 7.5 us = 375 cycles
		TimerLoad_H <= 0;												// don't load Timer
		RefreshTimerLoad_H <= 0 ;									// don't load refresh timer
		DramAddress <= 13'h0000 ;									// no particular dram address
		BankAddress <= 2'b00 ;										// no particular dram bank address
		DramDataLatch_H <= 0;										// don't latch data yet
		CPU_Dtack_L <= 1 ;											// don't acknowledge back to 68000
		SDramWriteData <= 16'h0000 ;								// nothing to write in particular
		//CPUReset_L <= 0 ;												// default is reset to CPU (for the moment, though this will change when design is complete so that reset-out goes high at the end of the dram initialisation phase to allow CPU to resume)
		FPGAWritingtoSDram_H <= 0 ;								// default is to tri-state the FPGA data lines leading to bi-directional SDRam data lines, i.e. assume a read operation

		// put your current state/next state decision making logic here - here are a few states to get you started
		// during the initialising state, the drams have to power up and we cannot access them for a specified period of time (100 us)
		// we are going to load the timer above with a value equiv to 100us and then wait for timer to time out
	
		if (CurrentState == InitialisingState ) begin
			TimerValue <= 16'd5000;									// chose a value equivalent to 100us at 50Mhz clock - you might want to shorten it to somthing small for simulation purposes
			TimerLoad_H <= 1 ;										// on next edge of clock, timer will be loaded and start to time out
			Command <= PoweringUp ;									// clock enable and chip select to the Zentel Dram chip must be held low (disabled) during a power up phase
			NextState <= WaitingForPowerUpState ;				// once we have loaded the timer, go to a new state where we wait for the 100us to elapse
		end
		
		else if (CurrentState == WaitingForPowerUpState) begin
			Command <= PoweringUp ;									// no DRam clock enable or CS while witing for 100us timer
			
			if (TimerDone_H == 1) 									// if timer has timed out i.e. 100us have elapsed
				NextState <= IssueFirstNOP ;						// take CKE and CS to active and issue a 1st NOP command
			else
				NextState <= WaitingForPowerUpState ;			// otherwise stay here until power up time delay finished
		end
		
		else if (CurrentState == IssueFirstNOP) begin	 		// issue a valid NOP
			Command <= NOP ;											// send a valid NOP command to the dram chip
			NextState <= PrechargingAllBanks;
		end		
		
		else if (CurrentState == PrechargingAllBanks) begin
			Command <= PrechargeAllBanks;
			DramAddress <= 13'b0_0100_0000_0000;		//set A[10] = 1
			NextState <= SecondNOP;
		end

		else if (CurrentState == SecondNOP) begin
			Command <= NOP;
			ReturnState <= ProgramModeRegister;
			NextState <= RefreshLoop;
		end

		else if (CurrentState == RefreshLoop) begin
			Command <= AutoRefresh;
			NextState <= RefreshFirstNOP;
		end

		else if (CurrentState == RefreshFirstNOP) begin
			Command <= NOP;
			NextState <= RefreshSecondNOP;
		end 
		else if (CurrentState == RefreshSecondNOP) begin
			Command <= NOP;
			NextState <= RefreshThirdNOP;
		end 
		else if (CurrentState == RefreshThirdNOP) begin
			Command <= NOP;

			if(RefreshCount == 0)
				NextState <= ReturnState;
			else
				NextState <= RefreshLoop;			
		end 

		else if (CurrentState == ProgramModeRegister) begin
			Command <= ProgramModeRegister;
			DramAddress <= ModeRegisterData;
			ReturnState <= WaitStart;
			NextState <= RefreshFirstNOP;
		end

		else if (CurrentState == WaitStart) begin
			Command <= NOP;
			RefreshTimerLoad_H <= 1;
			NextState <= Wait;
		end
		
		else if (CurrentState == Wait) begin
			Command <= NOP;
			if (RefreshTimerDone_H == 1) 
				NextState <= AutoRefreshPrecharge;

			else if (DramSelect_L == 0 && AS_L == 0) begin
				DramAddress <= Address[23:11];
				BankAddress <= Address[25:24];
				Command <= BankActivate;

				if (WE_L == 1)
					NextState <= BeginRead;
				else
					NextState <= BeginWrite;
			end

			else
				NextState <= Wait;
		end

		else if (CurrentState == AutoRefreshPrecharge) begin
			Command <= PrechargeAllBanks;
			DramAddress <= 13'b0_0100_0000_0000;		//set A[10] = 1
			NextState <= AutoRefreshNOP;
		end

		else if (CurrentState == AutoRefreshNOP) begin
			Command <= NOP;
			ReturnState <= WaitStart;
			NextState <= RefreshLoop;
		end

	else if (CurrentState == BeginWrite) begin
		if (UDS_L == 0 || LDS_L == 0) begin
				Command <= WriteAutoPrecharge;
				
				DramAddress <= {1'b1, Address[10:1]};
				BankAddress <= Address[25:24];			
				CPU_Dtack_L <= 0;
				FPGAWritingtoSDram_H <= 1;				
				SDramWriteData <=	DataIn;

				NextState <= WriteNOP;
		end
		else
			NextState <= BeginWrite;
	end

	else if (CurrentState == WriteNOP) begin
		Command <= NOP;

		CPU_Dtack_L <= 0;
		FPGAWritingtoSDram_H <= 1;
		SDramWriteData <=	DataIn;

		NextState <= WaitCurrentBusCycle;
	end

	else if (CurrentState == BeginRead) begin
		Command <= ReadAutoPrecharge;

		DramAddress <= {1'b1, Address[10:1]};
		BankAddress <= Address[25:24];
		CPU_Dtack_L <= 0;
		TimerValue <= 16'h0002;	
		TimerLoad_H <= 1;	

		NextState <= WaitCASLatency;
	end

	else if (CurrentState == WaitCASLatency) begin
		Command <= NOP;

		CPU_Dtack_L <= 0;
		DramDataLatch_H <= 1;

		if (TimerDone_H == 1) 								
			NextState <= WaitCurrentBusCycle;				
		else
			NextState <= WaitCASLatency;

	end

	else if (CurrentState == WaitCurrentBusCycle) begin
		Command <= NOP;
		if (UDS_L == 0 || LDS_L == 0) begin
			CPU_Dtack_L <= 0;
			NextState <= WaitCurrentBusCycle;
		end
		else
			NextState <= WaitStart;
	end

	else begin
		Command <= NOP;
		NextState <= Wait;
	end

	end	// always@ block

	//refresh counter
	always @(posedge Clock) begin
		if (CurrentState == RefreshLoop)
			RefreshCount <= RefreshCount - 1;
		else if (CurrentState == AutoRefreshNOP)
			RefreshCount <= 1;
		else if (CurrentState == SecondNOP)
			RefreshCount <= 10;
		else
			RefreshCount <= RefreshCount;		
	end
endmodule
