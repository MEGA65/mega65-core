/* ****************************************************************************
-- (C) Copyright 2018 Kevin M. Hubbard - All rights reserved.
-- Source file: hyper_xface.v           
-- Date:        April 2018
-- Author:      khubbard
-- Language:    Verilog-2001 
-- Simulation:  Mentor-Modelsim 
-- Synthesis:   Xilinst-XST 

-- Changes for MEGA65 by Paul Gardner-Stephen.
-- (C) Copyright Flinders University. 
 
-- License:     This project is licensed with the CERN Open Hardware Licence
--              v1.2.  You may redistribute and modify this project under the
--              terms of the CERN OHL v.1.2. (http://ohwr.org/cernohl).
--              This project is distributed WITHOUT ANY EXPRESS OR IMPLIED
--              WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY
--              AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN OHL
--              v.1.2 for applicable Conditions.
-- Description: S27KL0641DABHI020 : Cypress IC DRAM 64MBIT 3V 100MHZ 24BGA
--              This is a dword interface module to HyperRAM for writing
--              and reading DWORDs. It is optimized for RTL portability and
--              simplicity rather than absolute bandwidth. The DRAM clock is
--              Div-4 of the core FPGA fabric clock in order to achieve reqd
--              90o phase clock and data relationship per HyperRAM spec w/o 
--              using an FPGA PLL. Latency is also max 2cyc ( about 12 RAM 
--              clocks ) as to not require programming different values to the
--              control register defaults ( 2x latency with 166 MHz ).
--              Power On Reset : Part requires 150uS after Power On or Reset
--
-- Write Cycle:
--  clk        /\/\/\
--  wr_req     / \__
--  addr       < >--
--  wr_d       < >--
--  wr_byte_en <F>--
--  busy       __/                                                        \_
--                 1       2       3      ...   .     14      15      16
--  dram_ck    __/   \___/   \___/   \___/   \_  \___/   \___/   \___/   \__
--  dram_cs_l  \___________________________________________________________/
--  dram_dq    <A1><A2><A3><A4><A5><A6>--------------------<11><22><33><44>-
--
-- Read  Cycle:
--  clk        /\/\/\
--  rd_req     / \___
--  addr       < >---
--  num_dwrds  < >---
--  busy       __/                                                          \_
--  rd_d       -----------------------------------------------------------<>-
--  rd_rdy     ___________________________________________________________/\_
--                 1       2       3      ...        14      15      16
--  dram_ck    __/   \___/   \___/   \___/   \_  ___/   \___/   \___/   \__
--  dram_cs_l  \____________________________________________________________/
--  dram_dq    <A1><A2><A3><A4><A5><A6>---------------------<11><22><33><44>-
--  dram_rwds  _/                     \_____________________/   \___/   \____
--
-- Write Bursts:
--  Writes may be bursted in groups of 32bits by asserting wr_req with new data
--  every 8 clock cycles once burst_wr_rdy has asserted. Note Addr is ignored
--  wr_req       / \___________________/ \__________/ \______________________
--  addr         <A>---------------------------------------------------------
--  wr_d         <B>-------------------<C>----------<D>----------------------
--  wr_byte_en   <F>-------------------<F>----------<F>----------------------
--                                  |--| 5 clocks max
--  burst_wr_rdy _________________/ \_________/ \_________/ \_______________
--  dram_cs_l     \______________________________________________________/
--  dram_dq      --<A><A><A><A><A><A><B><B><B><B><C><C><C><C><D><D><D><D>---
--
-- Core Interface Description:
--  clk           : in  : FPGA clock. Actual DRAM clock will be this Div-4.
--  rd_req        : in  : When core not busy, assert 1ck to make read request.
--  wr_req        : in  : When core not busy, assert 1ck to make write request.
--  mem_or_req    : in  : 0=DRAM Memory. 1=Configuration Register 
--  wr_byte_en    : in  : 0xF=Write all 4 bytes. 0xE write Bytes 3-1 but not 0.
--  rd_num_dwords : in  : Number of dwords to read, example 0x01.
--  addr          : in  : 32bit byte (not dword) address for 64Mbit DRAM cell.
--  wr_d          : in  : 32bit Write Data to DRAM.
--  rd_d          : out : 32bit Read Data from DRAM.
--  rd_rdy        : out : Read Ready Strobe. Asserts 1ck when rd_d is valid.
--  busy          : out : Busy Strobe asserts when Read or Write cycle is busy.
--  burst_wr_rdy  : out : Asserts when ready to accept next wr_req for burst.
--
--
-- Example Setup: HyperRAM requires that both the DRAM and the Controller 
--   agree to a fixed latency. The FPGA controller is configured via the
--   latency_1x and latency_2x input ports. The DRAM is configured via a 
--   write to configuration register 0. The default setting is really slow 
--   but has the advantage of not requiring a special configuration cycle
--   at the beginning of time. The difference is about 2x, for example 8 vs
--   16 DRAM clocks for a single DWORD xfer. Default always uses 2x latency,
--   ignoring the rwds completely.
--   Default 6 Clock 166 MHz Latency, latency1x=0x12, latency2x=0x16
--     CfgReg0 write(0x00000800, 0x8f1f0000);
--   Configd 3 Clock  83 MHz Latency, latency1x=0x04, latency2x=0x0a
--     CfgReg0 write(0x00000800, 0x8fe40000);
-- ***************************************************************************/

