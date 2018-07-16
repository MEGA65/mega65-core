/* 
** Copyright (c) 2018 Kenneth C. Dyke
** 
** Permission is hereby granted, free of charge, to any person obtaining a copy
** of this software and associated documentation files (the "Software"), to deal
** in the Software without restriction, including without limitation the rights
** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
** copies of the Software, and to permit persons to whom the Software is
** furnished to do so, subject to the following conditions:
** 
** The above copyright notice and this permission notice shall be included in all
** copies or substantial portions of the Software.
** 
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
** SOFTWARE.
*/

`ifndef _6502_inc_vh_
`define _6052_inc_vh_

// Enable 65C02 extensions by default.
`define CMOS 1

// For when I want to synthesize and keep the full internal hierarchy
//`define SCHEM_KEEP 1
`ifdef SCHEM_KEEP
`define SCHEM_KEEP_HIER (* keep_hierarchy = "yes" *)
`else
`define SCHEM_KEEP_HIER
`endif

// `define EN_MARK_DEBUG
`ifdef EN_MARK_DEBUG
`define MARK_DEBUG (* mark_debug = "true", dont_touch = "true" *)
`else
`define MARK_DEBUG
`endif

// This is just the universal "don't care" or "default"
`define none          0

`define ABUS_PCHPCL   3'd0
`define ABUS_S       3'd1
`define ABUS_ABHABL   3'd2
`define ABUS_ABL      3'd3
`define ABUS_DL       3'd4
`define ABUS_VEC      3'd5

// Internal data bus input select
`define DB_DI       0
`define DB_DOR      0       // Just a named alias to make it clear in the microcode when we are writing from DOR
`define DB_0        1
`define DB_A        2
`define DB_SB       3
`define DB_PCL      4
`define DB_PCH      5
`define DB_P        6
`define DB_BO       7       // Branch offset, 0 or FF

// Internal secondary bus input select
`define SB_A        0
`define SB_X        1
`define SB_Y        2
`define SB_S        3
`define SB_ALU      4
`define SB_ADH      5
`define SB_DB       6
`define SB_FF       7

// Internal ADH bus input select
`define ADH_DI      0       // ADH is data bus input (not latched)
`define ADH_ALU     1       // ADH is current value from ALU
`define ADH_PCHS    2       // ADH is current PCHS out
`define ADH_0       3       // This would eventually be the base page register
`define ADH_1       4       // This would eventually be the stack page register
`define ADH_FF      5

// Internal ADL bus input select
`define ADL_DI      0       // ADL is data bus input (not latched)
`define ADL_PCLS    1       // ADL is current PCLS out
`define ADL_S       2       // ADL is current stack pointer
`define ADL_ALU     3       // ADL is ALU output
`define ADL_VECLO   4       // ADL is low vector address
`define ADL_VECHI   5       // ADL is high vector address

`define PCLS_PCL    0
`define PCLS_ADL    1

`define PCHS_PCH    0
`define PCHS_ADH    1

`define PCHPCL      0
`define PCHADL      1
`define ADHPCL      2
`define ADHADL      3

// ALU A input select - always loaded
`define ALU_A_0     1
`define ALU_A_SB    2
`define ALU_A_NSB   3
`define ALU_A_IR    4
`define ALU_A_NIR   5

// ALU_B input select - 0 holds last input
`define ALU_B_DB    1  
`define ALU_B_NDB   2  
`define ALU_B_ADL   3

// ALU Carry select
`define ALU_C_0     0       // Forced to 0
`define ALU_C_1     1       // Forced to 1
`define ALU_C_P     2       // Carry from status register
`define ALU_C_A     3       // Carry from previous accumulator carry

// ALU ops - some extra space for "illegal" ops in the future when I get to it.
`define ALU_ADC   4'b0000
`define ALU_SUM   4'b0000
`define ALU_ORA   4'b0001
`define ALU_AND   4'b0010
`define ALU_EOR   4'b0011
`define ALU_SBC   4'b0100
`define ALU_ROR   4'b0101
`define ALU_PSA   4'b1111   // Just pass A input through - Used for JSR passthrough and to hold RMW results

`define LF_C_DB0      0
`define LF_C_IR5      1
`define LF_C_ACR      2
`define LF_Z_SBZ      3
`define LF_Z_DB1      4
`define LF_I_DB2      5
`define LF_I_IR5      6
`define LF_D_DB3      7
`define LF_D_IR5      8
`define LF_V_DB6      9
`define LF_V_AVR      10
`define LF_V_0        11
`define LF_N_SBN      12
`define LF_N_DB7      13
`define LF_I_1        14

