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

`include "6502_inc.vh"

(* keep_hierarchy = "yes" *) module microcode(input clk, input ready, input [7:0] ir, input [2:0] t, 
                  output wire [2:0] tnext, output wire [2:0] adh_sel, output wire [2:0] adl_sel, 
                  output wire [2:0] db_sel, output wire [2:0] sb_sel, output wire pchs_sel, output wire pcls_sel, 
                  output wire [3:0] alu_op, output wire [2:0] alu_a, output wire [1:0] alu_b, output wire [1:0] alu_c,
                  output wire load_a, output wire load_x, output wire load_y, output wire load_s, output wire load_abh, output wire load_abl, 
                  output wire [3:0] load_flags, output wire write_cycle, output wire pc_inc);

reg [`MICROCODE_BITS] mc_out;
(* rom_style = "block" *) reg [`MICROCODE_BITS] mc[0:2047];

// synthesis translate off
reg [12:0] i;
// synthesis translate on

initial begin

// synthesis translate off
// Init all microcode slots we haven't implemented with a state that halts
for( i = 0; i < 2048; i = i + 1 ) 
begin
   mc[i][`TNEXT_BITS] = `TKL;
   //$display("init %d",i);
end
// synthesis translate on

                            `BRK(8'h00)       // BRK
                            
`ADDR_zp_x_ind(8'h01)       `ORA(8'h01,0)     // ORA (zp,x)
`ADDR_zp(8'h05,`T0)         `ORA(8'h05,0)     // ORA zp
                            `ORA(8'h09,1)     // ORA #
`ADDR_abs(8'h0D,`T0)        `ORA(8'h0D,0)     // ORA abs
`ADDR_zp_ind_y(8'h11)       `ORA(8'h11,0)     // ORA (zp),y
`ADDR_zp_x(8'h15,`T0)       `ORA(8'h15,0)     // ORA zp,x
`ADDR_abs_y(8'h19)          `ORA(8'h19,0)     // ORA abs,y
`ADDR_abs_x(8'h1D,`TNC,`T0) `ORA(8'h1D,0)     // ORA abs,x

`ADDR_zp_x_ind(8'h21)       `AND(8'h21,0)     // AND (zp,x)
`ADDR_zp(8'h25,`T0)         `AND(8'h25,0)     // AND zp
                            `AND(8'h29,1)     // AND #
`ADDR_abs(8'h2D,`T0)        `AND(8'h2D,0)     // AND abs
`ADDR_zp_ind_y(8'h31)       `AND(8'h31,0)     // AND (zp),y
`ADDR_zp_x(8'h35,`T0)       `AND(8'h35,0)     // AND zp,x
`ADDR_abs_y(8'h39)          `AND(8'h39,0)     // AND abs,y
`ADDR_abs_x(8'h3D,`TNC,`T0) `AND(8'h3D,0)     // AND abs,x

`ADDR_zp(8'h24,`T0)         `BIT(8'h24,`FLAGS_BIT,0)       // BIT zp
`ADDR_abs(8'h2C,`T0)        `BIT(8'h2C,`FLAGS_BIT,0)       // BIT abs