// Disable the below since it messes up compiling other Verilog sources
// on the MEGA65
// 'default_nettype none // Strictly enforce all nets to be declared
  
module hyper_xface 
(
  input  wire         reset,
  input  wire         clk,
  input  wire         rd_req,
  input  wire         wr_req,
  input  wire         mem_or_reg,
  input  wire [3:0]   wr_byte_en,
  input  wire [5:0]   rd_num_dwords,
  input  wire [31:0]  addr,
  input  wire [31:0]  wr_d,
  output reg  [31:0]  rd_d,
  output reg          rd_rdy,
  output reg          busy,
  output reg          burst_wr_rdy,
  input  wire [7:0]   latency_1x,
  input  wire [7:0]   latency_2x,

  input  wire [7:0]   dram_dq_in,
  output reg  [7:0]   dram_dq_out,
  output reg          dram_dq_oe_l,

  input  wire         dram_rwds_in,
  output reg          dram_rwds_out,
  output reg          dram_rwds_oe_l,

  output reg          dram_ck,
  output wire         dram_rst_l,
  output wire         dram_cs_l,
  output wire [7:0]   sump_dbg
);// module hyper_xface 


  reg  [47:0]  addr_sr;
  reg  [31:0]  data_sr;
  reg  [31:0]  rd_sr;
  reg  [1:0]   ck_phs;
  reg  [2:0]   fsm_addr;
  reg  [3:0]   fsm_data;
  reg  [5:0]   fsm_wait;
  reg          run_rd_jk;
  reg          run_jk;
  reg  [3:0]   run_jk_sr;
  reg          go_bit;
  reg          rw_bit;
  reg          reg_bit;
  reg          rwds_in_loc;
  reg          rwds_in_loc_p1;
  reg          byte_wr_en;
  reg  [7:0]   sr_data;
  reg  [3:0]   sr_byte_en;
  reg  [7:0]   dram_rd_d;
  reg          addr_shift;
  reg          data_shift;
  reg          wait_shift;
  reg          cs_loc;
  reg          cs_l_reg;
  reg          dram_ck_loc;
  reg          rd_done;
  reg  [3:0]   rd_cnt;
  reg  [2:0]   rd_fsm;
  reg  [5:0]   rd_dwords_cnt;
  reg          sample_now;
  reg          burst_wr_jk;
  reg          burst_wr_jk_clr;
  reg  [4:0]   burst_wr_sr;
  reg  [35:0]  burst_wr_d;


  assign dram_rst_l = ~ reset;