`define LM_C_DB0      (1 << `LF_C_DB0)
`define LM_C_IR5      (1 << `LF_C_IR5)
`define LM_C_ACR      (1 << `LF_C_ACR)
`define LM_Z_SBZ      (1 << `LF_Z_SBZ)
`define LM_Z_DB1      (1 << `LF_Z_DB1)
`define LM_I_DB2      (1 << `LF_I_DB2)
`define LM_I_IR5      (1 << `LF_I_IR5)
`define LM_D_DB3      (1 << `LF_D_DB3)
`define LM_D_IR5      (1 << `LF_D_IR5)
`define LM_V_DB6      (1 << `LF_V_DB6)
`define LM_V_AVR      (1 << `LF_V_AVR)
`define LM_V_0        (1 << `LF_V_0  )
`define LM_N_SBN      (1 << `LF_N_SBN)
`define LM_N_DB7      (1 << `LF_N_DB7)
`define LM_I_1        (1 << `LF_I_1  )

`define FLAGS_DB    4'h1
`define FLAGS_SBZN  4'h2
`define FLAGS_ALU   4'h3
`define FLAGS_D     4'h4
`define FLAGS_I     4'h5
`define FLAGS_C     4'h6
`define FLAGS_V     4'h7
`define FLAGS_SETI  4'h8
`define FLAGS_CNZ   4'h9
`define FLAGS_BIT   4'ha
`define FLAGS_Z     4'hb

`define ALUF_C 0
`define ALUF_Z 1
`define ALUF_V 2
`define ALUF_N 3

`define PF_C 0
`define PF_Z 1
`define PF_I 2
`define PF_D 3
`define PF_B 4
`define PF_U 5
`define PF_V 6
`define PF_N 7

// TODO - Move all the microcode related `defines to a separate file that's not visible to the rest
// of the code, since it's supposed to be an implementation detail.

`define Tn    3'd0        // Go to T+1 (default)
`define T0    3'd1        // Go to T0
`define TNC   3'd2        // Go to T0 if ALU carry is 0
`define TBE   3'd3        // Go to T0 if no branch page crossing
`define TBR   3'd4        // Go to T1 if branch condition code check fails
`define TBT   3'd5        // Go to T1 if branch bit test check fails
`define TKL   3'd7        // Halt CPU - Unimplemented microcode entry

// Note: Try not to have any signals span 8 bit boundaries, which gives the synthesis more options
// in choosing which signals go with which block rams.  Still to do: Figure out if there are better
// groupings for signals that are likely to go to similar places.

// Also... block RAMs are really 36 bits wide, so it's also useful to make sure those last 4 bits
// are grouped together.  Although for Artix-7 the synthesis tools really wind up generating 3
// 2K x 18bit block RAMs.  So the bit groupings really wind up being 3 groups of 18 bits.

// 7:0
`define TNEXT_BITS      2:0
`define LOAD_ABH_BITS   3:3
`define ADH_BITS        7:5

// 15:8
`define PC_INC_BITS     8:8
`define ADL_BITS        12:10
`define LOAD_ABL_BITS   13:13
`define PCLS_BITS       14:14
`define PCHS_BITS       15:15
`define PC_BITS         15:14

// 23:16
`define ALU_A_BITS      18:16
`define ALU_B_BITS      21:20
`define ALU_C_BITS      23:22

// 31:24
`define ALU_BITS        27:24
`define LOAD_REG_BITS   31:28
`define LOAD_A_BITS     28:28
`define LOAD_X_BITS     29:29
`define LOAD_Y_BITS     30:30
`define LOAD_S_BITS     31:31

// 39:32
`define DB_BITS         34:32
`define WRITE_BITS      35:35
`define SB_BITS         38:36