`ADDR_zp_x_ind(8'h41)       `EOR(8'h41,0)     // EOR (zp,x)
`ADDR_zp(8'h45,`T0)         `EOR(8'h45,0)     // EOR zp
                            `EOR(8'h49,1)     // EOR #
`ADDR_abs(8'h4D,`T0)        `EOR(8'h4D,0)     // EOR abs
`ADDR_zp_ind_y(8'h51)       `EOR(8'h51,0)     // EOR (zp),y
`ADDR_zp_x(8'h55,`T0)       `EOR(8'h55,0)     // EOR zp,x
`ADDR_abs_y(8'h59)          `EOR(8'h59,0)     // EOR abs,y
`ADDR_abs_x(8'h5D,`TNC,`T0) `EOR(8'h5D,0)     // EOR abs,x

`ADDR_zp_x_ind(8'h61)       `ADC(8'h61,0)     // ADC (zp,x)
`ADDR_zp(8'h65,`T0)         `ADC(8'h65,0)     // ADC zp
                            `ADC(8'h69,1)     // ADC #
`ADDR_abs(8'h6D,`T0)        `ADC(8'h6D,0)     // ADC abs
`ADDR_zp_ind_y(8'h71)       `ADC(8'h71,0)     // ADC (zp),y
`ADDR_zp_x(8'h75,`T0)       `ADC(8'h75,0)     // ADC zp,x
`ADDR_abs_y(8'h79)          `ADC(8'h79,0)     // ADC abs,y
`ADDR_abs_x(8'h7D,`TNC,`T0) `ADC(8'h7D,0)     // ADC abs,x

`ADDR_zp_x_ind_w(8'h81,`DB_SB, `SB_A)         `STx(8'h81)       // STA (zp,x)
`ADDR_zp_w(8'h84,`T0, `DB_SB, `SB_Y)          `STx(8'h84)       // STY zp
`ADDR_zp_w(8'h85,`T0, `DB_SB, `SB_A)          `STx(8'h85)       // STA zp
`ADDR_zp_w(8'h86,`T0, `DB_SB, `SB_X)          `STx(8'h86)       // STX zp
`ADDR_abs_w(8'h8C,`T0, `DB_SB, `SB_Y)         `STx(8'h8C)       // STY abs
`ADDR_abs_w(8'h8D,`T0, `DB_SB, `SB_A)         `STx(8'h8D)       // STA abs
`ADDR_abs_w(8'h8E,`T0, `DB_SB, `SB_X)         `STx(8'h8E)       // STX abs
`ADDR_zp_ind_y_w(8'h91, `DB_SB, `SB_A)        `STx(8'h91)       // STA (zp),y
`ADDR_zp_x_w(8'h94,`T0, `DB_SB, `SB_Y)        `STx(8'h94)       // STY zp,x
`ADDR_zp_x_w(8'h95,`T0, `DB_SB, `SB_A)        `STx(8'h95)       // STA zp,x
`ADDR_zp_y_w(8'h96, `DB_SB, `SB_X)            `STx(8'h96)       // STX zp,y
`ADDR_abs_y_w(8'h99, `DB_SB, `SB_A)           `STx(8'h99)       // STA abs,y
`ADDR_abs_x_w(8'h9D,`TNC,`T0, `DB_SB, `SB_A)  `STx(8'h9D)       // STA abs,x

                            `LDY(8'hA0,1)     // LDY #
`ADDR_zp_x_ind(8'hA1)       `LDA(8'hA1,0)     // LDA (zp,x)
                            `LDX(8'hA2,1)     // LDX #
                            `LDA(8'hA9,1)     // LDA #
`ADDR_zp(8'hA4,`T0)         `LDY(8'hA4,0)     // LDY zp
`ADDR_zp(8'hA5,`T0)         `LDA(8'hA5,0)     // LDA zp
`ADDR_zp(8'hA6,`T0)         `LDX(8'hA6,0)     // LDX zp
`ADDR_abs(8'hAC,`T0)        `LDY(8'hAC,0)     // LDY abs
`ADDR_abs(8'hAD,`T0)        `LDA(8'hAD,0)     // LDA abs
`ADDR_abs(8'hAE,`T0)        `LDX(8'hAE,0)     // LDX abs
`ADDR_zp_ind_y(8'hB1)       `LDA(8'hB1,0)     // LDA (zp),y
`ADDR_zp_x(8'hB4,`T0)       `LDY(8'hB4,0)     // LDY zp,x
`ADDR_zp_x(8'hB5,`T0)       `LDA(8'hB5,0)     // LDA zp,x
`ADDR_zp_y(8'hB6)           `LDX(8'hB6,0)     // LDX zp,y
`ADDR_abs_y(8'hB9)          `LDA(8'hB9,0)     // LDA abs,y
`ADDR_abs_x(8'hBC,`TNC,`T0) `LDY(8'hBC,0)     // LDY abs,x
`ADDR_abs_x(8'hBD,`TNC,`T0) `LDA(8'hBD,0)     // LDA abs,x
`ADDR_abs_y(8'hBE)          `LDX(8'hBE,0)     // LDX abs,y

                            `CPY(8'hC0,1)     // CPY #
`ADDR_zp_x_ind(8'hC1)       `CMP(8'hC1,0)     // CMP (zp,x)
`ADDR_zp(8'hC4,`T0)         `CPY(8'hC4,0)     // CPY zp
`ADDR_zp(8'hC5,`T0)         `CMP(8'hC5,0)     // CMP zp
                            `CMP(8'hC9,1)     // CMP #
`ADDR_abs(8'hCC,`T0)        `CPY(8'hCC,0)     // CPY abs
`ADDR_abs(8'hCD,`T0)        `CMP(8'hCD,0)     // CMP abs
`ADDR_zp_ind_y(8'hD1)       `CMP(8'hD1,0)     // CMP (zp),y
`ADDR_zp_x(8'hD5,`T0)       `CMP(8'hD5,0)     // CMP zp,x
`ADDR_abs_y(8'hD9)          `CMP(8'hD9,0)     // CMP abs,y
`ADDR_abs_x(8'hDD,`TNC,`T0) `CMP(8'hDD,0)     // CMP abs,x
                            `CPX(8'hE0,1)     // CPX #
`ADDR_zp(8'hE4,`T0)         `CPX(8'hE4,0)     // CPY zp
`ADDR_abs(8'hEC,`T0)        `CPX(8'hEC,0)     // CPX abs

`ADDR_zp_x_ind(8'hE1)       `SBC(8'hE1,0)     // SBC (zp,x)
`ADDR_zp(8'hE5,`T0)         `SBC(8'hE5,0)     // SBC zp
                            `SBC(8'hE9,1)     // SBC #
`ADDR_abs(8'hED,`T0)        `SBC(8'hED,0)     // SBC abs
`ADDR_zp_ind_y(8'hF1)       `SBC(8'hF1,0)     // SBC (zp),y
`ADDR_zp_x(8'hF5,`T0)       `SBC(8'hF5,0)     // SBC zp,x
`ADDR_abs_y(8'hF9)          `SBC(8'hF9,0)     // SBC abs,y
`ADDR_abs_x(8'hFD,`TNC,`T0) `SBC(8'hFD,0)     // SBC abs,x

                            `BRA(8'h10,`TBR) // BPL
                            `BRA(8'h30,`TBR) // BMI
                            `BRA(8'h50,`TBR) // BVC
                            `BRA(8'h70,`TBR) // BVS
                            `BRA(8'h90,`TBR) // BCC
                            `BRA(8'hB0,`TBR) // BCS
                            `BRA(8'hD0,`TBR) // BNE
                            `BRA(8'hF0,`TBR) // BEQ