// Notes gleaned from datasheet:
// The clock is not required to be free-running. 
//
// Note: RWDS and DQ are edge aligned
// During write transactions, data is center aligned with clock transitions.
//
// During write data transfers, RWDS is 1 to mask a data byte write.
//
// During read data transfers, RWDS is a read data strobe with data values 
// edge aligned with the transitions of RWDS.
//
// The HyperRAM device may stop RWDS transitions with RWDS LOW, between the
// delivery of words, in order to insert latency between words when crossing 
// memory array boundaries.
//
//
// Read 1x Latency
//                          |---------  1x Latency ---------|
// CS_L   \__________________________________________________________________/
// CK     ____/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \_
// RWDS   \____________________________________________________/   \___/   \___
//  dir     < input        
// DQ[7:0] -<47><39><31><23><15><7 >---------------------------<  ><  ><  ><  >
//  dir     <       output         >---------------------------<   input      >
//
// Read 2x Latency
//                   |---1x Latency--|---2x Latency--|            
// CS_L    \__________________________________________________________________/
// CK      ____/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \
// RWDS                  \______________________________/\__/\___
// DQ[7:0] ---<><><><><><>------------------------------<><><><>-----------
//  dir      < output    >------------------------------<input >-----------
//
// Mem Write 1x Latency
//                   |---1x Latency--|---2x Latency--|            
// CS_L    \__________________________________________________________________/
// CK      ____/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \
// RWDS                     __________/      \___________
// DQ[7:0] ---<><><><><><>------------<><><><>-----------
//  dir      <       output         >-<output>-----------
//
// Reg Write 
//                   
// CS_L    \__________________________________________________________________/
// CK      ____/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \
// RWDS                     _____________________________
// DQ[7:0] ---<><><><><><><><>---------------------------
//  dir      <       output  >--------------------
//
// Command-Address Bit Packing:
//  47 R/W# Identifies the transaction as a read or write.
//     R/W#=1 indicates a Read transaction
//     R/W#=0 indicates a Write transaction
//  46 Address Space
//     AS=0 indicates memory space
//     AS=1 indicates the register space
//  45 Burst Type
//     Indicates whether the burst will be linear or wrapped.
//     Burst Type=0 indicates wrapped burst
//     Burst Type=1 indicates linear burst
//  44-16 Row & Upper Column Address
//  15-3 Reserved for future column address expansion.
//  2-0 Lower Column Address
//
// Register Address Map CA[39:0] to A[31:0] mapping
// This module reduces 48bit address down to a 32bit address. This table
// records what the 32bit addresses are for the 4 registers + default values
// 0x000000 0000 : ID-Reg0   0x00000000   : 0x0c81
// 0x000000 0001 : ID-Reg1   0x00000001   : 0x0000
// 0x000100 0000 : Cfg-Reg0  0x00000800   : 0x8f1f
// 0x000100 0001 : Cfg-Reg1  0x00000801   : 0x0002


//-----------------------------------------------------------------------------
// DRAM clock is core clock over 4.  This is to support the requirement of 
// placing both clock edges on center of the DDR data. A full bandwidth design
// would require fancy PLL phase shifting which falls beyond the scope of this
// portable RTL only interface project.
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_ck
 begin
   if ( run_jk == 1 ) begin 
     ck_phs <= ck_phs + 1;
   end else begin
     ck_phs <= 2'd0;
   end 
 end
end