// 42:39
`define LOAD_FLAGS_BITS 42:39
`define MICROCODE_BITS  42:0

`define FIELD_SHIFT(_x) (0?_x)

`define LOAD_A 4'b0001
`define LOAD_X 4'b0010
`define LOAD_Y 4'b0100
`define LOAD_S 4'b1000

`define MICROCODE(_ins, _t, _tnext, _adh_sel, _adl_sel, _load_abh, _load_abl,  _pc_sel, _pc_inc, _db_sel, _sb_sel, _alu_sel, _alu_a, _alu_b, _alu_c, _load_reg,_load_flags, _write) \
mc[(_ins << 3) | _t] = ( \
  (_tnext << `FIELD_SHIFT(`TNEXT_BITS)) | \
  (_adh_sel << `FIELD_SHIFT(`ADH_BITS)) | \
  (_adl_sel << `FIELD_SHIFT(`ADL_BITS)) | \
  (_load_abh << `FIELD_SHIFT(`LOAD_ABH_BITS)) | \
  (_load_abl << `FIELD_SHIFT(`LOAD_ABL_BITS)) | \
  (_pc_sel << `FIELD_SHIFT(`PC_BITS)) | \
  (_pc_inc << `FIELD_SHIFT(`PC_INC_BITS)) | \
  (_db_sel << `FIELD_SHIFT(`DB_BITS)) | \
  (_sb_sel << `FIELD_SHIFT(`SB_BITS)) | \
  (_alu_sel << `FIELD_SHIFT(`ALU_BITS)) | \
  (_alu_a << `FIELD_SHIFT(`ALU_A_BITS)) | \
  (_alu_b << `FIELD_SHIFT(`ALU_B_BITS)) | \
  (_alu_c << `FIELD_SHIFT(`ALU_C_BITS)) | \
  (_load_reg << `FIELD_SHIFT(`LOAD_REG_BITS)) | \
  (_load_flags << `FIELD_SHIFT(`LOAD_FLAGS_BITS)) | \
  (_write << `FIELD_SHIFT(`WRITE_BITS)) \
  );

// ADH/ADL combinations used:
//
// PCHS/PCLS              -- Data Fetch
// 1/S                    -- Stack
// 1/ALU                  -- Stack Op
// FF/VECLO               -- Vector Fectch
// FF/VECHI               -- Vector Fetch
// DI/ALU                 -- High Addres Fetch
// 0/DI                   -- Zero Page
// 0/ALU                  -- Zero Page Index
// ALU/PCLS               -- High Address Carry
// PCHS/ALU               -- Low ALU
//
// Could trivially go from 6 to 4 bits, which would give me 5 bits for timing state control to play with.
//                                                                                                                                      Register Loads
//                 INS   T  Tn    Adh       Adl        AH  AL  PC      INC   Db,       Sb,   Alu_op    Alu_a      Alu_b       Alu_c     Load     Flags      WC