`ADDR_zp(8'h06,`Tn)         `ASL_MEM(8'h06, 3, 4)     // ASL zp
                            `ASL_A(8'h0A)             // ASL a
`ADDR_abs(8'h0E,`Tn)        `ASL_MEM(8'h0E, 4, 5)     // ASL abs
`ADDR_zp_x(8'h16,`Tn)       `ASL_MEM(8'h16, 4, 5)     // ASL zp,x
`ADDR_abs_x(8'h1E,`Tn,`Tn)  `ASL_MEM(8'h1E, 5, 6)     // ASL abs,x

`ADDR_zp(8'h26,`Tn)         `ROL_MEM(8'h26, 3, 4)     // ROL zp
                            `ROL_A(8'h2A)             // ROL a
`ADDR_abs(8'h2E,`Tn)        `ROL_MEM(8'h2E, 4, 5)     // ROL abs
`ADDR_zp_x(8'h36,`Tn)       `ROL_MEM(8'h36, 4, 5)     // ROL zp,x
`ADDR_abs_x(8'h3E,`Tn,`Tn)  `ROL_MEM(8'h3E, 5, 6)     // ROL abs,x

`ADDR_zp(8'h46,`Tn)         `LSR_MEM(8'h46, 3, 4)     // LSR zp
                            `LSR_A(8'h4A)             // LSR a
`ADDR_abs(8'h4E,`Tn)        `LSR_MEM(8'h4E, 4, 5)     // LSR abs
`ADDR_zp_x(8'h56,`Tn)       `LSR_MEM(8'h56, 4, 5)     // LSR zp,x
`ADDR_abs_x(8'h5E,`Tn,`Tn)  `LSR_MEM(8'h5E, 5, 6)     // LSR abs,x

`ADDR_zp(8'h66,`Tn)         `ROR_MEM(8'h66, 3, 4)     // ROR zp
                            `ROR_A(8'h6A)             // ROR a
`ADDR_abs(8'h6E,`Tn)        `ROR_MEM(8'h6E, 4, 5)     // ROR abs
`ADDR_zp_x(8'h76,`Tn)       `ROR_MEM(8'h76, 4, 5)     // ROR zp,x
`ADDR_abs_x(8'h7E,`Tn,`Tn)  `ROR_MEM(8'h7E, 5, 6)     // ROR abs,x

                            `FLAG_OP(8'h18, `FLAGS_C) // CLC
                            `FLAG_OP(8'h38, `FLAGS_C) // SEC
                            `FLAG_OP(8'h58, `FLAGS_I) // CLI
                            `FLAG_OP(8'h78, `FLAGS_I) // SEI
                            `FLAG_OP(8'hB8, `FLAGS_V) // CLV
                            `FLAG_OP(8'hD8, `FLAGS_D) // CLD
                            `FLAG_OP(8'hF8, `FLAGS_D) // SED

                            `Txx(8'h8A, `SB_X,  `LOAD_A, `FLAGS_SBZN)  // TXA
                            `Txx(8'h98, `SB_Y,  `LOAD_A, `FLAGS_SBZN)  // TYA
                            `Txx(8'h9A, `SB_X,  `LOAD_S, `none)        // TXS
                            `Txx(8'hA8, `SB_A,  `LOAD_Y, `FLAGS_SBZN)  // TAY
                            `Txx(8'hAA, `SB_A,  `LOAD_X, `FLAGS_SBZN)  // TAX
                            `Txx(8'hBA, `SB_S, `LOAD_X, `FLAGS_SBZN)  // TSX

                            `DEC_REG(8'h88, `SB_Y, `LOAD_Y) // DEY
                            `DEC_REG(8'hCA, `SB_X, `LOAD_X) // DEX
                            `INC_REG(8'hC8, `SB_Y, `LOAD_Y) // INY
                            `INC_REG(8'hE8, `SB_X, `LOAD_X) // INX

`ADDR_zp(8'hC6,`Tn)         `DEC_MEM(8'hC6, 3, 4)     // DEC zp
`ADDR_abs(8'hCE,`Tn)        `DEC_MEM(8'hCE, 4, 5)     // DEC abs
`ADDR_zp_x(8'hD6,`Tn)       `DEC_MEM(8'hD6, 4, 5)     // DEC zp,x
`ADDR_abs_x(8'hDE,`Tn,`Tn)  `DEC_MEM(8'hDE, 5, 6)     // DEC abs,x