//-----------------------------------------------------------------------------
// Shift Registers for 48bits of Ctrl+Addr and 32bits of Write Data
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_lb_regs
 begin
   rd_d       <= 32'd0;
   rd_rdy     <= 0;
   go_bit     <= 0;
   busy       <= run_jk | go_bit;

   if ( addr_shift == 1 ) begin
     addr_sr[47:0]  <= { addr_sr[39:0], 8'd0 };
   end
   if ( data_shift == 1 ) begin
     data_sr[31:0]   <= { data_sr[23:0], 8'd0 };
     sr_byte_en[3:0] <= { sr_byte_en[2:0], 1'b0 };
   end
   if ( burst_wr_jk_clr == 1 ) begin
     data_sr[31:0]   <= burst_wr_d[31:0];
     sr_byte_en[3:0] <= burst_wr_d[35:32];
   end

   if ( run_jk == 0 && ( wr_req == 1 || rd_req == 1 ) ) begin
     burst_wr_jk    <= 0;
     busy           <= 1;
     go_bit         <= 1;// Kick off the FSM
     sr_byte_en     <= wr_byte_en[3:0];
     rw_bit         <= rd_req;     // 0=WriteOp, 1=ReadOp
     reg_bit        <= mem_or_reg; // 0=MemSpace,1=RegSpace
     addr_sr[47]    <= rd_req;     // 0=WriteOp, 1=ReadOp
     addr_sr[46]    <= mem_or_reg;// 0=MemSpace,1=ReadSpace
     addr_sr[45]    <= 1'b1;// Linear Burst
     addr_sr[15:3]  <= 13'd0;
     if ( mem_or_reg == 0 ) begin
       addr_sr[44:16] <= addr[30:2];
       addr_sr[2:0]   <= { addr[1:0], 1'b0 };// Always getting DWORD
     end else begin
       addr_sr[44:16] <= addr[31:3];
       addr_sr[2:0]   <= addr[2:0];// Reg access needs 16bit LSB bit
     end

     data_sr[31:0]  <= wr_d[31:0];
   end 

   if ( burst_wr_jk_clr == 1 ) begin
     burst_wr_jk <= 0;
   end 
   if ( run_jk == 1 && wr_req == 1 && burst_wr_sr[4:0] != 5'd0 ) begin
     burst_wr_jk <= 1;
     burst_wr_d[31:0]  <= wr_d[31:0];
     burst_wr_d[35:32] <= wr_byte_en[3:0];
   end

   if ( rd_done == 1 ) begin
     rd_d   <= rd_sr[31:0];
     rd_rdy <= 1;
   end

   if ( reset == 1 ) begin 
     go_bit       <= 0;
     burst_wr_jk  <= 0;
   end 

 end
end // proc_lb_regs


//-----------------------------------------------------------------------------
// 3 State Machines:
//  fsm_addr : Counts the Address Cycles
//  fsm_wait : Counts the Latency Cycles
//  fsm_data : Counts the Data Cycles
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_fsm
 begin
   addr_shift <= 0;
   data_shift <= 0;
   wait_shift <= 0;
   burst_wr_jk_clr <= 0;
   if ( rd_req == 1 ) begin
     rd_dwords_cnt <= rd_num_dwords[5:0];
   end

   if ( ck_phs[0] == 1 ) begin
     if ( fsm_addr != 3'd0 ) begin
       dram_dq_oe_l   <= 0; // D[7:0] is Output 
       dram_rwds_oe_l <= 1; // RWDS is Input
       fsm_addr <= fsm_addr - 1;
       if ( fsm_addr == 3'd1 ) begin
         // Register Writes have zero latency
         if ( reg_bit == 1 && rw_bit == 0 ) begin
           fsm_wait <= 6'd0;
           fsm_data <= 4'd2;
         end else begin
           // Mem Writes Sample RWDS to determine 1 or 2 latency periods
           // fsm_wait positions write data at appropriate place in time.
           if ( rwds_in_loc == 0 ) begin
             fsm_wait <= latency_1x[5:0];
           end else begin
             fsm_wait <= latency_2x[5:0];
           end
         end
         if ( rw_bit == 1 ) begin
           fsm_wait  <= 6'd63;// This actually ends from RWDS strobing
           run_rd_jk <= 1;
         end
       end else begin
         fsm_wait <= 6'd0;
         fsm_data <= 4'd0;
       end
       sr_data    <= addr_sr[47:40];
       addr_shift <= 1;
     end 

     if ( fsm_wait != 6'd0 ) begin
       byte_wr_en <= 0;
       wait_shift <= 1;
       fsm_wait   <= fsm_wait - 1;
       if ( fsm_wait == 6'd1 ) begin
         fsm_data <= 4'd4;// Number of Bytes to Write
       end
//     sr_data <= { 2'd0, fsm_wait[5:0] };// Marker for when Latency is wrong
     end

     if ( fsm_data != 4'd0 ) begin
       fsm_data   <= fsm_data - 1;
       sr_data    <= data_sr[31:24];
       byte_wr_en <= sr_byte_en[3];
       data_shift <= 1;
       if ( fsm_data == 4'd1 ) begin
         run_jk <= 0;
         if ( burst_wr_jk == 1 ) begin 
           run_jk          <= 1;
           burst_wr_jk_clr <= 1;
           fsm_data        <= 4'd4;// Number of Bytes to Write
         end
       end
     end 

     if ( fsm_wait != 6'd0 || fsm_data != 4'd0 ) begin
       if ( rw_bit == 1 ) begin
         dram_dq_oe_l   <= 1; // Input for Reads
         dram_rwds_oe_l <= 1; // Input for Reads
       end else begin
         dram_dq_oe_l   <= 0; // Output for Writes
         dram_rwds_oe_l <= 0; // Output for Writes
       end
     end
   end // if ( ck_phs[0] == 1 ) begin

   if ( rd_done == 1 ) begin
     if ( rd_dwords_cnt == 6'd1 ) begin
       run_jk    <= 0;
       run_rd_jk <= 0;
       fsm_wait  <= 6'd0;
     end else begin
       rd_dwords_cnt <= rd_dwords_cnt - 1;
       fsm_wait      <= 6'd63;// This actually ends from RWDS strobing
     end 
   end 

   if ( go_bit == 1 ) begin
     fsm_addr       <= 3'd6;
     fsm_wait       <= 6'd0;
     fsm_data       <= 4'd0;
     run_jk         <= 1;
     dram_dq_oe_l   <= 1; // Default Input
     dram_rwds_oe_l <= 1; // Default Input
   end

   run_jk_sr <= { run_jk_sr[2:0], run_jk };
   if ( run_jk == 1 ) begin
     cs_loc <= 1;
   end else if ( run_jk_sr[1:0] == 2'd0 ) begin
     cs_loc <= 0;
     dram_dq_oe_l   <= 1; // Default Input
     dram_rwds_oe_l <= 1; // Default Input
   end 

   if ( reset == 1 ) begin 
     fsm_addr   <= 3'd0;
     fsm_data   <= 4'd0;
     fsm_wait   <= 6'd0;
     run_jk     <= 0;
     run_rd_jk  <= 0;
     byte_wr_en <= 0;
     cs_loc     <= 0;
   end 

   burst_wr_rdy <= 0;
   if ( fsm_data == 4'd4 && burst_wr_rdy == 0 ) begin
     burst_wr_rdy <= 1;
   end
   // Protection against wr_req coming in too late. There is a 5 clock window
   burst_wr_sr[4:0] <= { burst_wr_sr[3:0], burst_wr_rdy };

 end
end // proc_fsm


//-----------------------------------------------------------------------------
// Read SR
// clk        /\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
//                                                              0 1 2 3 0 1 2 
// CK     ___/   \___/   \___/   \___/   \___/   \___/   \___/   \___/   \_
// RWDS   \___________________________________________________/   \___/   \___
//  dir    < input        
// DQ[7:0]-<47><39><31><23><15><7 >---------------------------<  ><  ><  ><  >
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_rd_sr
 begin
   rwds_in_loc_p1 <= rwds_in_loc;
   rd_done        <= 0;
   sample_now     <= 0;

   if ( run_rd_jk == 0 ) begin
     rd_fsm <= 3'd4;
     rd_cnt <= 4'd0;
   end else begin
     if ( rd_fsm == 3'd4 ) begin
       if ( rwds_in_loc == 1 && rwds_in_loc_p1 == 0 ) begin
         rd_fsm     <= 3'd0;
         sample_now <= 1;
       end
     end else begin
       rd_fsm <= rd_fsm + 1;
       if ( rd_fsm == 3'd1 ) begin
         rd_fsm     <= 3'd4;
         sample_now <= 1;
       end
     end
   end 

   if ( sample_now == 1 ) begin 
     rd_sr[31:0] <= { rd_sr[23:0], dram_rd_d[7:0] };
     rd_cnt      <= rd_cnt + 1;
     if ( rd_cnt == 4'd3 ) begin
       rd_done <= 1;// Call it a day after 4 bytes
       rd_cnt  <= 4'd0;
     end
   end 
   
 end
end // proc_rd_sr
  // Pipe out some signals for bebugging using SUMP
  assign sump_dbg[0] = busy;
  assign sump_dbg[1] = run_rd_jk;
  assign sump_dbg[2] = sample_now;
  assign sump_dbg[3] = rd_done;
  assign sump_dbg[7:4] = rd_cnt[3:0];


//-----------------------------------------------------------------------------
// IO Flops
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_out
 begin
   dram_ck_loc   <= ck_phs[1];
   dram_ck       <= dram_ck_loc;
   rwds_in_loc   <= dram_rwds_in;
   dram_rd_d     <= dram_dq_in[7:0];
   dram_dq_out   <= sr_data[7:0];
   dram_rwds_out <= ~ byte_wr_en;// Note: rwds is a mask, 1==Don't Write Byte
   cs_l_reg    <= ~ cs_loc;

   if ( reset == 1 ) begin
     cs_l_reg <= 1;
   end 

 end
end // proc_out
  assign dram_cs_l = cs_l_reg;


endmodule // hyper_xface.v