`define BRK(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  1, `DB_PCH,`SB_FF,  `none,    `ALU_A_SB, `ALU_B_ADL, `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_PCL,`SB_FF,  `ALU_SUM, `ALU_A_SB, `ALU_B_ADL, `ALU_C_0, `none,   `none,       1) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_P,  `SB_FF,  `ALU_SUM, `ALU_A_SB, `ALU_B_ADL, `ALU_C_0, `none,   `none,       1) \
`MICROCODE( _insbyte,  5, `Tn , `ADH_FF,   `ADL_VECLO, 1,  1, `PCHPCL,  0, `DB_DI, `SB_ALU, `ALU_SUM, `none,     `none,      `ALU_C_0, `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  6, `T0 , `ADH_FF,   `ADL_VECHI, 1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `FLAGS_SETI, 0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_DI,   `ADL_ALU,   1,  1, `ADHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define ADDR_zp_(_insbyte, tn, _db, _sb, _w) \
`MICROCODE( _insbyte,  2,  tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1,  _db,    _sb,    `none,    `none,     `none,      `none,    `none,   `none,       _w)

`define ADDR_zp_x_ind_(_insbyte, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1, `DB_DI, `SB_X,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_ADL, `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_1, `none,   `none,       0) \
`MICROCODE( _insbyte,  5, `T0 , `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       _w)

`define ADDR_abs_(_insbyte, tn, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  3,  tn , `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  1,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       _w)

`define ADDR_abs_x_(_insbyte, t1, t2, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_X,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3,  t1 , `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  1,  _db,    _sb,    `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       _w) \
`MICROCODE( _insbyte,  4,  t2 , `ADH_ALU,  `ADL_PCLS,  1,  0, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       _w)

`define ADDR_abs_y_(_insbyte, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_Y,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `TNC, `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  1,  _db,    _sb,    `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       _w) \
`MICROCODE( _insbyte,  4, `T0 , `ADH_ALU,  `ADL_PCLS,  1,  0, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       _w)

`define ADDR_zp_ind_y_(_insbyte, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `none,    `ALU_A_0,  `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_Y,   `ALU_SUM, `ALU_A_SB, `ALU_B_DB,  `ALU_C_1, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `TNC, `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       _w) \
`MICROCODE( _insbyte,  5, `T0 , `ADH_ALU,  `ADL_PCLS,  1,  0, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       _w)

`define ADDR_zp_ind_(_insbyte, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `none,    `ALU_A_0,  `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_Y,   `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_1, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `T0 , `ADH_DI,   `ADL_ALU,   1,  1, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       _w)

`define ADDR_zp_x_(_insbyte, tn, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_X,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3,  tn , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       _w)

`define ADDR_zp_y_(_insbyte, _db, _sb, _w) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_Y,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `T0 , `ADH_0,    `ADL_ALU,   1,  1, `PCHPCL,  0,  _db,    _sb,    `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       _w)

`define ADDR_jmp_abs(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_DI,   `ADL_ALU,   1,  1, `ADHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       0)

`define ADDR_jmp_abs_x(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_X,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_DI,   `ADL_ALU,   1,  1, `PCHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_ALU,  `ADL_PCLS,  1,  1, `ADHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       0)

`define ADDR_zp(_insbyte, tn)                     `ADDR_zp_(_insbyte, tn, `DB_DI, `SB_FF, 0)
`define ADDR_zp_w(_insbyte, tn, _db, _sb)         `ADDR_zp_(_insbyte, tn, _db, _sb, 1)
`define ADDR_zp_x_ind(_insbyte)                   `ADDR_zp_x_ind_(_insbyte, `DB_DI, `SB_FF, 0)
`define ADDR_zp_x_ind_w(_insbyte, _db, _sb)       `ADDR_zp_x_ind_(_insbyte, _db, _sb, 1)
`define ADDR_abs(_insbyte, tn)                    `ADDR_abs_(_insbyte, tn, `DB_DI, `SB_FF, 0)
`define ADDR_abs_w(_insbyte, tn, _db, _sb)        `ADDR_abs_(_insbyte, tn, _db, _sb, 1)
`define ADDR_abs_x(_insbyte, t1, t2)              `ADDR_abs_x_(_insbyte, t1, t2, `DB_DI, `SB_FF, 0)
`define ADDR_abs_x_w(_insbyte, t1, t2, _db, _sb)  `ADDR_abs_x_(_insbyte, t1, t2, _db, _sb, 1)
`define ADDR_abs_y(_insbyte)                      `ADDR_abs_y_(_insbyte, `DB_DI, `SB_FF, 0)
`define ADDR_abs_y_w(_insbyte, _db, _sb)          `ADDR_abs_y_(_insbyte, _db, _sb, 1)
`define ADDR_zp_ind_y(_insbyte)                   `ADDR_zp_ind_y_(_insbyte, `DB_DI, `SB_FF, 0)
`define ADDR_zp_ind_y_w(_insbyte, _db, _sb)       `ADDR_zp_ind_y_(_insbyte, _db, _sb, 1)
`define ADDR_zp_ind(_insbyte)                     `ADDR_zp_ind_(_insbyte, `DB_DI, `SB_FF, 0)
`define ADDR_zp_ind_w(_insbyte, _db, _sb)         `ADDR_zp_ind_(_insbyte, _db, _sb, 1)
`define ADDR_zp_x(_insbyte, tn)                   `ADDR_zp_x_(_insbyte, tn, `DB_DI, `SB_FF, 0)
`define ADDR_zp_x_w(_insbyte, tn, _db, _sb)       `ADDR_zp_x_(_insbyte, tn, _db, _sb, 1)
`define ADDR_zp_y(_insbyte)                       `ADDR_zp_y_(_insbyte, `DB_DI, `SB_FF, 0)
`define ADDR_zp_y_w(_insbyte, _db, _sb)           `ADDR_zp_y_(_insbyte, _db, _sb, 1)

`define ALUA(_insbyte, _aluop, _alub, _sb, _carry, _load, _flags, _i) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL, _i, `DB_DI, _sb,     `none,    `ALU_A_SB, _alub,      `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_SB, `SB_ALU, _aluop,   `none,     `none,      _carry,   _load,   _flags,      0) \
`MICROCODE( _insbyte,  7, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_A,  `SB_A,   `none,    `none,     `none,      `none,    `none,   `FLAGS_SBZN, 0)

`define BIT(_insbyte, _flags, _i) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL, _i, `DB_DI, `SB_A,   `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   _flags,      0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_SB, `SB_ALU, `ALU_AND, `none,     `none,      `ALU_C_0, `none,   `FLAGS_Z,    0)

`define STx(_insbyte) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_A,   `none,    `none,     `none,      `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_A,   `none,    `none,     `none,      `none,    `none,   `none,       0)

`define LDx(_insbyte, _load, _i) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL, _i, `DB_DI, `SB_DB,  `none,    `none,     `none,      `none,    _load,   `FLAGS_SBZN, 0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define BRA(_insbyte, t2) \
`MICROCODE( _insbyte,  2,   t2, `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `none,    `ALU_A_SB, `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `TBE, `ADH_PCHS, `ADL_ALU,   1,  1, `PCHADL,  0, `DB_BO, `SB_ADH, `ALU_SUM, `ALU_A_SB, `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_ALU,  `ADL_PCLS,  1,  1, `ADHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

// BBx
`define BBR(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_DB,  `none,    `ALU_A_IR, `ALU_B_NDB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `TBT, `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `ALU_AND, `ALU_A_SB, `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  5, `TBE, `ADH_PCHS, `ADL_ALU,   1,  1, `PCHADL,  0, `DB_BO, `SB_ADH, `ALU_SUM, `ALU_A_SB, `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_ALU,  `ADL_PCLS,  1,  1, `ADHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define BBS(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_0,    `ADL_DI,    1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_DB,  `none,    `ALU_A_IR, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `TBT, `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `ALU_AND, `ALU_A_SB, `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  5, `TBE, `ADH_PCHS, `ADL_ALU,   1,  1, `PCHADL,  0, `DB_BO, `SB_ADH, `ALU_SUM, `ALU_A_SB, `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_ALU,  `ADL_PCLS,  1,  1, `ADHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_A, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define SHIFT_MEM(_insbyte, c1, c2, _aluop, _carry) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_DB,  `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, _aluop,   `ALU_A_SB, `ALU_B_ADL, _carry,   `none,   `FLAGS_CNZ,  1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_ALU, `none,    `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define SHIFT_A(_insbyte, _aluop, _carry) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_A,  `SB_A,    `none,   `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_SB, `SB_ALU, _aluop,   `none,     `none,      _carry,   `LOAD_A, `FLAGS_CNZ,  0)

`define FLAG_OP(_insbyte, _flag) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   _flag,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define Txx(_insbyte, _sb, _load, _flags) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_SB,   _sb,   `none,    `none,     `none,      `none,    _load,   _flags,      0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define DEC_REG(_insbyte, _reg, _load) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_0,     _reg, `none,    `ALU_A_SB, `ALU_B_NDB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_SB, `SB_ALU, `ALU_SUM, `none,     `none,      `ALU_C_0, _load,   `FLAGS_SBZN, 0)

`define INC_REG(_insbyte, _reg, _load) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_0,     _reg, `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_SB, `SB_ALU, `ALU_SUM, `none,     `none,      `ALU_C_1, _load,   `FLAGS_SBZN, 0)