`ADDR_zp(8'hE6,`Tn)         `INC_MEM(8'hE6, 3, 4)     // INC zp
`ADDR_abs(8'hEE,`Tn)        `INC_MEM(8'hEE, 4, 5)     // INC abs
`ADDR_zp_x(8'hF6,`Tn)       `INC_MEM(8'hF6, 4, 5)     // INC zp,x
`ADDR_abs_x(8'hFE,`Tn,`Tn)  `INC_MEM(8'hFE, 5, 6)     // INC abs,x

                            `PUSH(8'h08, `DB_P, `SB_FF)           // PHP
                            `PUSH(8'h48, `DB_A, `SB_FF)           // PHA
                            `PULL(8'h28, `none,   `FLAGS_DB)    // PLP
                            `PULL(8'h68, `LOAD_A, `FLAGS_SBZN)  // PLA

                            `JSR(8'h20)       // JSR
                            `RTS(8'h60)       // RTS
                            `RTI(8'h40)       // RTI
                            `JMP(8'h4C, 2)    // JMP abs
`ADDR_jmp_abs(8'h6C)        `JMP(8'h6C, 4)    // JMP (abs)

                            `NOP1_2(8'hEA)      // NOP

                            // "Standard" CMOS Extensions
`ifdef CMOS
                            `BRA(8'h80,`Tn)  // BRA

                            `PUSH(8'hDA, `DB_SB, `SB_X)           // PHX
                            `PUSH(8'h5A, `DB_SB, `SB_Y)           // PHY
                            `PULL(8'hFA, `LOAD_X, `FLAGS_SBZN)    // PLX
                            `PULL(8'h7A, `LOAD_Y, `FLAGS_SBZN)    // PLY
                            
`ADDR_jmp_abs_x(8'h7C)      `JMP(8'h7C, 5)    // JMP (abs,x)
                            
                            `DEC_REG(8'h3A, `SB_A, `LOAD_A) // DEC
                            `INC_REG(8'h1A, `SB_A, `LOAD_A) // INC
                            
                            // (zp)
`ADDR_zp_ind(8'h12)         `ORA(8'h12,0)
`ADDR_zp_ind(8'h32)         `AND(8'h32,0)
`ADDR_zp_ind(8'h52)         `EOR(8'h52,0)
`ADDR_zp_ind(8'h72)         `ADC(8'h72,0)
`ADDR_zp_ind_w(8'h92, `DB_SB, `SB_A)         `STx(8'h92)
`ADDR_zp_ind(8'hB2)         `LDA(8'hB2,0)
`ADDR_zp_ind(8'hD2)         `CMP(8'hD2,0)
`ADDR_zp_ind(8'hF2)         `SBC(8'hF2,0)

                            // STZ
`ADDR_zp_w(8'h64,`T0, `DB_0, `SB_FF)         `STx(8'h64)       // STZ zp
`ADDR_zp_x_w(8'h74,`T0, `DB_0, `SB_FF)       `STx(8'h74)       // STZ zp,x
`ADDR_abs_w(8'h9C,`T0, `DB_0, `SB_FF)        `STx(8'h9C)       // STZ abs
`ADDR_abs_x_w(8'h9E,`TNC,`T0, `DB_0, `SB_FF) `STx(8'h9E)       // STZ abs,x

                            `BIT(8'h89, `none, 1)           // BIT #
`ADDR_zp_x(8'h34,`T0)       `BIT(8'h34,`FLAGS_BIT, 0)       // BIT zp,x
`ADDR_abs_x(8'h3C,`TNC,`T0) `BIT(8'h3C,`FLAGS_BIT, 0)       // BIT abs,x

`ADDR_zp(8'h14,`Tn)         `TRB(8'h14, 3, 4)     // TRB zp
`ADDR_abs(8'h1C,`Tn)        `TRB(8'h1C, 4, 5)     // TRB abs

`ADDR_zp(8'h04,`Tn)         `TSB(8'h04, 3, 4)     // TSB zp
`ADDR_abs(8'h0C,`Tn)        `TSB(8'h0C, 4, 5)     // TSB abs

                            // WDC65C02 and Rockwell extensions
`ADDR_zp(8'h07,`Tn)         `RMB(8'h07, 3, 4)     // RMB0 zp
`ADDR_zp(8'h17,`Tn)         `RMB(8'h17, 3, 4)     // RMB1 zp
`ADDR_zp(8'h27,`Tn)         `RMB(8'h27, 3, 4)     // RMB2 zp
`ADDR_zp(8'h37,`Tn)         `RMB(8'h37, 3, 4)     // RMB3 zp
`ADDR_zp(8'h47,`Tn)         `RMB(8'h47, 3, 4)     // RMB4 zp
`ADDR_zp(8'h57,`Tn)         `RMB(8'h57, 3, 4)     // RMB5 zp
`ADDR_zp(8'h67,`Tn)         `RMB(8'h67, 3, 4)     // RMB6 zp
`ADDR_zp(8'h77,`Tn)         `RMB(8'h77, 3, 4)     // RMB7 zp

`ADDR_zp(8'h87,`Tn)         `SMB(8'h87, 3, 4)     // SMB0 zp
`ADDR_zp(8'h97,`Tn)         `SMB(8'h97, 3, 4)     // SMB1 zp
`ADDR_zp(8'hA7,`Tn)         `SMB(8'hA7, 3, 4)     // SMB2 zp
`ADDR_zp(8'hB7,`Tn)         `SMB(8'hB7, 3, 4)     // SMB3 zp
`ADDR_zp(8'hC7,`Tn)         `SMB(8'hC7, 3, 4)     // SMB4 zp
`ADDR_zp(8'hD7,`Tn)         `SMB(8'hD7, 3, 4)     // SMB5 zp
`ADDR_zp(8'hE7,`Tn)         `SMB(8'hE7, 3, 4)     // SMB6 zp
`ADDR_zp(8'hF7,`Tn)         `SMB(8'hF7, 3, 4)     // SMB7 zp

                            `BBR(8'h0F)   // BBR 0
                            `BBR(8'h1F)   // BBR 0
                            `BBR(8'h2F)   // BBR 0
                            `BBR(8'h3F)   // BBR 0
                            `BBR(8'h4F)   // BBR 0
                            `BBR(8'h5F)   // BBR 0
                            `BBR(8'h6F)   // BBR 0
                            `BBR(8'h7F)   // BBR 0
                            `BBS(8'h8F)   // BBR 0
                            `BBS(8'h9F)   // BBR 0
                            `BBS(8'hAF)   // BBR 0
                            `BBS(8'hBF)   // BBR 0
                            `BBS(8'hCF)   // BBR 0
                            `BBS(8'hDF)   // BBR 0
                            `BBS(8'hEF)   // BBR 0
                            `BBS(8'hFF)   // BBR 0

                            // Various flavors of CMOS NOPs
                            `NOP2_2(8'h02)
                            `NOP2_2(8'h22)
                            `NOP2_2(8'h42)
                            `NOP2_2(8'h62)
                            `NOP2_2(8'h82)
                            `NOP2_2(8'hC2)
                            `NOP2_2(8'hE2)

                            `NOP2_3(8'h44)
                            `NOP2_4(8'h54)
                            `NOP2_4(8'hD4)
                            `NOP2_4(8'hF4)
                            
                            `NOP1_1(8'h03)
                            `NOP1_1(8'h13)
                            `NOP1_1(8'h23)
                            `NOP1_1(8'h33)
                            `NOP1_1(8'h43)
                            `NOP1_1(8'h53)
                            `NOP1_1(8'h63)
                            `NOP1_1(8'h73)
                            `NOP1_1(8'h83)
                            `NOP1_1(8'h93)
                            `NOP1_1(8'hA3)
                            `NOP1_1(8'hB3)
                            `NOP1_1(8'hC3)
                            `NOP1_1(8'hD3)
                            `NOP1_1(8'hE3)
                            `NOP1_1(8'hF3)

                            `NOP1_1(8'h0B)
                            `NOP1_1(8'h1B)
                            `NOP1_1(8'h2B)
                            `NOP1_1(8'h3B)
                            `NOP1_1(8'h4B)
                            `NOP1_1(8'h5B)
                            `NOP1_1(8'h6B)
                            `NOP1_1(8'h7B)
                            `NOP1_1(8'h8B)
                            `NOP1_1(8'h9B)
                            `NOP1_1(8'hAB)
                            `NOP1_1(8'hBB)
                            `NOP1_1(8'hCB)
                            `NOP1_1(8'hDB)
                            `NOP1_1(8'hEB)
                            `NOP1_1(8'hFB)
                            
                            `NOP3_8(8'h5C)
                            `NOP3_4(8'hDC)
                            `NOP3_4(8'hFC)
                            
`endif
end

// microcode outputs wired to specific bits
assign tnext = mc_out[`TNEXT_BITS];
assign adh_sel= mc_out[`ADH_BITS];
assign adl_sel= mc_out[`ADL_BITS];
assign db_sel = mc_out[`DB_BITS];
assign sb_sel = mc_out[`SB_BITS];
assign alu_a = mc_out[`ALU_A_BITS];
assign alu_b = mc_out[`ALU_B_BITS];
assign alu_op = mc_out[`ALU_BITS];
assign alu_c = mc_out[`ALU_C_BITS];
assign load_a = mc_out[`LOAD_A_BITS];
assign load_x = mc_out[`LOAD_X_BITS];
assign load_y = mc_out[`LOAD_Y_BITS];
assign load_s = mc_out[`LOAD_S_BITS];
assign load_abh = mc_out[`LOAD_ABH_BITS];
assign load_abl = mc_out[`LOAD_ABL_BITS];
assign load_flags = mc_out[`LOAD_FLAGS_BITS];
assign write_cycle = mc_out[`WRITE_BITS];
assign pc_inc = mc_out[`PC_INC_BITS];
assign pchs_sel = mc_out[`PCHS_BITS];
assign pcls_sel = mc_out[`PCLS_BITS];

always @(posedge clk)
begin
  if(ready)
    mc_out <= mc[{ir, t}];
  //$display("mc[%02x|%d] tn: %04x",ir,t,mc[{ir, t}][`TNEXT_BITS]);
end

endmodule