`define DEC_MEM(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `ALU_A_SB, `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_SUM, `ALU_A_SB, `ALU_B_ADL, `ALU_C_0, `none,   `FLAGS_SBZN, 1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define INC_MEM(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_DB,  `none,    `ALU_A_0,  `ALU_B_DB,  `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_SUM, `ALU_A_SB, `ALU_B_ADL, `ALU_C_1, `none,   `FLAGS_SBZN, 1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define PUSH(_insbyte, _db, _sb) \
`MICROCODE( _insbyte,  2, `T0 , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  0,  _db,    _sb,    `none,    `none,     `none,      `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_0,  `SB_S,   `none,    `ALU_A_SB, `ALU_B_NDB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_ALU, `ALU_SUM, `none,     `none,      `ALU_C_0, `LOAD_S, `none,       0)

`define PULL(_insbyte, _load, _flags) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  0, `DB_0,  `SB_FF,  `none,    `ALU_A_0,  `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `T0 , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_0,  `SB_ALU, `ALU_SUM, `none,     `none,      `ALU_C_1, `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_DB,  `none,    `none,     `none,      `none,    _load,   _flags,      0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define JSR(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  1, `DB_PCH,`SB_DB,  `none,    `ALU_A_0,  `ALU_B_ADL, `none,    `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_PCH,`SB_FF,  `ALU_SUM, `ALU_A_SB, `none,      `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_PCL,`SB_FF,  `ALU_SUM, `ALU_A_SB, `ALU_B_ADL, `ALU_C_0, `none,   `none,       1) \
`MICROCODE( _insbyte,  5, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_ALU, `ALU_SUM, `ALU_A_SB, `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_DI,   `ADL_S,     1,  1, `ADHADL,  0, `DB_DI, `SB_ALU, `ALU_PSA, `none,     `none,      `ALU_C_0, `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define RTI(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `none,    `ALU_A_0,  `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_ADL, `ALU_C_1, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_ADL, `ALU_C_1, `none,   `FLAGS_DB,   0) \
`MICROCODE( _insbyte,  5, `T0 , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_ALU, `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_1, `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_DI,   `ADL_ALU,   1,  1, `ADHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define JMP(_insbyte, t0) \
`MICROCODE( _insbyte, t0, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `ALU_A_0,  `ALU_B_DB,  `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_DI,   `ADL_ALU,   1,  1, `ADHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define RTS(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_1,    `ADL_S,     1,  1, `PCHPCL,  1, `DB_DI, `SB_DB,  `none,    `ALU_A_0,  `ALU_B_ADL, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `ALU_A_0,  `ALU_B_ADL, `ALU_C_1, `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_1,    `ADL_ALU,   1,  1, `PCHPCL,  0, `DB_DI, `SB_ALU, `ALU_SUM, `ALU_A_0,  `ALU_B_DB,  `ALU_C_1, `LOAD_S, `none,       0) \
`MICROCODE( _insbyte,  5, `T0 , `ADH_DI,   `ADL_ALU,   1,  1, `ADHADL,  0, `DB_DI, `SB_FF,  `ALU_SUM, `none,     `none,      `ALU_C_0, `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,     `none,      `none,    `none,   `none,       0)

`define TRB(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_A,   `none,    `ALU_A_NSB, `ALU_B_DB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_AND, `none,      `none,     `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_A,   `none,    `ALU_A_SB,  `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_ALU, `ALU_AND, `none,      `none,     `none,    `none,   `FLAGS_Z,    0)

`define TSB(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_A,   `none,    `ALU_A_SB,  `ALU_B_DB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_ORA, `none,      `none,     `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_A,   `none,    `ALU_A_SB,  `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_ALU, `ALU_AND, `none,      `none,     `none,    `none,   `FLAGS_Z,    0)

`define RMB(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `ALU_A_NIR, `ALU_B_DB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_AND, `none,      `none,     `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define SMB(_insbyte, c1, c2) \
`MICROCODE( _insbyte, c1, `Tn , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `ALU_A_IR,  `ALU_B_DB, `none,    `none,   `none,       0) \
`MICROCODE( _insbyte, c2, `T0 , `ADH_PCHS, `ADL_PCLS,  0,  0, `PCHPCL,  0, `DB_SB, `SB_ALU, `ALU_ORA, `none,      `none,     `none,    `none,   `none,       1) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP1_1(_insbyte) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP1_2(_insbyte) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP2_2(_insbyte) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP2_3(_insbyte) \
`MICROCODE( _insbyte,  2, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP2_4(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP3_4(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define NOP3_8(_insbyte) \
`MICROCODE( _insbyte,  2, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  3, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  4, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  5, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  6, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  7, `T0 , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  0, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  0, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0) \
`MICROCODE( _insbyte,  1, `Tn , `ADH_PCHS, `ADL_PCLS,  1,  1, `PCHPCL,  1, `DB_DI, `SB_FF,  `none,    `none,      `none,     `none,    `none,   `none,       0)

`define ORA(_insbyte,_inc) `ALUA(_insbyte, `ALU_ORA, `ALU_B_DB,  `SB_A, `ALU_C_0, `LOAD_A, `FLAGS_SBZN, _inc)
`define AND(_insbyte,_inc) `ALUA(_insbyte, `ALU_AND, `ALU_B_DB,  `SB_A, `ALU_C_0, `LOAD_A, `FLAGS_SBZN, _inc)
`define EOR(_insbyte,_inc) `ALUA(_insbyte, `ALU_EOR, `ALU_B_DB,  `SB_A, `ALU_C_0, `LOAD_A, `FLAGS_SBZN, _inc)
`define ADC(_insbyte,_inc) `ALUA(_insbyte, `ALU_ADC, `ALU_B_DB,  `SB_A, `ALU_C_P, `LOAD_A, `FLAGS_ALU,  _inc)
`define SBC(_insbyte,_inc) `ALUA(_insbyte, `ALU_SBC, `ALU_B_NDB, `SB_A, `ALU_C_P, `LOAD_A, `FLAGS_ALU,  _inc)
`define CMP(_insbyte,_inc) `ALUA(_insbyte, `ALU_SUM, `ALU_B_NDB, `SB_A, `ALU_C_1, `none,   `FLAGS_CNZ,  _inc)
`define CPX(_insbyte,_inc) `ALUA(_insbyte, `ALU_SUM, `ALU_B_NDB, `SB_X, `ALU_C_1, `none,   `FLAGS_CNZ,  _inc)
`define CPY(_insbyte,_inc) `ALUA(_insbyte, `ALU_SUM, `ALU_B_NDB, `SB_Y, `ALU_C_1, `none,   `FLAGS_CNZ,  _inc)


`define LDA(_insbyte, _inc) `LDx(_insbyte, `LOAD_A, _inc)
`define LDX(_insbyte, _inc) `LDx(_insbyte, `LOAD_X, _inc)
`define LDY(_insbyte, _inc) `LDx(_insbyte, `LOAD_Y, _inc)

`define ASL_MEM(_insbyte, c1, c2) `SHIFT_MEM(_insbyte, c1, c2, `ALU_SUM, `ALU_C_0)
`define ROL_MEM(_insbyte, c1, c2) `SHIFT_MEM(_insbyte, c1, c2, `ALU_SUM, `ALU_C_P)
`define LSR_MEM(_insbyte, c1, c2) `SHIFT_MEM(_insbyte, c1, c2, `ALU_ROR, `ALU_C_0)
`define ROR_MEM(_insbyte, c1, c2) `SHIFT_MEM(_insbyte, c1, c2, `ALU_ROR, `ALU_C_P)

`define ASL_A(_insbyte) `SHIFT_A(_insbyte, `ALU_SUM, `ALU_C_0)
`define ROL_A(_insbyte) `SHIFT_A(_insbyte, `ALU_SUM, `ALU_C_P)
`define LSR_A(_insbyte) `SHIFT_A(_insbyte, `ALU_ROR, `ALU_C_0)
`define ROR_A(_insbyte) `SHIFT_A(_insbyte, `ALU_ROR, `ALU_C_P)

`endif //_6502_inc_vh_
