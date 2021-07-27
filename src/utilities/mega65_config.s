;===============================================================================
;M65 Configuration Utility
;-------------------------
;
;Version 00.99D beta
;
;Written by Daniel England for the MEGA65 project.
;
;The mouse driver was cobbled together from the example in the 1351 Programmer's
;Reference Guide and the ca65/cc65 example driver, modified for our purposes.
;
;A small portion of the C64 Kernal's reset routines have been copied and 
;utilised.
;
;===============================================================================


;-------------------------------------------------------------------------------
;Defines
;-------------------------------------------------------------------------------
;	I'm enabling "leading_dot_in_identifiers" because I prefer to use a 
;	leading '.' in data definitions and I'm using a macro for them.
;
;	I'm enabling "loose_string_term" because I don't see a way of defining
;	a string with a double quote in it without it.

	.feature	leading_dot_in_identifiers, loose_string_term

	.macro 	.defPStr Arg
	.byte  	.strlen(Arg), Arg
	.endmacro
	
;	Set this define to 1 to run in "C64 mode" (uses the Kernal and will run
;	on a C64, using only C64 features).  Set to 0 to run in "M65 mode" 
;	(doesn't use Kernal, uses M65 features).  This is for the sake of 
;	debugging.
	.define		C64_MODE	0
	
;	Set this to use certain other debugging features
	.define		DEBUG_MODE	0
	
	.if		C64_MODE
	.setcpu	"6502"
	.else
	.setcpu		"4510"
	.endif
	
	.macro	LDA_HYPERIO
	.if	.not C64_MODE
		LDA	(ptrTempData), Y
	.else
		LDA	#$00
	.endif
	.endmacro
	
	.macro	STA_HYPERIO
	.if	.not C64_MODE
		STA	(ptrTempData), Y
	.endif
	.endmacro
	
		
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;Constants
;-------------------------------------------------------------------------------
optLineOffs	=	$04
;optLineMaxC	=	(25 - optLineOffs - 2)
optLineMaxC	=	(25 - 5)
tabMaxCount	=	$06			;count - 1

tabSaveIdx  =	$05
tabHelpIdx	=	$06


optDfltBase	=	$C000
optSessBase	=	$C200


	.if	C64_MODE
IIRQ   	=	$0314
	.else
IIRQ   	=	$FFFE
	.endif

VIC		=	$D000	   		; VIC REGISTERS
SID		=	$D400	   		; SID REGISTERS
SID_ADConv1   	=	SID + $19
SID_ADConv2   	=	SID + $1A

spriteMemD	=	$0340
spritePtr0	=	$07F8
vicSprClr0	=	$D027
vicSprEnab	=	$D015


CIA1_DDRA	=	$DC02
CIA1_DDRB	=	$DC03
CIA1_PRB	=	$DC01

offsX		=	24
offsY		=	50
buttonLeft	=	$10
buttonRight	=	$01


;
VICXPOS   	=	VIC + $00			; LOW ORDER X POSITION
VICYPOS   	=	VIC + $01			; Y POSITION
VICXPOSMSB	=	VIC + $10			; BIT 0 IS HIGH ORDER X POSITION


	.if	C64_MODE
keyF1		=	$85
keyF2		=	$89
keyF3		=	$86
keyF4		=	$8A
keyF5		=	$87
keyF6		=	$8B
keyF7		=	$88
keyF8		=	$8C
	.else
keyF1		=	$F1
keyF2		=	$F2
keyF3		=	$F3
keyF4		=	$F4
keyF5		=	$F5
keyF6		=	$F6
keyF7		=	$F7
keyF8		=	$F8
keyF9		=	$F9
;keyF10		=	$FA			;Doesn't work?
keyHELP		= $1F
	.endif

;Corporate
;CLR_CTLTXT =	$00
;CLR_BCKGND	=	$06
;CLR_HIGHLT	=	$01
;CLR_CTRLFC	=	$0F
;CLR_INACTV	=	$0E
;HDR_COLORS	=	$01

;Familiar
;CLR_CTLTXT =	$00
;CLR_BCKGND	=	$0E
;CLR_HIGHLT	=	$01
;CLR_CTRLFC	=	$0F
;CLR_INACTV	=	$04
;HDR_COLORS	=	$00

;Traditional
;CLR_CTLTXT =	$06
;CLR_BCKGND	=	$0E
;CLR_HIGHLT	=	$01
;CLR_CTRLFC	=	$0F
;CLR_INACTV	=	$03
;HDR_COLORS	=	$00

;Slate
;CLR_CTLTXT =	$00
;CLR_BCKGND	=	$0B
;CLR_HIGHLT	=	$01
;CLR_CTRLFC	=	$0F
;CLR_INACTV	=	$0C
;HDR_COLORS	=	$00


;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;ZPage storage
;-------------------------------------------------------------------------------
ptrCurrOpts	=	$40			;Might be able to be non-ZP
selectedOpt	=	$42			;Might be able to be non-ZP
optTempLine	=	$43			;Might be able to be non-ZP
optTempIndx	=	$44			;Might be able to be non-ZP
tabSelected	=	$45			;Might be able to be non-ZP
saveSlctOpt	=	$46			;Might be able to be non-ZP
progTermint	=	$47			;Might be able to be non-ZP
pgeSelected	=	$48			;Might be able to be non-ZP
currPageCnt	=	$49			;Might be able to be non-ZP

ptrTempData	=	$A5
crsrIsDispl	=	$A7			;Might be able to be non-ZP
ptrCrsrSPos	=	$A8			
ptrNextInsP	=	$AA
currTextLen	=	$AC			;Might be able to be non-ZP
currTextMax	=	$AD			;Might be able to be non-ZP
ptrIRQTemp0	=	$AE
ptrPageIndx	=	$B0
currMACByte	=	$B2			;Might be able to be non-ZP
currMACNybb	=	$B3			;Might be able to be non-ZP

zp32		=	$F7	; 32-bit pointer for far memory access
	
ptrOptsTemp	=	$FB
ptrCurrHeap	=	$FD
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;BASIC interface 
;-------------------------------------------------------------------------------
	.code
	.org		$07FF			;start 2 before load address so
						;we can inject it into the binary
						
	.byte		$01, $08		;load address
	
	.word		_basNext, $000A		;BASIC next addr and this line #
	.byte		$9E			;SYS command
	.asciiz		"2061"			;2061 and line end
_basNext:
	.word		$0000			;BASIC prog terminator
	.assert	    * = $080D, error, "BASIC Loader incorrect!"
bootstrap:
		JMP	init
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;Global data
;-------------------------------------------------------------------------------
;signature for utility menu
	.asciiz	"PROP.M65U.NAME=CONFIGURE MEGA65"
	

themeColours:
;CorpNeuvue
	.byte	$01, $06, $0E, $0C, $04, $01, $00, $00
;Familiar
	.byte	$00, $0E, $01, $0F, $04, $00, $00, $00
;Traditional
	.byte	$06, $0E, $01, $0F, $03, $00, $00, $00
;Slate
	.byte	$00, $0B, $01, $0F, $0C, $00, $00, $00
;Termnal
	.byte	$01, $05, $00, $0F, $03, $01, $00, $00

CNT_THEMES = 5

themeIndex:
	.byte	$FF

clr_ctltxt:
	.byte	$00
clr_bckgnd:
	.byte	$0E
clr_highlt:
	.byte	$01
clr_ctrlfc:
	.byte	$0F
clr_inactv:
	.byte	$04
hdr_colors:
	.byte	$00

headerLine:
	.byte		"          mega65 configuration          "

headerColours0:
	.byte		$06, $06, $05, $05, $07, $07, $02, $02
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$02, $02, $07, $07, $05, $05, $06, $06
headerColours1:
	.byte		$0E, $0E, $0D, $0D, $07, $07, $0A, $0A
	.byte		$0C, $0C, $0C, $0C, $0C, $0C, $0C, $0C
	.byte		$0C, $0C, $0C, $0C, $0C, $0C, $0C, $0C
	.byte		$0C, $0C, $0C, $0C, $0C, $0C, $0C, $0C
	.byte		$0A, $0A, $07, $07, $0D, $0D, $0E, $0E

menuLine:
	.byte		"inputBchipsetBvideoBaudioBnetwork  Bdone"
footerLine:
	.byte		"                                page  / "

infoText0:
	.byte		": version 00.99d beta     :"
infoText1:
	.if	C64_MODE
	.byte		": press f8 for help       :"
	.else
	.byte		": press help for help     :"
	.endif
infoText2:
	.byte		": f7 - save and exit opts :"

count_infoTexts = 3

infoTexts:
	.word		infoText0, infoText1, infoText2

currInfoTxt:
	.byte		$00

saveConfExit0:
	  .defPStr	   "are you sure you wish to exit"
saveConfExit1:
	  .defPStr	   "without saving?"

;saveConfAppl0:
;	  .defPStr	   "are you sure you wish to apply"
;saveConfAppl1:
;	  .defPStr	   "the current settings?"

saveConfOnBoard0:
	.defPStr		"without saving and reboot to"
saveConfOnBoard1:
	.defPStr		"the onboarding utility?"


saveConfSave0:
	.defPStr	"are you sure you wish to save"
saveConfFactory0:
	  .defPStr	   "the factory defaults and continue?"
saveConfDflt0:
	.defPStr	"as the defaults and exit?"
	
saveConfRest0:
	.defPStr	   "reset your machine now"

errorLine:
	.byte		"config data corrupt. press f14 to reset."


helpText0:
	.defPStr	"mega65 configuration help page!"
	
helpText1:
	.defPStr	"to navigate the tabbed categories, use"
helpText2:
	.defPStr	"f1/f3 or crsr left/right."
helpText4:
	.defPStr	"each tab has pages that have options."

helpText5:
	.defPStr	"using the crsr up/down keys, toggle or"
helpText6:
	.defPStr	"select options using the space or"
helpText7:
	.defPStr	"return keys."
	
helpText8:
	.defPStr	"you may also use the mouse to click"
helpText9:
	.defPStr	"tabs, options or pages."
	
helpTextA:
	.defPStr	"some options require data entry. use"
helpTextB:
	.defPStr	"the appropriate keys to complete."
	
helpTextC:
	.defPStr	"when done, save or exit with f7"
	
helpTextD:
	.defPStr	""
	

helpTexts:
	.word	helpText0, helpTextD, helpText1, helpText2
	.word	helpText4, helpTextD, helpText5, helpText6, helpText7
	.word	helpTextD, helpText8, helpText9, helpTextD, helpTextA
	.word	helpTextB, helpTextD, helpTextC
	.byte	$00


;	This will tell us whats happening on each line so we can use quick 
;	look-ups for the mouse etc.  Only optLineMaxC of the lines on the 
;	screen can be used (see above).  This will need to be adhered to by
;	the options lists!
pageOptions:
	.repeat		optLineMaxC + 1; +1 for a guard byte
	.byte		$FF
	.endrep
	
	
helpLastTab:
	.byte	$00
helpLastPage:
	.byte	$00
	

	.include	"mega65_config.inc"


;-------------------------------------------------------------------------------
init:
;-------------------------------------------------------------------------------
;	Init screen
		LDA	clr_bckgnd			;Border colour
		STA	$D020
		
		LDA	clr_ctltxt			;Screen colour
		STA	$D021

		LDA	#$14				;Set screen address to $0400, upper-case font
		STA	$D018
	
	.if	C64_MODE
;	Upper-case
		LDA	#$8E				;Print to-upper-case character
		JSR	$FFD2
		LDA	#$08				;Disable change of case
		JSR	$FFD2
	.endif
	
		SEI						;disable the interrupts
	
		JSR	initState
		
		JSR	themeNext
		
	.if	.not DEBUG_MODE
	.if	.not C64_MODE
;		JSR	checkSanity
		JSR	hypervisorLoadOrResetConfig
		JSR	checkMagicBytes
	.endif
	.endif
		
		JSR	initMouse
		
		CLI				;enable the interrupts
		
		LDA	#$00
		STA	tabSelected
		STA	progTermint
		
		LDA	#$00
		STA	mouseLastY
		STA	mouseLastY + 1
		STA	mouseYRow
		
		JSR	readDefaultOpts

		JSR	setupSelectedTab
		
;-------------------------------------------------------------------------------
main:
;-------------------------------------------------------------------------------
		JSR	displayOptionsPage

@inputLoop:
		LDA	progTermint
		BEQ	@cont
		
@halt:
		JMP	@halt

@cont:
		JSR	hotTrackMouse

		LDA	ButtonLClick
		BEQ	@tstKeys
		
		JSR	processMouseClick
		JMP	@inputLoop

@tstKeys:
	.if	C64_MODE
		JSR	$FFE4			;call get character from input
		BEQ	@inputLoop
	.else
		LDA	$D610
		BEQ	@inputLoop
		
		LDX	#$00
		STX	$D610
	.endif
		
@tstthemekey:
	.if	C64_MODE
		CMP	#$54
	.else
		CMP	#keyF8
	.endif
		BNE	@tstDownKey
		
		JSR	themeNext
		JSR	displayOptionsPage
		
		JMP	@inputLoop
		
@tstDownKey:
		CMP	#$11
		BNE	@tstUpKey
		
		JSR	moveSelectDown
		JMP	@inputLoop
		
@tstUpKey:
		CMP	#$91
		BNE	@tstF3Key
		
		JSR	moveSelectUp
		JMP	@inputLoop
				
@tstF3Key:
		CMP	#$1D
		BEQ	@doMoveTabLeft
		CMP	#keyF3
		BNE	@tstF1Key
@doMoveTabLeft:	
		JSR	moveTabLeft
		JMP	main
				
@tstF1Key:
		CMP	#$9D
		BEQ	@doMoveTabRight
		CMP	#keyF1
		BNE	@tstF2Key
@doMoveTabRight:
		JSR	moveTabRight
		JMP	main
		
@tstF4Key:
		CMP	#keyF4
		BNE	@tstF2Key
		
		JSR	moveNextPage
		JMP	main
		
@tstF2Key:
		CMP	#keyF2
		BNE	@tstF7Key
		
		JSR	movePriorPage
		JMP	main
		
@tstF7Key:
		CMP	#keyF7
		BNE	@tstHelpKey
		
		LDA	#tabSaveIdx
		STA	tabSelected
		JSR	setupSelectedTab
		
		JMP	main
		
@tstHelpKey:
	.if .not C64_MODE
		CMP	#keyHELP
	.else
		CMP	#keyF8
	.endif
		BNE	@otherKey

		LDA	tabSelected
		CMP	#tabHelpIdx
		BNE	@doHelp
		
		JMP	@inputLoop

@doHelp:
		LDA	tabSelected
		STA	helpLastTab
		
		LDA	pgeSelected
		STA	helpLastPage

		LDA	#tabHelpIdx
		STA	tabSelected
		JSR	setupSelectedTab
		
		JMP	main
		
@otherKey:
	.if	DEBUG_MODE
		STA	$0401
	.endif

		LDX	crsrIsDispl
		BEQ	@tstSaveTab
		
		JSR	doTestDataInput
		JMP	@inputLoop
		
@tstSaveTab:
		LDX	tabSelected
		CPX	#tabSaveIdx
		BNE	@tstHelpTab
		
		JSR	doTestSaveKeys
		JMP	@inputLoop
		
@tstHelpTab:
		CPX	#tabHelpIdx
		BNE	@toggleInput
		
		JSR	doTestHelpKeys
		JMP	@inputLoop
		
@toggleInput:
		JSR	doTestToggleKeys
		JMP	@inputLoop


;-------------------------------------------------------------------------------
themeNext:
;-------------------------------------------------------------------------------
		LDX	themeIndex
		INX
		CPX	#CNT_THEMES
		BNE	@cont
		
		LDX #$00
		
@cont:
		STX themeIndex
		TXA
		
		ASL
		ASL
		ASL
		
		TAX
		
		LDA	themeColours, X
		STA	clr_ctltxt
		
		LDA	themeColours + 1, X
		STA	clr_bckgnd
		
		LDA	themeColours + 2, X
		STA	clr_highlt

		LDA	themeColours + 3, X
		STA	clr_ctrlfc

		LDA	themeColours + 4, X
		STA	clr_inactv

		LDA	themeColours + 5, X
		STA	hdr_colors
		
		LDA	clr_bckgnd			;Border colour
		STA	$D020
		
		LDA	clr_ctltxt			;Screen colour
		STA	$D021
		
		RTS

;-------------------------------------------------------------------------------
littleDelay:
;-------------------------------------------------------------------------------
		; add a slight delay
		LDX #$00
@inner1:
		LDY #$00
@inner2:
		DEY
		BNE @inner2

		DEX
		BNE @inner1
		RTS

;-------------------------------------------------------------------------------
copySessionOptionsToSectorBuffer:	
;-------------------------------------------------------------------------------
;; As the name suggests, simply copy the specified 512 bytes to the SD card
;; sector buffer, which is where the hypervisor expects options to be placed
    ; disable interrupts, just in-case they are interfering
		SEI

		JMP littleDelay

		; check if this is a nexys4 board
		LDA $D629
		AND #$40  
		BEQ @notnexys

		; for nexys4 boards, use sd card bus 0
		LDA #$80
		STA $D680
		LDY #$00
		JMP @copyLoop

@notnexys:
		; for all other boards, use sd card bus 1
		LDA	#$81
		STA	$D680
		LDY	#$00
@copyLoop:	LDA	optSessBase, Y
		STA	$DE00, Y
		LDA	optSessBase+$100, Y
		STA	$DF00, Y
		DEY
		BNE	@copyLoop
		;; Set magic bytes
		LDA	#$01
		STA	$DE00
		STA	$DE01
		RTS
;-------------------------------------------------------------------------------
copyDefaultOptionsToSectorBuffer:	
;-------------------------------------------------------------------------------
;; As the name suggests, simply copy the specified 512 bytes to the SD card
;; sector buffer, which is where the hypervisor expects options to be placed
		LDA	#$81
		STA	$D680
		LDY	#$00
@copyLoop2:	
		LDA	optDfltBase, Y
		STA	$DE00, Y
		LDA	optDfltBase+$100, Y
		STA	$DF00, Y
		DEY
		BNE	@copyLoop2
		;; Set magic bytes
		LDA	#$01
		STA	$DE00
		STA	$DE01
		RTS

;-------------------------------------------------------------------------------
hypervisorApplyConfig:
;-------------------------------------------------------------------------------
;; Apply options in optSessBase
			JSR	copySessionOptionsToSectorBuffer
			LDA	#$04
			STA	$D642
			NOP
			RTS
	
;-------------------------------------------------------------------------------
hypervisorSaveConfig:
;-------------------------------------------------------------------------------
;; Save options in optSessBase
		JSR	copyDefaultOptionsToSectorBuffer
		LDA	#$02
		STA	$D642
		NOP
		RTS

	.if	.not C64_MODE
;-------------------------------------------------------------------------------
hypervisorLoadOrResetConfig:	
;-------------------------------------------------------------------------------
;;	 Load current options sector from SD card using Hypervisor trap		
		
;;	 Hypervisor trap to read config
		LDA	#$00
		STA	$D642
		NOP		; Required after hypervisor traps, as PC skips one
		
;;	 Copy from sector buffer to optDfltBase
		LDA	#$81
		STA	$D680
		LDX	#$00
@rl:		LDA	$DE00, X
		STA	optDfltBase, X
		LDA	$DF00, X
		STA	optDfltBase+$100, X
		INX
		BNE	@rl
;;	 Demap sector buffer when done
		LDA	#$82
		STA	$D680

;;; Work-around for retrieving Real-Time Clock values for editing
	jsr readRealTimeClock

;;	 Check for empty config
		LDA	optDfltBase+0
		ORA	optDfltBase+1
		BEQ	getDefaultSettings
		RTS

getDefaultSettings:
;;	 Empty config, so zero out and reset		
		LDA	#$00
		TAX
@rl2:		STA	optDfltBase, X
		STA	optDfltBase+$100,X
		DEX
		BNE	@rl2

;;	 Provide sensible initial values
		LDA	#$01  				 ; major and minor version
		STA	optDfltBase
		STA	optDfltBase+1

	;; MAC address
	;; Generate a random one
		LDX	#$05
@macrandom:	
		PHX
		JSR	getRandomByte
		PLX
		STA	optDfltBase+6, X
		STA	$D6E9, X
		DEX
		bpl @macrandom
		LDA	$DE06
		ORA	#$02	; Make "locally administered"
		AND	#$FE 	; Make unicast
		STA	$DE06
		STA	$D6E9

	jsr readRealTimeClock
	
		RTS

readRealTimeClock:	
	;; We insert them, as though they came from the config sector
	;; $FFD7110-5 has the real-time clock values on MEGA65R2
	;; XXX - Support MEGAphone as well
	lda #<$7110
	sta zp32+0
	lda #>$7110
	sta zp32+1
	lda #<$FFD
	sta zp32+2
	lda #>$FFD
	sta zp32+3
	LDZ #0
	NOP
	LDA (zp32),Z
	STA optDfltBase+$1f2	; seconds
	STA optSessBase+$1f2	; seconds
	sta rtc_values+$2
	INZ
	NOP
	LDA (zp32),Z
	STA optDfltBase+$1f1	; minutes
	STA optSessBase+$1f1	; minutes
	sta rtc_values+$1
	INZ
	NOP
	LDA (zp32),Z
	;; Hide bit7 which indicates 24 hour time
	and #$7f
	STA optDfltBase+$1f0		; hours
	STA optSessBase+$1f0		; hours
	sta rtc_values+$0
	INZ
	;; YY-MM-DD date, so neither the Americans nor Europeans can claim we are favouring the other
	NOP
	LDA (zp32),Z
	STA optDfltBase+$1f5	; day of month
	STA optSessBase+$1f5	; day of month
	sta rtc_values+$5
	INZ
	NOP
	LDA (zp32),Z
	STA optDfltBase+$1f4	; month of year
	STA optSessBase+$1f4	; month of year
	sta rtc_values+$4
	INZ
	NOP
	LDA (zp32),Z
	STA optDfltBase+$1f3	; year
	STA optSessBase+$1f3	; year
	sta rtc_values+$3
	LDZ #0

	RTS

	

	
getRandomByte:
	;; get parity of 256 reads of lowest bit of FPGA temperature
	;; for each bit. Then add to raster number.
	;; Should probably have more than enough entropy, even if the
	;; temperature is biased, as we are looking only at parity of
	;; a large number of reads.
	;; (Whether it is cryptographically secure is a separate issue.
	;; but it should be good enough for random MAC address generation).
		LDA #$00
		LDX #8
		LDY #0
@bitLoop:
		EOR $D6DE
		DEY
		BNE @bitLoop
	;; low bit into C
		LSR
	;; then into A
		ROR
		DEX
		BPL @bitLoop
		CLC
		ADC $D012

		RTS
	

;-------------------------------------------------------------------------------
checkSanity:
;-------------------------------------------------------------------------------
		RTS

		LDA	$D68C
		STA	ptrOptsTemp

		EOR	#$AA
		STA	$D68C

		LDA	$D68C
		CMP	ptrOptsTemp
		BNE	@exit

@loop:
		INC	$D020
		JMP	@loop

@exit:
		LDA	ptrOptsTemp
		STA	$D68C

		RTS


;-------------------------------------------------------------------------------
checkMagicBytes:
;-------------------------------------------------------------------------------
		LDA	optDfltBase + 1		;Major versions different, fail
		CMP	#configMagicByte1
		BNE	@fail
		
		LDA	#configMagicByte0	;Opts minor >= system minor, ok
		CMP	optDfltBase
		BCS	@exit
		
@fail:
		JSR	clearScreen
		
		LDX	#$27
@loop:
		LDA	errorLine, X
		JSR	asciiToCharROM
		ORA	#$80
		STA	$07C0, X
		DEX
		BPL	@loop

	;; PGS 20200405 - When this happens, offer to reset the config sector
	

	;; Wait until the user presses F14
@halt:
	lda $d610
	beq @halt
	cmp #$fe
	beq @repairSettings
	sta $d610
	
	JMP	@halt

	;; User pressed F14, so reset to default settings and continue
@repairSettings:
	;; Clear the read key
	sta $d610
	jsr getDefaultSettings
	
	
@exit:
		RTS
	.endif


;-------------------------------------------------------------------------------
readTemp0:
	.byte		$00
readTemp1:
	.byte		$00
readTemp2:
	.byte		$00
readTemp3:
	.byte		$00
	
ptrOptionBase0:
	.word		$0000
	
;-------------------------------------------------------------------------------
readDefaultOpts:
;-------------------------------------------------------------------------------
		LDA	#<optDfltBase
		STA	ptrOptionBase0
		LDA	#>optDfltBase
		STA	ptrOptionBase0 + 1

		LDX	#$00
@loopInput:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	inputPageIndex, X
		STA	ptrOptsTemp
		LDA	inputPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCC	@cont
		JMP	@error
		
@cont:
		LDX	readTemp3
		INX
		CPX	#inputPageCnt
		BNE	@loopInput
		

		LDX	#$00
@loopChipset:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	chipsetPageIndex, X
		STA	ptrOptsTemp
		LDA	chipsetPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#inputPageCnt
		BNE	@loopChipset


		LDX	#$00
@loopVideo:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	videoPageIndex, X
		STA	ptrOptsTemp
		LDA	videoPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#videoPageCnt
		BNE	@loopVideo
		
		
		LDX	#$00
@loopAudio:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	audioPageIndex, X
		STA	ptrOptsTemp
		LDA	audioPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#audioPageCnt
		BNE	@loopAudio

		LDX	#$00
@loopNetwork:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	networkPageIndex, X
		STA	ptrOptsTemp
		LDA	networkPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#networkPageCnt
		BNE	@loopNetwork
		
@exit:
		RTS

@error:
		LDA	#$02
		STA	$D020
		RTS


;-------------------------------------------------------------------------------
doReadOptList:
;-------------------------------------------------------------------------------
		LDY	#$00
	
@loop0:
		LDA	(ptrOptsTemp), Y
		CMP	#$00
		BEQ	@finish
	
		JSR	doReadOpt
		BCS	@error

		JMP	@loop0

@finish:
		CLC
		RTS
		
@error:
		SEC
		RTS


;-------------------------------------------------------------------------------
doReadOpt:
;-------------------------------------------------------------------------------
		STY	readTemp0
		
		AND	#$F0
		CMP	#$10
		BNE	@tstToggOpt
		
		INY			
		INC	readTemp0
		INC	readTemp0
		CLC
		LDA	readTemp0
		ADC	(ptrOptsTemp), Y
		TAY
		
		CLC
		RTS

@tstToggOpt:
		CMP	#$20
		BNE	@tstStrOpt
	
		INY
		JSR	setOptBasePtr
		
		TYA
		PHA
		LDY	#$00
;		LDA	(ptrTempData), Y
		
		LDA_HYPERIO
		
		STA	readTemp1
		PLA
		TAY
		LDA	(ptrOptsTemp), Y
		
		AND	readTemp1
		BNE	@setToggOpt
		
		STY	readTemp1
		LDA	#$20

		JMP	@contTogg
	
@setToggOpt:		
		STY	readTemp1
		LDA	#$21

@contTogg:
		LDY	readTemp0
		STA	(ptrOptsTemp), Y
		
		LDY	readTemp1
		INY
		JSR	doSkipString
		JSR	doSkipString
		JSR	doSkipString

		CLC
		RTS
		
@tstStrOpt:
		CMP	#$30
		BNE	@tstBlankOpt
		
		INY
		JSR	setOptBasePtr

		LDA	(ptrOptsTemp), Y
		STA	readTemp1
		INY
		
		JSR	doSkipString
		
		STY	readTemp2
		
		LDA	#$00
		STA	readTemp0
		
		LDX	#$00
@loopStr:
		LDY	readTemp0

;		LDA	(ptrTempData), Y
		LDA_HYPERIO

		INC	readTemp0
		
		LDY	readTemp2
		STA	(ptrOptsTemp), Y
		INC	readTemp2
		
		INX
		CPX	readTemp1
		BNE	@loopStr
		
		LDY	readTemp2
	
		CLC
		RTS

@tstBlankOpt:
		CMP	#$40
		BNE	@tstMACOpt
		
		INY
		CLC
		RTS

@tstMACOpt:
		CMP	#$50
		BEQ	@isMACOpt
		CMP	#$60
		BNE	@unknownOpt
@isMACOpt:
	   
		INY
		JSR	setOptBasePtr

		JSR	doSkipString
		
		STY	readTemp2
		
		LDA	#$00
		STA	readTemp0
		
		LDX	#$00
@loopMAC:
		LDY	readTemp0

;		LDA	(ptrTempData), Y
		LDA_HYPERIO
		
		INC	readTemp0
		
		LDY	readTemp2
		STA	(ptrOptsTemp), Y
		INC	readTemp2
		
		INX
		CPX	#$06
		BNE	@loopMAC
		
		LDY	readTemp2
	
		CLC
		RTS
		
@unknownOpt:
		SEC
		RTS


;-------------------------------------------------------------------------------
setOptBasePtr:
;-------------------------------------------------------------------------------
		CLC
		LDA	(ptrOptsTemp), Y
		ADC	ptrOptionBase0
		STA	ptrTempData
		INY
		LDA	(ptrOptsTemp), Y
		ADC	ptrOptionBase0 + 1
		STA	ptrTempData + 1
		
		INY
		RTS

;-------------------------------------------------------------------------------
doSkipString:
;-------------------------------------------------------------------------------
		LDA	(ptrOptsTemp), Y
		STA	readTemp0
		INC	readTemp0
		TYA
		CLC
		ADC	readTemp0
		TAY
		RTS

;-------------------------------------------------------------------------------
saveSessionOpts:
;-------------------------------------------------------------------------------
		LDA	#<optSessBase
		STA	ptrOptionBase0
		LDA	#>optSessBase
		STA	ptrOptionBase0 + 1

		JSR	doSaveOptions
		
	.if	.not C64_MODE
		JSR	hypervisorApplyConfig
	.endif
		
		RTS


;-------------------------------------------------------------------------------
saveDefaultOpts:
;-------------------------------------------------------------------------------
		LDA	#<optDfltBase
		STA	ptrOptionBase0
		LDA	#>optDfltBase
		STA	ptrOptionBase0 + 1

		JSR	doSaveOptions

	.if	.not C64_MODE
		JSR	hypervisorSaveConfig
		JSR	hypervisorApplyConfig
	.endif
		
		RTS


;-------------------------------------------------------------------------------
saveExitToOnboard:
;-------------------------------------------------------------------------------
		CLC
		LDA	#<optDfltBase
		ADC	#$0E
		STA	ptrTempData
		LDA	#>optDfltBase
		ADC	#$00
		STA	ptrTempData + 1

		LDY	#$00
		LDA	(ptrTempData), Y
		AND	#$7F
		STA	(ptrTempData), Y


		CLC								;Why cant I just save the default ones?
		LDA	#<optSessBase
		ADC	#$0E
		STA	ptrTempData
		LDA	#>optSessBase
		ADC	#$00
		STA	ptrTempData + 1

		LDY	#$00
		LDA	(ptrTempData), Y
		AND	#$7F
		STA	(ptrTempData), Y

		JSR	hypervisorSaveConfig
;		JSR	hypervisorApplyConfig

;		LDA	#$7E
;		STA	$D640
;		NOP


		RTS

;-------------------------------------------------------------------------------
doSaveOptions:
;-------------------------------------------------------------------------------
		LDX	#$00
@loopInput:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	inputPageIndex, X
		STA	ptrOptsTemp
		LDA	inputPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCC	@cont
		JMP	@error
		
@cont:
		LDX	readTemp3
		INX
		CPX	#inputPageCnt
		BNE	@loopInput


		LDX	#$00
@loopChipset:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	chipsetPageIndex, X
		STA	ptrOptsTemp
		LDA	chipsetPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#chipsetPageCnt
		BNE	@loopChipset

		LDX	#$00
@loopVideo:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	videoPageIndex, X
		STA	ptrOptsTemp
		LDA	videoPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#videoPageCnt
		BNE	@loopVideo

		LDX	#$00
@loopAudio:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	audioPageIndex, X
		STA	ptrOptsTemp
		LDA	audioPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#audioPageCnt
		BNE	@loopAudio

		LDX	#$00
@loopNetwork:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	networkPageIndex, X
		STA	ptrOptsTemp
		LDA	networkPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#networkPageCnt
		BNE	@loopNetwork

@exit:
		RTS
@error:
		LDA	#$02
		STA	$D020
		RTS



;-------------------------------------------------------------------------------
doSaveOptList:
;-------------------------------------------------------------------------------
		LDY	#$00
	
@loop0:
		LDA	(ptrOptsTemp), Y
		CMP	#$00
		BEQ	@finish
	
		JSR	doSaveOpt
		BCS	@error

		JMP	@loop0

@finish:
		CLC
		RTS
		
@error:
		SEC
		RTS
		

;-------------------------------------------------------------------------------
doSaveOpt:
;-------------------------------------------------------------------------------
		STY	readTemp0
		
		AND	#$F0
		CMP	#$10
		BNE	@tstToggOpt
		
		INY			
		INC	readTemp0
		INC	readTemp0
		CLC
		LDA	readTemp0
		ADC	(ptrOptsTemp), Y
		TAY
		
		CLC
		RTS

@tstToggOpt:
		CMP	#$20
		BNE	@tstStrOpt
	
		INY
		JSR	setOptBasePtr
		
		TYA
		PHA
		LDY	#$00
		
;		LDA	(ptrTempData), Y
		LDA_HYPERIO

		STA	readTemp1		;current data in readTemp1
		
		PLA
		TAY
		LDA	(ptrOptsTemp), Y
		STA	readTemp2		;flags in readTemp2
		
		LDA	#$FF			;not flags
		EOR	readTemp2		
		
		AND	readTemp1		;remove flags from current data
		STA	readTemp1
		
		LDY	readTemp0		;get setting
		LDA	(ptrOptsTemp), Y
		AND	#$0F
		BEQ	@unSetTogg
		
		LDA	readTemp1		;include flags in current data
		ORA	readTemp2
		JMP	@contTogg
		
@unSetTogg:
		LDA	readTemp1		;get back current data without flags

@contTogg:
		LDY	#$00			;store in current data

;		STA	(ptrTempData), Y
		STA_HYPERIO

		LDY	readTemp0		;skip past type, offset and flags
		INY
		INY
		INY
		INY
		JSR	doSkipString
		JSR	doSkipString
		JSR	doSkipString

		CLC
		RTS
		
@tstStrOpt:
		CMP	#$30
		BNE	@tstBlankOpt
		
		INY
		JSR	setOptBasePtr

		LDA	(ptrOptsTemp), Y
		STA	readTemp1
		INY
		
		JSR	doSkipString
		
		STY	readTemp2
		
		LDA	#$00
		STA	readTemp0
		
		LDX	#$00
@loopStr:
		LDY	readTemp2
		LDA	(ptrOptsTemp), Y
		INC	readTemp2
		
		LDY	readTemp0
		
;		STA	(ptrTempData), Y
		STA_HYPERIO
		
		INC	readTemp0
		
		INX
		CPX	readTemp1
		BNE	@loopStr
		
		LDY	readTemp2
	
		CLC
		RTS

@tstBlankOpt:
		CMP	#$40
		BNE	@tstMACOpt
		
		INY
		CLC
		RTS
		
@tstMACOpt:
		CMP	#$50
		BEQ	@isMACOpt
		CMP	#$60
		BNE	@unknownOpt
@isMACOpt:
		
		INY
		JSR	setOptBasePtr

		JSR	doSkipString
		
		STY	readTemp2
		
		LDA	#$00
		STA	readTemp0
		
		LDX	#$00
@loopMAC:
		LDY	readTemp2
		LDA	(ptrOptsTemp), Y
		INC	readTemp2
		
		LDY	readTemp0

;		STA	(ptrTempData), Y
		STA_HYPERIO
		
		INC	readTemp0
		
		INX
		CPX	#$06
		BNE	@loopMAC
		
		LDY	readTemp2
	
		CLC
		RTS
		
		
@unknownOpt:
		SEC
		RTS
		
;-------------------------------------------------------------------------------
doJumpApplyNow:
;-------------------------------------------------------------------------------
		LDA	#tabSaveIdx
		STA	tabSelected
		LDA	#$02
		STA	saveSlctOpt
		LDA	#$01
		STA	pgeSelected

		LDA	#savePageCnt
		STA	currPageCnt

		LDA	#<savePageIndex
		STA	ptrPageIndx
		LDA	#>savePageIndex 
		STA	ptrPageIndx + 1

		RTS

	
;-------------------------------------------------------------------------------
doTestDataInput:
;-------------------------------------------------------------------------------
		PHA
		
		LDX	selectedOpt
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$30
		BEQ	@inputStr

		CMP	#$50
		BEQ	@doMacKeys
		
		CMP	#$60
		BNE	@exit
		
@doMacKeys:
		PLA
		JSR	doTestMACKeys
		RTS
		
@inputStr:
		PLA
		JSR	doTestStringKeys
		RTS
		
@exit:
		PLA
		RTS


;-------------------------------------------------------------------------------
doTestMACKeys:
;-------------------------------------------------------------------------------
		CMP	#$14
		BNE	@tstCharIn
		
		JSR	doDelMACChar
		RTS
		
@tstCharIn:
		TAX

		CMP	#$30
		BCC	@exit
		
		CMP	#$3A
		BCC	@acceptDigit
		
		CMP	#$61
		BCC	@exit
		
		CMP	#$67
		BCS	@exit
		
		SEC
		SBC	#$37
		JSR	doAppMACChar
		RTS
		
@acceptDigit:
		SEC
		SBC	#$30
		JSR	doAppMACChar
		RTS
	
@exit:
		RTS
		

;-------------------------------------------------------------------------------
doDelMACChar:
;-------------------------------------------------------------------------------
		LDA	currMACByte
		BNE	@cont
		LDA	currMACNybb
		BEQ	@exit
		
@cont:
		LDX	#$00
		STX	crsrIsDispl

		LDY	#$00
		LDA	(ptrCrsrSPos), Y
		ORA	#$80
		STA	(ptrCrsrSPos), Y

		LDA	currMACByte
		CMP	#$06
		BNE	@tstLow

		LDA	#$01
		STA	currMACNybb
		DEC	currMACByte

		SEC
		LDA	ptrNextInsP
		SBC	#$01	
		STA	ptrNextInsP
		LDA	ptrNextInsP + 1
		SBC	#$00
		STA	ptrNextInsP + 1

		SEC
		LDA	ptrCrsrSPos
		SBC	#$01
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		SBC	#$00
		STA	ptrCrsrSPos + 1

		LDX	#$01
		STX	crsrIsDispl
		RTS


@tstLow:
		LDA	currMACNybb
		BEQ	@isHigh
		
		LDA	#$00
		STA	currMACNybb
		
		SEC
		LDA	ptrCrsrSPos
		SBC	#$01
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		SBC	#$00
		STA	ptrCrsrSPos + 1

		LDX	#$01
		STX	crsrIsDispl
		RTS
		
@isHigh:
		DEC	currMACByte
		LDA	#$01
		STA	currMACNybb

		SEC
		LDA	ptrNextInsP
		SBC	#$01	
		STA	ptrNextInsP
		LDA	ptrNextInsP + 1
		SBC	#$00
		STA	ptrNextInsP + 1

		SEC
		LDA	ptrCrsrSPos
		SBC	#$02
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		SBC	#$00
		STA	ptrCrsrSPos + 1

		LDX	#$01
		STX	crsrIsDispl

@exit:
		RTS
		

;-------------------------------------------------------------------------------
doAppMACChar:
;-------------------------------------------------------------------------------
		STA	dispOptTemp0	
				
		LDA	currMACByte
		CMP	#$06
		BEQ	@exit
		
		LDY	#$00
		TXA	
	.if	C64_MODE
		JSR	inputToCharROM
	.else
		JSR	asciiToCharROM
	.endif
		ORA	#$80
		STA	(ptrCrsrSPos), Y

		LDA	currMACNybb
		BEQ	@isHigh
		
		JSR	doAppMACCharLow
		jmp	@exit
		
@isHigh:
		JSR	doAppMACCharHigh
		
@exit:
	;; HACK: For setting the real-time clock we do this as you type.
	lda tabSelected
	cmp #1
	bne notRTCTab

	.if	.not C64_MODE
	
	;;  Write-enable the clock
	ldz #8
	NOP
	LDA (zp32),z
	ora #$40
	NOP
	STA (zp32),z
	jsr i2cwait
	ldz #0
	lda rtc_values+2
	NOP
	STA (zp32),z
	jsr i2cwait
	INZ
	lda rtc_values+1
	NOP
	STA (zp32),z
	jsr i2cwait
	INZ
	lda rtc_values+0
	;; Always store RTC time in 24-hour format
	ora #$80
	NOP
	STA (zp32),z
	jsr i2cwait
	INZ
	lda rtc_values+5
	NOP
	STA (zp32),z
	jsr i2cwait
	INZ
	lda rtc_values+4
	NOP
	STA (zp32),z
	jsr i2cwait
	INZ
	lda rtc_values+3
	NOP
	STA (zp32),z
	jsr i2cwait
	;;  Write-protect the clock
	ldz #8
	NOP
	LDA (zp32),z
	and #$BF
	NOP
	STA (zp32),z
	LDZ #0	
	
	.endif
	
notRTCTab:		
		RTS

i2cwait:
	;; I2C peripherals can take a while for writes to get scheduled
@i2c1:	lda $d012
	cmp #$80
	bne @i2c1
@i2c2:	lda $d012
	cmp #$70
	bne @i2c2
	rts

;-------------------------------------------------------------------------------
doAppMACCharLow:
;-------------------------------------------------------------------------------
		LDX	#$00
		STX	crsrIsDispl
		
		LDY	#$00
		LDA	(ptrNextInsP), Y
		AND	#$F0
		ORA	dispOptTemp0
		STA	(ptrNextInsP), Y
		
		INC	currMACByte
		LDA	#$00
		STA	currMACNybb

		LDA	currMACByte
		CMP	#$06
		BEQ	@atEnd
		
		LDA	#$02
		STA	dispOptTemp0
		JMP	@cont
		
@atEnd:
		LDA	#$01
		STA	dispOptTemp0

@cont:
		CLC
		LDA	#$01
		ADC	ptrNextInsP
		STA	ptrNextInsP
		LDA	ptrNextInsP + 1
		ADC	#$00
		STA	ptrNextInsP + 1
		
		CLC
		LDA	dispOptTemp0
		ADC	ptrCrsrSPos
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		ADC	#$00
		STA	ptrCrsrSPos + 1
		
		LDX	#$01
		STX	crsrIsDispl
		
		RTS
		

;-------------------------------------------------------------------------------
doAppMACCharHigh:
;-------------------------------------------------------------------------------
		LDX	#$00
		STX	crsrIsDispl

		LDA	dispOptTemp0
		ASL
		ASL
		ASL
		ASL
		STA	dispOptTemp0

		LDY	#$00
		LDA	(ptrNextInsP), Y
		AND	#$0F
		ORA	dispOptTemp0
		STA	(ptrNextInsP), Y
		
		INC	currMACNybb
		
		CLC
		LDA	#$01
		ADC	ptrCrsrSPos
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		ADC	#$00
		STA	ptrCrsrSPos + 1
		
		LDX	#$01
		STX	crsrIsDispl
		
		RTS


;-------------------------------------------------------------------------------
doTestStringKeys:
;***fixme?
;	For file names want $20 to $5E but not $22, $24, $2A, $3A, $40.
;	This is not implemented!  Instead, just accept all from $20 to $7F.
;
;	Del is $14
;-------------------------------------------------------------------------------
		CMP	#$14
		BNE	@tstCharIn
		
		JSR	doDelStringChar
		RTS
		
@tstCharIn:
		CMP	#$20
		BCC	@exit
		
		CMP	#$80
		BCS	@exit
		
		JSR	doAppStringChar

@exit:
		RTS


;-------------------------------------------------------------------------------
doAppStringChar:
;-------------------------------------------------------------------------------
		LDX	currTextLen
		CPX	currTextMax
		BEQ	@exit
	
		LDX	#$00
		STX	crsrIsDispl
	
		LDY	#$00
		STA	(ptrNextInsP), Y
	
	.if	C64_MODE
		JSR	inputToCharROM
	.else
		JSR	asciiToCharROM
	.endif

		ORA	#$80
		LDY	#$00
		STA	(ptrCrsrSPos), Y

		INC	currTextLen
		
		CLC
		LDA	ptrNextInsP
		ADC	#$01
		STA	ptrNextInsP
		LDA	ptrNextInsP + 1
		ADC	#$00
		STA	ptrNextInsP + 1
		
		CLC
		LDA	ptrCrsrSPos
		ADC	#$01
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		ADC	#$00
		STA	ptrCrsrSPos + 1

		LDX	#$01
		STX	crsrIsDispl

@exit:
		RTS
		

;-------------------------------------------------------------------------------
doDelStringChar:
;-------------------------------------------------------------------------------
		LDX	currTextLen
		BEQ	@exit
	
		LDX	#$00
		STX	crsrIsDispl

		LDY	#$00
		LDA	#$A0
		STA	(ptrCrsrSPos), Y
		
		DEC	currTextLen
		
		SEC
		LDA	ptrNextInsP
		SBC	#$01
		STA	ptrNextInsP
		LDA	ptrNextInsP + 1
		SBC	#$00
		STA	ptrNextInsP + 1
		
		SEC
		LDA	ptrCrsrSPos
		SBC	#$01
		STA	ptrCrsrSPos
		LDA	ptrCrsrSPos + 1
		SBC	#$00
		STA	ptrCrsrSPos + 1

		LDA	#$00
		STA	(ptrNextInsP), Y
		
		LDA	#$A0
		STA	(ptrCrsrSPos), Y

		LDX	#$01
		STX	crsrIsDispl
		
@exit:
		RTS
		
		
;-------------------------------------------------------------------------------
doTestToggleKeys:
;	Want return $0D and space $20
;-------------------------------------------------------------------------------
		CMP	#$0D
		BEQ	@tstToggle
	
		CMP	#$20
		BNE	@exit

@tstToggle:
		LDX	selectedOpt
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$00
		BNE	@exit
		
		LDA	pageOptions, X
		AND	#$0F

		ASL				
		TAX

		LDA	heap0, X		;Get to the type/data
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		STA	ptrOptsTemp + 1		
		
		LDY	#$00
		LDA	(ptrOptsTemp), Y

		AND	#$0F
		EOR	#$01
		CLC
		ADC	#$01
		ASL
		ASL
		ASL
		ASL
		LDX	selectedOpt
		
		JSR	doToggleOption

@exit:
		RTS
	

;-------------------------------------------------------------------------------
doTestHelpKeys:
;-------------------------------------------------------------------------------
		CMP	#$0D
		BNE	@exit
		
		LDA	helpLastTab
		STA	tabSelected
		
		JSR	setupSelectedTab
		
		LDA	helpLastPage
		STA	pgeSelected
		
		JSR	displayOptionsPage
		
@exit:
		RTS

;-------------------------------------------------------------------------------
doTestSaveKeys:
;-------------------------------------------------------------------------------
		CMP	#$0D
		BNE	@exit
		
		JSR	doHandleSaveButton
		
@exit:
		RTS


;-------------------------------------------------------------------------------
doHandleSaveButton:
;-------------------------------------------------------------------------------
		LDX	pgeSelected
		CPX	#$00
		BEQ	@switchConfirm

		LDX	selectedOpt
		CPX	#$06
		BNE	@performSave

		JMP	@clear

@performSave:
		JSR	doPerformSaveAction

@clear:
		LDX	$FF
		STX	saveSlctOpt
		
		LDA	progTermint
		BNE	@switchReset
		
		LDX	#$00
		JMP	@update
		
@switchReset:
;; Hypervisor trap to reset machine
;		LDA	#$7E
;		STA	$D640
;		NOP

	.if	.not	C64_MODE
		JSR	reconfigReset
	.endif

		LDX	#$02
		JMP	@update
		
@switchConfirm:
		LDX	selectedOpt
		STX	saveSlctOpt
		
		LDX	#$01
		
@update:
		STX	pgeSelected	
		JSR	displayOptionsPage
		
@exit:
		RTS


;-------------------------------------------------------------------------------
usleep:
;***FIXME:  Should include .Y for 16 bit resolution.
;-------------------------------------------------------------------------------
@loop0:
		CMP	#$40
		BCC @exit

		LDX	$D012
@loop1:
		CPX	$D012
		BEQ	@loop1

		SEC
		SBC	#$40
		JMP	@loop0

@exit:
		RTS


;-------------------------------------------------------------------------------
reconfigReset:
;-------------------------------------------------------------------------------
		LDA	#$00				;Blank, black screen
		STA	$D020
		STA	$D011

		LDA	#$47				;M65 knock knock
		STA	$D02F
		LDA	#$53
		STA	$D02F
		LDA	#65
		STA	$00

		LDA	#$00				;Adress of reconfigure
		STA	$D6C8
		STA	$D6C9
		STA	$D6CA
		STA	$D6CB

@loop:
		LDA	#$FF				;Wait for ready
		JSR	usleep

		LDA	#$42				;Reconfigure (reset)
		STA	$D6CF

		JMP	@loop


;-------------------------------------------------------------------------------
doPerformSaveAction:
;-------------------------------------------------------------------------------
		LDX	saveSlctOpt			
		BNE	@tstFactorySys
		
		LDA	#$01					;Exit without saving
		STA	progTermint
		RTS

;@tstSaveApply:
;		CPX	#$02
;		BNE	@tstFactorySys
;		
;		JSR	saveSessionOpts			;Apply now
;		RTS
		
@tstFactorySys:
;		CPX	#$04
		CPX	#$02
;		BNE	@tstSaveSys
		BNE	@tstBootOnboard
		
	.if .not C64_MODE
		JSR	getDefaultSettings		;Restore defaults
		JSR	readDefaultOpts
	.endif
		
		RTS

@tstBootOnboard:
		CPX	#$04
		BNE	@tstSaveSys

	.if	.not	C64_MODE
		JSR	saveExitToOnboard
		LDA	#$01
		STA	progTermint
	.endif
		RTS
	
@tstSaveSys:		
		CPX	#$06
		BNE	@exit
		
		JSR	saveDefaultOpts
		JSR	saveSessionOpts
		LDA	#$01
		STA	progTermint

@exit:
		RTS

;-------------------------------------------------------------------------------
setupSelectedTab:
;-------------------------------------------------------------------------------
		LDA	#$FF
		STA	saveSlctOpt
		
		LDA	tabSelected
		CMP	#$00
		BNE	@tstDisk
		
		JSR	setupInputPage0
		RTS
		
@tstDisk:
		CMP	#$01
		BNE	@tstVideo
		
		JSR	setupChipsetPage0
		RTS
		
@tstVideo:
		CMP	#$02
		BNE	@tstAudio
		
		JSR	setupVideoPage0
		RTS
		
@tstAudio:
		CMP	#$03
		BNE	@tstNetwork
		
		JSR	setupAudioPage0
		RTS
		
@tstNetwork:
		CMP	#$04
		BNE	@tstSave
		
		JSR	setupNetworkPage0
		RTS
		
@tstSave:
		CMP	#$05
		BNE	@help
		
		JSR	setupSavePage0
		RTS
		
@help:
		JSR	setupHelpPage0
		RTS


;-------------------------------------------------------------------------------
highlightSelectedTab:
;-------------------------------------------------------------------------------
		LDA	tabSelected
		CMP	#$00
		BNE	@tstChipset
		
		JSR	highlightInputTab
		RTS
		
@tstChipset:
		CMP	#$01
		BNE	@tstVideo
		
		JSR	highlightChipsetTab
		RTS
		
@tstVideo:
		CMP	#$02
		BNE	@tstAudio
		
		JSR	highlightVideoTab
		RTS
		
@tstAudio:
		CMP	#$03
		BNE	@tstNetwork
		
		JSR	highlightAudioTab
		RTS
		
@tstNetwork:
		CMP	#$04
		BNE	@tstSave
		
		JSR	highlightNetworkTab
		RTS
		
@tstSave:
		CMP	#$05
		BNE	@help
		
		JSR	highlightSaveTab
		RTS
		
@help:
		RTS


;-------------------------------------------------------------------------------
setupInputPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#inputPageCnt
		STA	currPageCnt
		
		LDA	#<inputPageIndex
		STA	ptrPageIndx
		LDA	#>inputPageIndex
		STA	ptrPageIndx + 1
		
		RTS

;-------------------------------------------------------------------------------
highlightInputTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$00
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$06
		BNE	@loop

		RTS


;-------------------------------------------------------------------------------
setupChipsetPage0:
;-------------------------------------------------------------------------------
	.if .not C64_MODE
;;	Re-read RTC everytime we display a tab, so to give fresh time
		JSR readRealTimeClock
	.endif

		LDA	#$00
		STA	pgeSelected
		LDA	#chipsetPageCnt
		STA	currPageCnt
		
		LDA	#<chipsetPageIndex
		STA	ptrPageIndx
		LDA	#>chipsetPageIndex
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightChipsetTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$06
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$0E
		BNE	@loop
		
		RTS


;-------------------------------------------------------------------------------
setupVideoPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#videoPageCnt
		STA	currPageCnt
		
		LDA	#<videoPageIndex
		STA	ptrPageIndx
		LDA	#>videoPageIndex
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightVideoTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$0E
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$14
		BNE	@loop
		
		RTS
		
		
;-------------------------------------------------------------------------------
setupAudioPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#audioPageCnt
		STA	currPageCnt
		
		LDA	#<audioPageIndex
		STA	ptrPageIndx
		LDA	#>audioPageIndex
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightAudioTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$14
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$1A
		BNE	@loop
		
		RTS
		
		
;-------------------------------------------------------------------------------
setupNetworkPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#networkPageCnt
		STA	currPageCnt
		
		LDA	#<networkPageIndex
		STA	ptrPageIndx
		LDA	#>networkPageIndex
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightNetworkTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$1A
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$21
		BNE	@loop
		
		RTS
		
		
;-------------------------------------------------------------------------------
setupSavePage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#savePageCnt
		STA	currPageCnt
		
		LDA	#<savePageIndex
		STA	ptrPageIndx
		LDA	#>savePageIndex 
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightSaveTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$24
		LDA	clr_highlt
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$28
		BNE	@loop
		
		RTS
		

;-------------------------------------------------------------------------------
setupHelpPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#helpPageCnt
		STA	currPageCnt
		
		LDA	#<helpPageIndex
		STA	ptrPageIndx
		LDA	#>helpPageIndex 
		STA	ptrPageIndx + 1
		
		RTS



;-------------------------------------------------------------------------------
mouseTemp0:
	.word		$0000
mouseXCol:
	.byte		$00
mouseYRow:
	.byte		$00
mouseLastY:
	.word		 $0000


;-------------------------------------------------------------------------------
hotTrackMouse:
;-------------------------------------------------------------------------------
		SEI
		
		LDA	mouseLastY
		CMP	YPos
		BNE	@update
		
		LDA	mouseLastY + 1
		CMP	YPos + 1
		BNE	@update
			
		CLI
		JMP	@exit

@update:
		LDA		YPos
		STA		mouseTemp0
		STA	mouseLastY
		LDA		YPos + 1
		STA		mouseTemp0 + 1
		STA	mouseLastY + 1

		LDX		#$02
@yDiv8Loop:
		LSR
		STA	mouseTemp0 + 1
		LDA	mouseTemp0
		ROR
		STA	mouseTemp0
		LDA	mouseTemp0 + 1
		
		DEX
		BPL	@yDiv8Loop

		CLI
		
		LDA	mouseTemp0
		CMP	mouseYRow
		BEQ	@exit
		
		STA	mouseYRow
		
		CMP	#optLineOffs
		BCS	@tstInOptions
		

		CMP	#$01
		BNE	@exit

;***fixme Could do a nice little hot track on the menu, too.
		JMP	@exit
		
@tstInOptions:
		CMP	#(optLineMaxC + optLineOffs + 1)
		BCC	@isInOptions
		
;***fixme And the footer?
		JMP	@exit

@isInOptions:
		SEC
		SBC	#optLineOffs
		
		TAX
		LDA	pageOptions, X
		
		AND	#$F0
		BEQ	@selectLine
	
		CMP	#$F0
		BEQ	@exit

		CMP	#$30
		BEQ	@selectLine

		RTS
		
@selectLine:
		TXA
		PHA

		LDA	clr_bckgnd
		JSR	doHighlightSelected

		PLA
		TAX

		STX	selectedOpt
		LDA	clr_highlt
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		

@exit:
		RTS

;-------------------------------------------------------------------------------
processMouseClick:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	ButtonLClick
		
		LDA	XPos
		STA	mouseTemp0
		LDA	XPos + 1
		STA	mouseTemp0 + 1
		
		LDX	#$02
@xDiv8Loop:
		LSR
		STA	mouseTemp0 + 1
		LDA	mouseTemp0
		ROR
		STA	mouseTemp0
		LDA	mouseTemp0 + 1
		
		DEX
		BPL	@xDiv8Loop
		
		LDA	mouseTemp0
		STA	mouseXCol
		
		LDA	YPos
		STA	mouseTemp0
		LDA	YPos + 1
		STA	mouseTemp0 + 1
		
		LDX	#$02
@yDiv8Loop:
		LSR
		STA	mouseTemp0 + 1
		LDA	mouseTemp0
		ROR
		STA	mouseTemp0
		LDA	mouseTemp0 + 1
		
		DEX
		BPL	@yDiv8Loop
		
		LDA	mouseTemp0
		STA	mouseYRow
		
		JSR	doMouseClick
		RTS
		
		
;-------------------------------------------------------------------------------
doMouseClick:
;-------------------------------------------------------------------------------
		LDA	mouseYRow
		CMP	#optLineOffs
		BCS	@tstInOptions
		

		CMP	#$01
		BEQ	@clickMenu
		
		RTS

@clickMenu:
		JSR	doClickMenu
		RTS
		
@tstInOptions:
		CMP	#(optLineMaxC + optLineOffs + 1)
		BCC	@isInOptions
		
		JSR	doClickFooter
		RTS

@isInOptions:
		SEC
		SBC	#optLineOffs
		
		TAX
		LDA	pageOptions, X
		STA	mouseTemp0
		
		AND	#$F0
		BEQ	@selectLine
	
		CMP	#$F0
		BEQ	@exit

		CMP	#$30
		BEQ	@selectLine
		
		TAY
		
@loop:
		DEX
		LDA	pageOptions, X
		AND	#$F0
		BNE	@loop

		TXA
		PHA

		TYA
		JSR	doToggleOption

		PLA
		TAX
		

@selectLine:
		TXA
		PHA

		LDA	clr_bckgnd
		JSR	doHighlightSelected

		PLA
		TAX

		STX	selectedOpt
		LDA	clr_highlt
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		
		LDA	tabSelected
		CMP	#tabSaveIdx
		BNE	@checkToggle
		
		JSR	doHandleSaveButton
		JMP	@done
		
@checkToggle:
		LDA	mouseTemp0
		AND	#$F0
		BNE	@done

		LDA	mouseTemp0
		AND	#$0F

		ASL				
		TAX

		LDA	heap0, X		;Get to the type/data
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		STA	ptrOptsTemp + 1		
		
		LDY	#$00
		LDA	(ptrOptsTemp), Y

		CMP	#$21
		BEQ	@toggleOff
		
		LDA	#$20
		JMP	@doToggle

@toggleOff:
		LDA	#$10
		
@doToggle:
		LDX	selectedOpt
		JSR	doToggleOption
				
@done:

		
@exit:
		RTS


;-------------------------------------------------------------------------------
doClickMenu:
;	00-06	System
;	07-0B	Disk
;	0C-11	Video
;	12-17	Audio
;	24-27	Save
;-------------------------------------------------------------------------------
		LDA	mouseXCol
		CMP	#$08
		BCS	@tstChipsetTab
		
		LDA	#$00
		JMP	@tstUpdate
		
@tstChipsetTab:
		CMP	#$0F
		BCS	@tstVideoTab
		
		LDA	#$01
		JMP	@tstUpdate
		
@tstVideoTab:
		CMP	#$15
		BCS	@tstAudioTab
		
		LDA	#$02
		JMP	@tstUpdate
		
@tstAudioTab:
		CMP	#$1B
		BCS	@tstNetworkTab
		
		LDA	#$03
		JMP	@tstUpdate

@tstNetworkTab:
		CMP	#$22
		BCS	@tstSaveTab
		
		LDA	#$04
		JMP	@tstUpdate
		
@tstSaveTab:
		CMP	#$24
		BCC	@exit
		
		LDA	#$05
		JMP	@tstUpdate

		RTS
		
@tstUpdate:
		CMP	tabSelected
		BEQ	@exit
		
		STA	tabSelected
		JSR	setupSelectedTab
		JSR	displayOptionsPage
		
@exit:
		RTS


;-------------------------------------------------------------------------------
doClickFooter:
;-------------------------------------------------------------------------------
		LDA	mouseXCol
		CMP	#$25
		BNE @tstPrior
		
		JSR	moveNextPage
		JSR	displayOptionsPage
		RTS
		
@tstPrior:
		CMP	#$27
		BNE	@exit
		
		JSR	movePriorPage
		JSR	displayOptionsPage

@exit:
		RTS
		


;-------------------------------------------------------------------------------
moveTabLeft:
;-------------------------------------------------------------------------------
		LDX	tabSelected
		INX
		CPX	#tabMaxCount
		BCC	@done
		
		LDX	#$00
		
@done:
		STX	tabSelected
		JSR	setupSelectedTab
		
		RTS
		

;-------------------------------------------------------------------------------
moveTabRight:
;-------------------------------------------------------------------------------
		LDX	tabSelected
		DEX
		BPL	@done
		
		LDX	#(tabMaxCount - 1)
		
@done:
		STX	tabSelected
		JSR	setupSelectedTab
		
		RTS


;-------------------------------------------------------------------------------
moveNextPage:
;-------------------------------------------------------------------------------
		LDX	tabSelected
		CPX	#tabSaveIdx
		BNE	@cont
		
		RTS
		
@cont:
		LDX	pgeSelected
		INX	
		CPX	currPageCnt
		BCC	@done
		
		LDX	#$00
		
@done:
		STX	pgeSelected
		
		RTS
		

;-------------------------------------------------------------------------------
movePriorPage:
;-------------------------------------------------------------------------------
		LDX	tabSelected
		CPX	#tabSaveIdx
		BNE	@cont
		
		RTS
		
@cont:
		LDX	pgeSelected
		DEX
		BPL	@done
		
		LDX	currPageCnt
		DEX
		
@done:
		STX	pgeSelected
		
		RTS
		
		
;-------------------------------------------------------------------------------
moveSelectDown:
;-------------------------------------------------------------------------------
		LDX	selectedOpt
		CPX	#$FF
		BEQ	@exit

		LDA	clr_bckgnd
		JSR	doHighlightSelected
		
		LDX	selectedOpt
		
@loop:
		INX
		CPX	#optLineMaxC
		BNE	@test
		
		LDX	#$00
@test:
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$30
		BEQ	@found
		CMP	#$00
		BNE	@loop
		
@found:
		STX	selectedOpt
		
		LDA	clr_highlt
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		
@exit:
		RTS
		

;-------------------------------------------------------------------------------
moveSelectUp:
;-------------------------------------------------------------------------------
		LDX	selectedOpt
		CPX	#$FF
		BEQ	@exit
		
		LDA	clr_bckgnd
		JSR	doHighlightSelected
		
		LDX	selectedOpt
		
@loop:
		DEX
		BPL	@test
		
		LDX	#optLineMaxC - 1
@test:
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$30
		BEQ	@found
		CMP	#$00
		BNE	@loop
		
@found:
		STX	selectedOpt
		
		LDA	clr_highlt
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		
@exit:
		RTS
		
		
;-------------------------------------------------------------------------------
doUpdateSelected:
;-------------------------------------------------------------------------------
		LDA		crsrIsDispl
		CMP		#$01
		BNE		@begin

		LDA		#$00
		STA		crsrIsDispl
		
		LDY		#$00
		LDA		(ptrCrsrSPos), Y
		ORA		#$80
		STA	(ptrCrsrSPos), Y

@begin:
		LDX	selectedOpt
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$30
		BEQ	@updateStr
		
		CMP	#$50
		BEQ	@updateMAC
		CMP	#$60
		BEQ	@updateMAC
		
		RTS
		
@updateMAC:
		JSR	doUpdateMAC
		RTS
		

@updateStr:
		JSR	doUpdateString
		
@exit:
		RTS


;-------------------------------------------------------------------------------
doUpdateMAC:
;-------------------------------------------------------------------------------
		LDA	pageOptions, X
		AND	#$0F

		ASL				
		TAX

		CLC
		LDA	heap0, X		;Get pointer to the string
		ADC	#$03
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		ADC	#$00
		STA	ptrOptsTemp + 1		

		LDY	#$00			;Get pointer to data area
		LDA	(ptrOptsTemp), Y
		TAY
		INY
		TYA
		CLC
		ADC	ptrOptsTemp
		STA	ptrNextInsP
		LDA	ptrOptsTemp + 1
		ADC	#$00
		STA	ptrNextInsP + 1
		
		CLC
		LDA	selectedOpt
		ADC	#optLineOffs
		TAX
		
		CLC
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		ADC	#$16			;and column
		STA	ptrCrsrSPos
		LDA	screenRowsHi, X
		ADC	#$00
		STA	ptrCrsrSPos + 1
	
		LDA	#$00
		STA	currMACByte
		STA	currMACNybb

		LDA	#$01
		STA	crsrIsDispl


		RTS

;-------------------------------------------------------------------------------
doUpdateString:
;-------------------------------------------------------------------------------
		LDA	pageOptions, X
		AND	#$0F

		ASL				
		TAX

		CLC
		LDA	heap0, X		;Get pointer to the length
		ADC	#$03
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		ADC	#$00
		STA	ptrOptsTemp + 1		
		
		LDY	#$00
		LDA	(ptrOptsTemp), Y
		STA	currTextMax
		
		INY
		LDA	(ptrOptsTemp), Y
		TAY
		INY
		INY
		
		LDX	#$00
@loop:
		LDA	(ptrOptsTemp), Y
		BEQ	@cont
		INY
		INX
		CPX	currTextMax
		BNE	@loop
		
@cont:
		STX	currTextLen
		STY	dispOptTemp0
		
		CLC
		LDA	ptrOptsTemp
		ADC	dispOptTemp0
		STA	ptrNextInsP
		LDA	ptrOptsTemp + 1
		ADC	#$00
		STA	ptrNextInsP + 1
		
		SEC
		LDA	#$27
		SBC	currTextMax
		CLC
		ADC	currTextLen
		STA	dispOptTemp0
		
		CLC
		LDA	selectedOpt
		ADC	#optLineOffs
		TAX
		
		CLC
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		ADC	dispOptTemp0		;and column
		STA	ptrCrsrSPos
		LDA	screenRowsHi, X
		ADC	#$00
		STA	ptrCrsrSPos + 1
		
		LDA	#$01
		STA	crsrIsDispl
		
		RTS


;-------------------------------------------------------------------------------
doToggleOption:
;	.X	is toggle option line
;	.A	is $20 for on, $10 for off	
;-------------------------------------------------------------------------------
		PHA

		STX	dispOptTemp0

		LDA	pageOptions, X
		AND	#$0F
		PHA

		ASL				
		TAX
		
		LDA	heap0, X		;Get pointer to the option
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		STA	ptrOptsTemp + 1
		
		LDY	#$00			;Get the type
		LDA	(ptrOptsTemp), Y
		AND	#$F0
		
		CMP	#$20			;Not an option type we want?
		BCC	@exit			;exit
		
		PLA
		TAX
		
		PLA
		LSR
		LSR
		LSR
		LSR
		LSR
		PHA
		
		LDA	(ptrOptsTemp), Y
		AND	#$FE
		STA	(ptrOptsTemp), Y
		PLA
		PHA
		ORA	(ptrOptsTemp), Y
		STA	(ptrOptsTemp), Y
		
		LDA	dispOptTemp0
		CLC
		ADC	#optLineOffs + 1
		TAX
		
		CLC
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		ADC	#$05			;and column
		STA	ptrTempData
		LDA	screenRowsHi, X
		ADC	#$00
		STA	ptrTempData + 1
		
		PLA
		AND	#$0F
		BEQ	@isUnSet
		
		LDA	#$D1
		PHA
		LDA	#$A0
		PHA
		
		JMP	@update
		
@isUnSet:
		LDA	#$A0
		PHA
		LDA	#$D1
		PHA
		
@update:
		PLA
		STA	(ptrTempData), Y
		PLA
		LDY	#$28
		STA	(ptrTempData), Y
		
@exit:
		RTS

;-------------------------------------------------------------------------------
displayOptionsPage:
;-------------------------------------------------------------------------------
		LDY	#$00
		STY	crsrIsDispl
		
		JSR clearScreen
		
		JSR	highlightSelectedTab
		JSR	updateFooter
		
		LDA	#$00
		STA	infoCntr
		STA	infoCntr + 1
		
		LDA	pgeSelected
		ASL
		TAY

		LDA	(ptrPageIndx), Y
		STA	ptrCurrOpts
		STA	ptrOptsTemp
		INY
		LDA	(ptrPageIndx), Y
		STA	ptrCurrOpts + 1
		STA	ptrOptsTemp + 1

		LDA	#<heap0
		STA	ptrCurrHeap
		LDA	#>heap0
		STA	ptrCurrHeap + 1
		
		LDY	#$FF
		STY	selectedOpt
		LDY	#$00
		STY	optTempLine
		STY	optTempIndx
				
@loop0:
		LDA	(ptrOptsTemp), Y
		CMP	#$00
		BEQ	@finish
	
		JSR	doDisplayOpt
		BCS	@error
		
;		TYA
;		TAX
;		
;		LDY	#$00
;		LDA	(ptrOptsTemp), Y
;		PHA
;		
;		TXA
;		TAY
		
		CLC
		TYA
		ADC	ptrOptsTemp
		STA	ptrOptsTemp
		LDA	ptrOptsTemp + 1
		ADC	#$00
		STA	ptrOptsTemp + 1
		
		INC	optTempIndx

;		PLA

		LDX	optTempLine		;Blank line between options
		LDA	#$FF
		STA	pageOptions, X
		INC	optTempLine		;and next line

		LDY	#$00

		JMP	@loop0

@finish:
		LDX	optTempLine		;Clear line usage until end 
						;of page
@loop1:
		CPX	#optLineMaxC
		BEQ	@done
		
		LDA	#$FF
		STA	pageOptions, X
		INX
		JMP	@loop1
		
@done:
		LDA	tabSelected
		CMP	#tabSaveIdx
		BNE	@tstHelp
	
		LDA	pgeSelected
		CMP	#$02
		BNE	@tstConfirm
		
		JSR	updateSaveReset
		JMP	@updateStd
		
@tstConfirm:
	
		CMP	#$01
		BNE	@updateStd
		
		JSR	updateSaveConfirm
		JMP	@cont		

@tstHelp:
		CMP	#tabHelpIdx
		BNE	@updateStd
		
		JSR	updateHelpPage
		
		LDX	#$12
		JMP	@cont

@updateStd:
		LDX	#$00
		LDA	pageOptions, X
		CMP	#$FF
		BEQ	@exit
		
		
@cont:
		STX	selectedOpt

		LDA	clr_highlt
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
	
@exit:

		RTS

@error:
;***fixme
;	Need something else here?  This is really a debug assert so maybe not
		LDA	#$0A			
		STA	$D020
;***
		RTS


;-------------------------------------------------------------------------------
updateHelpPage:
;-------------------------------------------------------------------------------
		LDA	#<helpTexts
		STA	ptrCurrOpts
		LDA #>helpTexts
		STA	ptrCurrOpts + 1
		
		LDX	#$00
		LDY	#optLineOffs - 1
		
@loop:
		STY	optTempLine

		TXA
		TAY
		
		LDA	(ptrCurrOpts), Y
		BEQ	@exit

		STA	ptrOptsTemp
		INY
		LDA	(ptrCurrOpts), Y
		STA	ptrOptsTemp + 1
		INY
		
		TYA
		TAX
		
		LDY	optTempLine
		JSR	dispCentreText
		
		INY
		
		JMP	@loop
			
@exit:
		RTS


;-------------------------------------------------------------------------------
updateSaveReset:
;-------------------------------------------------------------------------------
		LDA	#<saveConfRest0
		STA	ptrOptsTemp
		LDA	#>saveConfRest0
		STA	ptrOptsTemp + 1
		
		LDY	#(optLineOffs + 4)
		
		JSR	dispCentreText
		
		RTS


;-------------------------------------------------------------------------------
updateSaveConfirm:
;-------------------------------------------------------------------------------
		LDX	saveSlctOpt
;		BNE	@tstSaveApply
		BNE	@tstSaveRestore

		LDA	#<saveConfExit0				;Exit without saving
		STA	ptrOptsTemp
		LDA	#>saveConfExit0
		STA	ptrOptsTemp + 1

		LDY	#optLineOffs

		JSR	dispCentreText

		LDA	#<saveConfExit1
		STA	ptrOptsTemp
		LDA	#>saveConfExit1
		STA	ptrOptsTemp + 1

		LDY	#(optLineOffs + 2)

		JSR	dispCentreText
		JMP	@exit

;@tstSaveApply:
;		CPX	#$02
;		BNE	@tstSaveThis
;
;		LDA	#<saveConfAppl0
;		STA	ptrOptsTemp
;		LDA	#>saveConfAppl0
;		STA	ptrOptsTemp + 1
;
;		LDY	#optLineOffs
;
;		JSR	dispCentreText
;
;		LDA	#<saveConfAppl1
;		STA	ptrOptsTemp
;		LDA	#>saveConfAppl1
;		STA	ptrOptsTemp + 1
;
;		LDY	#(optLineOffs + 2)
;
;		JSR	dispCentreText
;		JMP	@exit

@tstSaveRestore:
		CPX	#$02
		BNE	@tstSaveOnboard

		LDA	#<saveConfSave0				;Restore factory settings
		STA	ptrOptsTemp
		LDA	#>saveConfSave0
		STA	ptrOptsTemp + 1

		LDY	#optLineOffs

		JSR	dispCentreText

		LDA	#<saveConfFactory0
		STA	ptrOptsTemp
		LDA	#>saveConfFactory0
		STA	ptrOptsTemp + 1

		LDY	#(optLineOffs + 2)

		JSR	dispCentreText
		JMP	@exit

@tstSaveOnboard:
		CPX	#$04
		BNE	@tstSaveSys

		LDA	#<saveConfExit0				;Exit to onboarding
		STA	ptrOptsTemp
		LDA	#>saveConfExit0
		STA	ptrOptsTemp + 1

		LDY	#optLineOffs

		JSR	dispCentreText


		LDA	#<saveConfOnBoard0
		STA	ptrOptsTemp
		LDA	#>saveConfOnBoard0
		STA	ptrOptsTemp + 1

		LDY	#(optLineOffs + 2)

		JSR	dispCentreText

		LDA	#<saveConfOnBoard1
		STA	ptrOptsTemp
		LDA	#>saveConfOnBoard1
		STA	ptrOptsTemp + 1

		LDY	#(optLineOffs + 4)

		JSR	dispCentreText

		JMP	@exit

@tstSaveSys:
		CPX	#$06
		BNE	@invalid
		
		LDA	#<saveConfSave0
		STA	ptrOptsTemp
		LDA	#>saveConfSave0
		STA	ptrOptsTemp + 1

		LDY	#optLineOffs

		JSR	dispCentreText

		LDA	#<saveConfDflt0
		STA	ptrOptsTemp
		LDA	#>saveConfDflt0
		STA	ptrOptsTemp + 1

		LDY	#(optLineOffs + 2)

		JSR	dispCentreText

@exit:
	
		LDX	#$06
		RTS
		
@invalid:
		LDX	#$FF
		RTS
		


;-------------------------------------------------------------------------------
updateFooter:
;-------------------------------------------------------------------------------
		LDA	currPageCnt
		CLC
		ADC	#$30
		ORA	#$80
		STA	$07E7
		
		LDA	pgeSelected
		CLC
		ADC	#$31
		ORA	#$80
		STA	$07E5
		
		RTS


;-------------------------------------------------------------------------------
doDisplayOpt:
;	When called:
;		.A	will have current option type
;		.Y	will have offset into option from ptrOptsTemp (will be 0)
;		ptrOptsTemp will be start of option
;		optTempLine will be line (offset by -3)
;		optTempIndx will be option number
;		ptrCurrHeap will be next storage pointer
;	When complete:
;		.Y	will have offset to next option
;		optTempLine will be next available line
;		ptrCurrHeap points to next storage pointer
;-------------------------------------------------------------------------------
		PHA				;Store state
		
		INY				;Skip one data byte
		
;***fixme Could use 4510 instructions here
		TYA
		PHA
;***

		LDY	#$00			;Update the heap to point to
		LDA	ptrOptsTemp		;this option (for fast access)
		STA	(ptrCurrHeap), Y
		LDA	ptrOptsTemp + 1
		INY
		STA	(ptrCurrHeap), Y
		
		CLC				;Point heap to next
		LDA	#$02
		ADC	ptrCurrHeap
		STA	ptrCurrHeap
		LDA	ptrCurrHeap + 1
		ADC	#$00
		STA	ptrCurrHeap + 1
		
;***fixme Could use 4510 instructions here
		PLA				;Restore state
		TAY
		PLA
;***
		TAX				;Keep whole byte in .X
		
		AND	#$F0			;Concerned now with hi nybble
		
		CMP	#$10
		BNE	@tstToggOpt

		JSR	doDispButtonOpt
		RTS
		
@tstToggOpt:
		CMP	#$20
		BNE	@tstStrOpt
		
		JSR	doDispToggleOpt
		RTS
		
@tstStrOpt:
		CMP	#$30
		BNE	@tstBlankOpt
		
		JSR	doDispStringOpt
		RTS
		
@tstBlankOpt:
		CMP	#$40
		BNE	@tstMACOpt
		
		LDX	optTempLine		;Blank line 
		LDA	#$FF
		STA	pageOptions, X
		INC	optTempLine		;and next line
		CLC
		RTS
		
@tstMACOpt:
		CMP	#$50
		BNE	@tstRTCOpt

		lda #1
		sta isRTCField
		JSR	doDispMACOpt
		RTS
		
@tstRTCOpt:
		CMP	#$60
		BNE	@unknownOpt
		
		lda #0
		sta isRTCField
		JSR	doDispMACOpt
		RTS
		
@unknownOpt:
		SEC
		RTS


;-------------------------------------------------------------------------------
doDispButtonOpt:
;-------------------------------------------------------------------------------
		TXA
		
		JSR	doDispOptHdrLbl		;Display the header label
		
		LDX	optTempLine		;Set this line to be the option
		LDA	optTempIndx
		STA	pageOptions, X
		INC	optTempLine		;and next line

		CLC
		RTS


;-------------------------------------------------------------------------------
doDispToggleOpt:
;-------------------------------------------------------------------------------
		INY				;Skip past offset and flags
		INY
		INY
		
		TXA
		PHA
		
		JSR	doDispOptHdrLbl		;Display the header label
		
		LDX	optTempLine		;Set this line to be the option
		LDA	optTempIndx
		STA	pageOptions, X
		INC	optTempLine		;and next line
		
		PLA				;Figure out if the first opt
		AND	#$01			;is enabled or not
		PHA				;Keep intermediary value
		EOR	#$01			
		
		TAX				;Flag if selected
		JSR	doDispOptTogLbl		;Display first option value

		LDX	optTempLine		;Set this line to be option value
		LDA	optTempIndx
		ORA	#$10
		STA	pageOptions, X
		INC	optTempLine		;and next line

		PLA				;Get back intermediary
		TAX				;Flag if selected
		JSR	doDispOptTogLbl		;Display second option value

		LDX	optTempLine		;Set this line to be option value
		LDA	optTempIndx
		ORA	#$20
		STA	pageOptions, X
		INC	optTempLine		;and next line

		CLC
		RTS
		
		
;-------------------------------------------------------------------------------
doDispStringOpt:
;-------------------------------------------------------------------------------
		INY				;Skip past offset 
		INY
		
		LDA	(ptrOptsTemp), Y	;Input string length
		PHA
		INY
		
		JSR	doDispOptHdrLbl		;Display the header label
		
		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		PLA
		STA	dispOptTemp0

		TAX				;Subtract length + 1 from
		INX				;line length to give us
		STX	dispOptTemp1		;size of input field
		SEC
		LDA	#$28
		SBC	dispOptTemp1
		
		STA	dispOptTemp1
		
		CLC				;Add this position to colour
		ADC	ptrTempData		;RAM pointer
		STA	ptrTempData
		LDA	ptrTempData + 1		
		ADC	#$00
		STA	ptrTempData + 1		
		
		TYA
		PHA
		
		LDY	#$00			;Set colour for input field
		LDA	clr_ctrlfc
@loop0:
		STA	(ptrTempData), Y
		INY
		DEX
		BNE	@loop0

		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, X
		STA	ptrTempData + 1		

		LDA	dispOptTemp1
		
		CLC				;Add this position to screen
		ADC	ptrTempData		;RAM pointer
		STA	ptrTempData
		LDA	ptrTempData + 1		
		ADC	#$00
		STA	ptrTempData + 1		

;**fixme This is horrible because we can't push .Y directly.  Can be
;	fixed on 4510.
		PLA
		TAY
		PHA
	
		LDA	#$00
		STA	dispOptTemp1
	
@loop1:						;Display string value
		LDA	(ptrOptsTemp), Y
		BEQ	@cont
		
	.if	C64_MODE
		JSR	inputToCharROM
	.else
		JSR	asciiToCharROM
	.endif

		ORA	#$80
		STA	dispOptTemp2
		TYA
		PHA
		LDY	dispOptTemp1
		LDA	dispOptTemp2
		
		STA	(ptrTempData), Y
		INC	dispOptTemp1
		
		PLA
		TAY
		INY
		
		LDA	dispOptTemp1
		CMP	#$10
		BNE	@loop1
;***

@cont:
		LDX	optTempLine		;Set this line to be the option
		LDA	optTempIndx
		ORA	#$30
		STA	pageOptions, X
		INC	optTempLine		;and next line

		PLA				;Move .Y past data storage
		CLC
		ADC	dispOptTemp0
		TAY
				
		CLC
		RTS
		

;-------------------------------------------------------------------------------
doDispMACOpt:
;-------------------------------------------------------------------------------
		INY				;Skip past offset 
		INY
		
		JSR	doDispOptHdrLbl		;Display the header label
		
		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDA	#$16
		LDX	#$12
		
		CLC				;Add this position to colour
		ADC	ptrTempData		;RAM pointer
		STA	ptrTempData
		LDA	ptrTempData + 1		
		ADC	#$00
		STA	ptrTempData + 1		
		
		TYA
		PHA
		
		LDY	#$00			;Set colour for input field
		LDA	clr_ctrlfc
@loop0:
		STA	(ptrTempData), Y
		INY
		DEX
		BNE	@loop0

		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, X
		STA	ptrTempData + 1		

		LDA	#$16
		
		CLC				;Add this position to screen
		ADC	ptrTempData		;RAM pointer
		STA	ptrTempData
		LDA	ptrTempData + 1		
		ADC	#$00
		STA	ptrTempData + 1		

;**fixme This is horrible because we can't push .Y directly.  Can be
;	fixed on 4510.

@breakDispMACOpt:
		PLA
		TAY
		PHA
	
		LDA	#$00
		STA	dispOptTemp1
	
@loop1:						;Display MAC value
		LDA	(ptrOptsTemp), Y
		STA	dispOptTemp0
		JSR	convertValueToHex
		INY
		TYA
		PHA
		LDY	dispOptTemp1
		
		LDA	dispOptTemp2
		STA	(ptrTempData), Y
		INC	dispOptTemp1
		INY
		
		LDA	dispOptTemp3
		STA	(ptrTempData), Y
		INC	dispOptTemp1
		INY
		
		CPY	#$11
		BEQ	@skip

		lda	isRTCField
		bne	@macColon
		lda	rtcSeparators,y
		jmp	@dispSeparator

@macColon:
		LDA	#':'
@dispSeparator:
		JSR	asciiToCharROM
		ORA	#$80
		STA	(ptrTempData), Y
		
@skip:
		INC	dispOptTemp1
		
		PLA
		TAY
		
		LDA	dispOptTemp1
		CMP	#$12
		BNE	@loop1
;***

@cont:
		LDX	optTempLine		;Set this line to be the option
		LDA	optTempIndx
		ORA	#$50
		STA	pageOptions, X
		INC	optTempLine		;and next line

		PLA				;Move .Y past data storage
		CLC
		ADC	#$06
		TAY
				
		CLC
		RTS

isRTCField:	.byte 0
rtcSeparators:
	.byte 0,0,':',0,0,'.',0,0,' ',0,0,'.',0,0,'.'

;-------------------------------------------------------------------------------
convertValueToHex:
;-------------------------------------------------------------------------------
		LDA	dispOptTemp0
		LSR
		LSR
		LSR
		LSR
		JSR	convertNybbleToHex
		JSR	asciiToCharROM
		ORA	#$80
		STA	dispOptTemp2

		LDA	dispOptTemp0
		AND	#$0F
		JSR	convertNybbleToHex
		JSR	asciiToCharROM
		ORA	#$80
		STA	dispOptTemp3
		
		RTS

;-------------------------------------------------------------------------------
convertNybbleToHex:
;-------------------------------------------------------------------------------
		CMP	#$0A
		BCS	@alpha
		
		CLC
		ADC	#$30
		RTS
		
@alpha:
		SEC
		SBC	#$09
		RTS
		

;-------------------------------------------------------------------------------
dispOptTemp0:
	.byte		$00
dispOptTemp1:
	.byte		$00
dispOptTemp2:
	.byte		$00
dispOptTemp3:
	.byte		$00
	

;-------------------------------------------------------------------------------
doDispOptHdrLbl:
;-------------------------------------------------------------------------------
		TYA				;Store state
		PHA

		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1
		
		LDA	clr_ctrlfc		;Set colour for opt indicator
		LDY	#$00
		STA	(ptrTempData), Y
		
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, X
		STA	ptrTempData + 1
		
		LDA	#$AB			;'+' - opt indicator
		STA	(ptrTempData), Y
		INY				;Move to label column
		INY
		TYA
		TAX

		PLA
		TAY

;	.X now holds offset to screen pos for label
;	.Y is offset into list for label length
		STX	dispOptTemp0

		LDA	(ptrOptsTemp), Y
		INY
		TAX
		DEX
		
;	.X now holds cntr for displaying str
;	.Y is offset into list for label 
@loop:
		LDA	(ptrOptsTemp), Y
		JSR	asciiToCharROM
		ORA	#$80
		
;***fixme Could use 4510 instructions to avoid dispOptTemp1
		STA	dispOptTemp1
		TYA
		PHA
		LDY	dispOptTemp0
		LDA	dispOptTemp1
;***
		STA	(ptrTempData), Y
		INC	dispOptTemp0
		PLA
		TAY
		INY
		
		DEX
		BPL	@loop
		
;	.Y should now be offset to next data entry in list

		RTS


;-------------------------------------------------------------------------------
doDispOptTogLbl:
;-------------------------------------------------------------------------------
		TYA				;Store state
		PHA

		TXA
		PHA

		LDA	optTempLine		;Get current line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1
		
		CLC				;Move to our indicator x pos
		LDA	ptrTempData
		ADC	#$05
		STA	ptrTempData
		LDA	ptrTempData + 1
		ADC	#$00
		STA	ptrTempData + 1
		
		LDA	clr_ctrlfc			;Set colour for opt indicator
		LDY	#$00
		STA	(ptrTempData), Y
		
		LDA	screenRowsLo, X		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, X
		STA	ptrTempData + 1
		
		CLC				;Move to our indicator x pos
		LDA	ptrTempData
		ADC	#$05
		STA	ptrTempData
		LDA	ptrTempData + 1
		ADC	#$00
		STA	ptrTempData + 1
		
		PLA
		CMP	#$01
		BEQ	@optIsSet

		LDA	#$A0			;unset opt indicator
		JMP	@cont

@optIsSet:
		LDA	#$D1			;set opt indicator
		
@cont:
		STA	(ptrTempData), Y
		INY				;Move to label column
		INY
		TYA
		TAX

		PLA
		TAY

;	.X now holds offset to screen pos for label
;	.Y is offset into list for label length
		STX	dispOptTemp0

		LDA	(ptrOptsTemp), Y
		INY
		TAX
		DEX
		
;	.X now holds cntr for displaying str
;	.Y is offset into list for label 
@loop:
		LDA	(ptrOptsTemp), Y
		JSR	asciiToCharROM
		ORA	#$80
		
;***fixme Could use 4510 instructions to avoid dispOptTemp1
		STA	dispOptTemp1
		TYA
		PHA
		LDY	dispOptTemp0
		LDA	dispOptTemp1
;***
		STA	(ptrTempData), Y
		INC	dispOptTemp0
		PLA
		TAY
		INY
		
		DEX
		BPL	@loop
		
;	.Y should now be offset to next data entry in list

		RTS


;-------------------------------------------------------------------------------
dispCentreText:
;-------------------------------------------------------------------------------
		TYA
		PHA

		LDA	screenRowsLo, Y		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, Y
		STA	ptrTempData + 1		
		
		LDY	#$00
		LDA	(ptrOptsTemp), Y
		BNE	@cont
		
		PLA
		TAY
		
		RTS

@cont:		
		STA	optTempIndx
		
		CLC
		LDA	ptrOptsTemp
		ADC	#$01
		STA	ptrOptsTemp
		LDA	ptrOptsTemp + 1
		ADC	#$00
		STA	ptrOptsTemp + 1
		
		SEC
		LDA	#$28
		SBC	optTempIndx
		LSR
		
		CLC
		ADC	ptrTempData
		STA	ptrTempData
		LDA	ptrTempData + 1
		ADC	#$00
		STA	ptrTempData + 1
		
		LDY	optTempIndx
		DEY
@loop:
		LDA	(ptrOptsTemp), Y
		JSR	asciiToCharROM
		ORA	#$80
		STA	(ptrTempData), Y
		DEY
		BPL	@loop
		
		PLA
		TAY
		
		RTS
		

;-------------------------------------------------------------------------------
	.if	.not	C64_MODE
clrScreenDAT:
	.byte		$0A				;F018A
	.byte		$00
	.byte		$03			; fill non-chained job 
	.word		$03E8			; number of bytes to copy
	.word		$00A0			; source address
	.byte		$00			; source bank number / direction
	.word		$0400			; destination address
	.byte		$00			; destination bank number / direction
	.word		$0000			; modulo	

clrColourDAT:
	.byte		$0A				;F018A
	.byte		$00
	.byte		$03			; fill non-chained job 
	.word		$03E8			; number of bytes to copy
;	.word		$000B			; source address - dengland errr?  No its not!
clrColourDAT7:
	.word		$0000	
	.byte		$00			; source bank number / direction
	.word		$F800			; destination address
	.byte		$01			; destination bank number / direction
	.word		$0000			; modulo	
	.endif

;-------------------------------------------------------------------------------
clearScreen:
;-------------------------------------------------------------------------------
	.if	C64_MODE
		LDX	#$00
@loop0:	 
		LDA	#$A0			;Screen memory
		STA	$0400, X
		STA	$0500, X
		STA	$0600, X
		STA	$0700, X
		
		LDA	clr_bckgnd			;Colour memory
		STA	$D800, X
		STA	$D900, X
		STA	$DA00, X
		STA	$DB00, X
		INX
		BNE	@loop0
		
;	The above goes overboard and clears out the sprite pointers, too.  So, 
;	we need to restore it.
		LDA		#$0D
		STA		spritePtr0
		
	.else
		LDA		clr_bckgnd
		STA		clrColourDAT7

		LDA	#$00
		STA	$D702
		STA	$D704
		LDA	#>clrScreenDAT
		STA	$D701
		LDA	#<clrScreenDAT
		STA	$D705		

		LDA	#$00
		STA	$D702
		STA	$D704
		LDA	#>clrColourDAT
		STA	$D701
		LDA	#<clrColourDAT
		STA	$D705		
	.endif


	LDA	hdr_colors
	BNE	@sel1
	
	LDA	#<headerColours0
	STA	@selfmod0 + 1
	LDA	#>headerColours0
	STA	@selfmod0 + 2
	
	JMP	@cont

@sel1:
	LDA	#<headerColours1
	STA	@selfmod0 + 1
	LDA	#>headerColours1
	STA	@selfmod0 + 2
	
@cont:
;	Header and footer
		LDY	#39
@loop1:	 
		LDA	headerLine, Y		
		JSR	asciiToCharROM		;Convert header for screen 
		ORA	#$80			;Output in reverse
		STA	$0400, Y
		
@selfmod0:
		LDA	headerColours0, Y
		STA	$D800, Y
		
		LDA	menuLine, Y		
		JSR	asciiToCharROM		;Convert menu for screen 
		ORA	#$80			;Output in reverse
		STA	$0428, Y
		
		LDA	clr_inactv
		STA	$D828, Y
		
		LDA	footerLine, Y		
		JSR	asciiToCharROM		;Convert footer for screen 
		ORA	#$80			;Output in reverse
		STA	$07C0, Y
		
		LDA	clr_inactv
		STA	$DBC0, Y
		
		DEY
		BPL	@loop1

		RTS
		
		
;-------------------------------------------------------------------------------
asciiToCharROM:
;	Must be re-entrant in the case the IRQ handler calls while the main 
;	code also does.
;-------------------------------------------------------------------------------
;	NUL ($00) becomes a space
		CMP	#0
		BNE	atc0
		LDA	#$20
atc0:
;	@ becomes $00
		CMP	#$40
		BNE	atc1
		LDA	#0
		RTS
atc1:
		CMP	#$5B
		BCS	atc2
;	A to Z -> leave unchanged
		RTS
atc2:
		CMP	#$5B
		BCC	atc3
		CMP	#$60
		BCS	atc3
;	[ \ ] ^ _ -> subtract $40
		SEC
		SBC	#$40

		RTS
atc3:
		CMP	#$61
		BCC	atc4
		CMP	#$7B
		BCS	atc4
;	a - z -> subtract $60
		SEC
		SBC	#$60
atc4:		
		RTS
		

;-------------------------------------------------------------------------------
inputToCharROM:
;-------------------------------------------------------------------------------
;	NUL ($00) becomes a space
		CMP	#0
		BNE	@atc0
		LDA	#$20
@atc0:
;	@ becomes $00
		CMP	#$40
		BNE	@atc1
		LDA	#0
		RTS
@atc1:
		CMP	#$5B
		BCS	@atc2
		
		CMP	#$41
		BCC	@atc4
		
;	A to Z -> subtract $40
		SEC
		SBC	#$40
		
		RTS
@atc2:
		CMP	#$5B
		BCC	@atc3
		CMP	#$60
		BCS	@atc3
;	[ \ ] ^ _ -> subtract $40
		SEC
		SBC	#$40

		RTS
@atc3:
		CMP	#$61
		BCC	@atc4
		CMP	#$7B
		BCS	@atc4
;	a - z -> subtract $20
		SEC
		SBC	#$20

@atc4:		
		RTS
		

;-------------------------------------------------------------------------------
doHighlightSelected:
;-------------------------------------------------------------------------------
		PHA				;Store colour to use
		
		LDX	selectedOpt		;Get information about opt at
		LDA	pageOptions, X		;selected line
		
		CMP	#$FF			;If its no opt (by chance),
		BEQ	@exit			;exit
		
		AND	#$0F			;Only want opt index, not
		ASL				;entry type
		TAX
		
		LDA	heap0, X		;Get pointer to the option
		STA	ptrOptsTemp
		LDA	heap0 + 1, X
		STA	ptrOptsTemp + 1
		
		LDY	#$00			;Get the type
		LDA	(ptrOptsTemp), Y
		AND	#$F0
		
		CMP	#$10			;Button type?
		BEQ	@cont			;
		
		CMP	#$50			;MAC type?
		BEQ	@cont0			;
		CMP	#$60			;RTC type?
		BEQ	@cont0			;
		
		INY				;Skip past type, offset and 
						;data
@cont0:			 
		INY
		INY
		
@cont:
		INY
		
		LDA	(ptrOptsTemp), Y	;Get the length of the label
		PHA
		
		LDA	selectedOpt		;Get selected line #
		CLC
		ADC	#optLineOffs		;Add 3 for our menu/header
		TAX				;Store in .X
		
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1
		
		CLC				;Move to our label x pos
		LDA	ptrTempData
		ADC	#$02
		STA	ptrTempData
		LDA	ptrTempData + 1
		ADC	#$00
		STA	ptrTempData + 1
		
		PLA				;Get back the length
		TAY
		DEY				;Highlight
		PLA
@loop:
		STA	(ptrTempData), Y
		DEY
		BPL	@loop
		
@exit:
		RTS
		
	
;-------------------------------------------------------------------------------
initState:
;	This is much the same thing the Kernal does in its reset procedure to 
;	initialise the CIA.  I've taken it directly from the Kernal disassembly.
;	Where it says "VIA" it means CIA.  I don't know why the disassembly says
;	the wrong thing.  I left the SID init in there, too.  Timing is assumed
;	to be for PAL.
;
;***fixme Check that using PAL timing is correct in all situations.
;-------------------------------------------------------------------------------

	.if	.not	C64_MODE
;	Try to fix oddities
		LDA	$D011
		STA	$D011

;	Enable enhanced registers
		LDA	#$47			;M65 knock knock
		STA	$D02F
		LDA	#$53
		STA	$D02F
		LDA	#65
		STA	$00
		
;;	 Make sure no colour RAM @ $DC00, no sector buffer overlaying $DCxx/$DDxx
		LDA	#$00
		STA	$D030
		LDA	#$82
		STA	$D680
	.endif
				
;		SEI		  		;disable the interrupts
		CLD		  		;clear decimal mode

		LDA	#$7F	  		;disable all interrupts
		STA	$DC0D	 		;save VIA 1 ICR
		STA	$DD0D	 		;save VIA 2 ICR
		STA	$DC00	 		;save VIA 1 DRA, keyboard column drive
		LDA	#$08	  		;set timer single shot
		STA	$DC0E	 		;save VIA 1 CRA
		STA	$DD0E	 		;save VIA 2 CRA
		STA	$DC0F	 		;save VIA 1 CRB
		STA	$DD0F	 		;save VIA 2 CRB
		LDX	#$00	  		;set all inputs
		STX	$DC03	 		;save VIA 1 DDRB, keyboard row
		STX	$DD03	 		;save VIA 2 DDRB, RS232 port
		STX	$D418	 		;clear the volume and filter select register
		DEX		  		;set X = $FF
		STX	$DC02	 		;save VIA 1 DDRA, keyboard column
		LDA	#$07	  		;DATA out high, CLK out high, ATN out high, RE232 Tx DATA
						;high, video address 15 = 1, video address 14 = 1
		STA	$DD00	 		;save VIA 2 DRA, serial port and video address
		LDA	#$3F	  		;set serial DATA input, serial CLK input
		STA	$DD02	 		;save VIA 2 DDRA, serial port and video address

	.if	C64_MODE
		LDA	#$E6	  		;set 1110 0110, motor off, enable I/O, enable KERNAL,
						;disable BASIC
	.else
		LDA	#$E5			;set 1110 0101 - motor off, enable IO
						;disable Kernal and BASIC
	.endif
						
		STA	$01	   		;save the 6510 I/O port
		LDA	#$2F	  		;set 0010 1111, 0 = input, 1 = output
		STA	$00	   		;save the 6510 I/O port direction register
;		LDA	$02A6	 		;get the PAL/NTSC flag
;		BEQ	$FDEC	 		;if NTSC go set NTSC timing
						;else set PAL timing
		LDA	#$25
		STA	$DC04	 		;save VIA 1 timer A low byte
		LDA	#$40
;		JMP	$FDF3
; FDEC:		LDA	#$95
;		STA	$DC04	 		;save VIA 1 timer A low byte
;		LDA	#$42
; FDF3:
		STA	$DC05	 		;save VIA 1 timer A high byte

		LDA	#$81	  		;enable timer A interrupt
		STA	$DC0D	 		;save VIA 1 ICR
		LDA	$DC0E	 		;read VIA 1 CRA
		AND	#$80	  		;mask x000 0000, TOD clock
		ORA	#$11	  		;mask xxx1 xxx1, load timer A, start timer A
		STA	$DC0E	 		;save VIA 1 CRA

		LDA	$DD00	 		;read VIA 2 DRA, serial port and video address
		ORA	#$10	  		;mask xxx1 xxxx, set serial clock out low
		STA	$DD00	 		;save VIA 2 DRA, serial port and video address

;		CLI				;enable the interrupts

		RTS
		

;-------------------------------------------------------------------------------
;Mouse driver variables
;-------------------------------------------------------------------------------
OldPotX:	   
	.byte   	0				; Old hw counter values
OldPotY:	   
	.byte   	0

DirectionTemp:	.byte 0
XDirection:	.byte 0
YDirection:	.byte 0
XPosNew:		 
	.word   	0			
YPosNew:		 
	.word   	0			
XPosPending:		 
	.word   	0			
YPosPending:		 
	.word   	0

XPos:		 
	.word   	0				; Current mouse position, X
YPos:		 
	.word   	0				; Current mouse position, Y
XMin:		 
	.word   	0				; X1 value of bounding box
YMin:		 
	.word   	0				; Y1 value of bounding box
XMax:		 
	.word   	319				; X2 value of bounding box
YMax:		 
	.word   	199				; Y2 value of bounding box
Buttons:	   
	.byte   	0				; button status bits
ButtonsOld:
	.byte		0
ButtonLClick:
	.byte		0
ButtonRClick:
	.byte		0

OldValue:	  
	.byte   	0				; Temp for MoveCheck routine
NewValue:	  
	.byte   	0				; Temp for MoveCheck routine

tempValue:	
	.word		0
mouseCheck:
	.byte		$00


blinkCntr:
	.byte		$10
	
infoCntr:
	.word		$0000

flgMse1351:
	.byte		$00

	.if	C64_MODE
spritePtr:
	.byte		%11111110, %00000000, %00000000
	.byte		%11111100, %00000000, %00000000
	.byte		%11111000, %00000000, %00000000
	.byte		%11111100, %00000000, %00000000
	.byte		%11111110, %00000000, %00000000
	.byte		%11011111, %00000000, %00000000
	.byte		%10001111, %00000000, %00000000
	.byte		%00000110, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	.byte		%00000000, %00000000, %00000000
	
	.else
spritePtr:
	.byte			$11, $00, $00, $00, $00, $00, $00, $00
	.byte		 $1F, $10, $00, $00, $00, $00, $00, $00
	.byte		 $1F, $F1, $00, $00, $00, $00, $00, $00
	.byte		 $1F, $AF, $10, $00, $00, $00, $00, $00
	.byte		 $1F, $AA, $F1, $00, $00, $00, $00, $00
	.byte		 $1F, $A2, $AF, $10, $00, $00, $00, $00
	.byte		 $1F, $A2, $2A, $F1, $00, $00, $00, $00
	.byte		 $1F, $A2, $32, $10, $00, $00, $00, $00
	.byte		 $1F, $A2, $31, $00, $00, $00, $00, $00
	.byte		 $1F, $A2, $10, $00, $00, $00, $00, $00
	.byte		 $1F, $A1, $00, $00, $00, $00, $00, $00
	.byte		 $1F, $10, $00, $00, $00, $00, $00, $00
	.byte		 $11, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	.byte		 $00, $00, $00, $00, $00, $00, $00, $00
	
	
coloursRed:
;	.byte		$00, $00, $CA, $66, $BB, $55, $D1, $AE
	.byte		$00, $00, $CA, $CA, $BB, $55, $D1, $AE
	.byte		$9B, $00, $DD, $B5, $B8, $0B, $AA, $8B
coloursGreen:
;	.byte		$00, $00, $13, $AD, $F3, $EC, $E0, $5F
	.byte		$00, $00, $33, $13, $F3, $EC, $E0, $5F
	.byte		$47, $00, $39, $B5, $B8, $4F, $D9, $8B
coloursBlue:
;	.byte		$00, $00, $62, $FF, $8B, $85, $79, $C7
	.byte		$00, $00, $78, $62, $8B, $85, $79, $C7
	.byte		$81, $00, $78, $B5, $B8, $CA, $FE, $8B 
	.endif
;-------------------------------------------------------------------------------
		

;-------------------------------------------------------------------------------
initMouse:
;-------------------------------------------------------------------------------
	.if	C64_MODE
		LDX	#$3E
@loop:
		LDA	spritePtr, X
		STA	spriteMemD, X
		DEX
		BPL	@loop

		LDA	#$0A
		STA	vicSprClr0
	.else
		LDX	#$00
@loop:
		LDA	spritePtr, X
		STA	spriteMemD, X
		INX
		CPX	#$B0
		BNE	@loop

		LDA	#$00
		STA	vicSprClr0
	.endif
	
		LDA	#$0D
		STA	spritePtr0
		
		LDA	vicSprEnab
		ORA	#$01
		STA	vicSprEnab
		
	.if	.not C64_MODE
		LDX	#$0F
@l:
		LDA	coloursRed, X
		STA	$D180, X
		STA	$D190, X
		STA	$D1A0, X
		STA	$D1B0, X
		STA	$D1C0, X
		STA	$D1D0, X
		STA	$D1E0, X
		STA	$D1F0, X
		
		LDA	coloursGreen, X
		STA	$D280, X
		STA	$D290, X
		STA	$D2A0, X
		STA	$D2B0, X
		STA	$D2C0, X
		STA	$D2D0, X
		STA	$D2E0, X
		STA	$D2F0, X
		
		LDA	coloursBlue, X
		STA	$D380, X
		STA	$D390, X
		STA	$D3A0, X
		STA	$D3B0, X
		STA	$D3C0, X
		STA	$D3D0, X
		STA	$D3E0, X
		STA	$D3F0, X
		
		DEX
		BPL @l

		;; Enable upper-half of pallete selection for
		;; 16-colour sprites
		LDA	$D049
		ORA	#$F0
		STA	$D049
		LDA	$D04B
		ORA	#$F0
		STA	$D04B

		LDA	#$01				;Enable 16colour sprite 0
		STA	$D06B

	.endif
		
		
	.if	C64_MODE
		LDA	IIRQ + 1
		CMP	#>MIRQ
		BEQ	L90
	.endif
		
;		PHP
;		SEI
		
	.if	C64_MODE
		LDA	IIRQ
		STA	IIRQ2
		LDA	IIRQ + 1
		STA	IIRQ2 + 1
	.endif

		LDA	#<MIRQ
		STA	IIRQ
		LDA	#>MIRQ
		STA	IIRQ + 1
;
;		PLP
L90:    
		JSR	CMOVEX
		JSR	CMOVEY

	.if  C64_MODE
		LDA	#$00
		STA	flgMse1351
	.else
;	Detect Amiga type mouse connected
;	NB:  This may not work in the future
		LDA	$D61B			
		ORA	#$01
		STA	$D61B

		LDA	$D61B			
		AND	#$01
		EOR	#$01
		STA	flgMse1351
	.endif

		RTS

;-------------------------------------------------------------------------------
	.if	C64_MODE
IIRQ2:
	.word		$0000
	.endif
	
;-------------------------------------------------------------------------------
MIRQ:    
;-------------------------------------------------------------------------------
		CLD		  		; JUST IN CASE.....
	
	.if	.not	C64_MODE
		PHP
		PHA
		PHX
		PHY
		PHZ
	.endif


;	  .if	DEBUG_MODE
;			LDA	#$0E
;			STA	$D020
;	  .endif


;Do help text switching
		LDA	progTermint
		BNE	@cont

		LDA	#$00
		CMP	infoCntr + 1
		BNE	@cont0
		CMP	infoCntr
		BNE	@cont0

	;; Update help message approximately every 5 seconds
		LDA	#<350
		STA	infoCntr
		LDA	#>350
		STA	infoCntr + 1
		
		LDA	currInfoTxt
		ASL
		TAX
		LDA	infoTexts, X
		STA	ptrIRQTemp0
		LDA	infoTexts + 1, X
		STA	ptrIRQTemp0 + 1
		
		LDY	#$1A
@loop:
		LDA	(ptrIRQTemp0), Y
		JSR	asciiToCharROM
		ORA	#$80
		STA	$07C0, Y
		DEY
		BPL	@loop
		
		INC	currInfoTxt
		LDA	currInfoTxt
		CMP	#count_infoTexts
		BNE	@cont0
		
		LDA	#$00
		STA	currInfoTxt
	
@cont0:
		SEC
		LDA	infoCntr
		SBC	#$01
		STA	infoCntr
		LDA	infoCntr + 1
		SBC	#$00
		STA	infoCntr + 1

;Do cursor blinking
		LDA	crsrIsDispl
		BEQ	@cont
		
		DEC	blinkCntr
		BNE	@cont
		
		LDA	#$10
		STA	blinkCntr
		
		LDY	#$00
		LDA	(ptrCrsrSPos), Y
		EOR	#$80
		STA	(ptrCrsrSPos), Y
	
@cont:

; Record the state of the buttons.
; Avoid crosstalk between the keyboard and the mouse.

		LDY	#%00000000		    ;Set ports A and B to input
		STY	CIA1_DDRB
		STY	CIA1_DDRA			;Keyboard won't look like mouse
		LDA	CIA1_PRB			 ;Read Control-Port 1
		DEC	CIA1_DDRA			;Set port A back to output
		EOR	#%11111111		    ;Bit goes up when button goes down
		STA	Buttons
		BEQ	@L0				 ;(bze)
		DEC	CIA1_DDRB			;Mouse won't look like keyboard
		STY	CIA1_PRB			 ;Set "all keys pushed"

@L0:    
		JSR	ButtonCheck
		
		LDA	SID_ADConv1		   ;Get mouse X movement
		LDY	flgMse1351
		BEQ	@full_x
		
		AND	#$7E
			
@full_x:	
		LDY	OldPotX
		JSR	MoveCheck			;Calculate movement vector
		STY	OldPotX

; Skip processing if nothing has changed

		BCC	@SkipX

; Calculate the new X coordinate (--> a/y)
		ASL
		PHA
		TXA
		ROL
		TAX
		PLA

		CLC
		ADC	XPosNew

		TAY					    ;Remember low byte
		TXA
		ADC	XPosNew+1
		TAX

; Limit the X coordinate to the bounding box

		CPY	XMin
		SBC	XMin+1
		BPL	@L1
		LDY	XMin
		LDX	XMin+1
		JMP	@L2
@L1:   	
		TXA

		CPY	XMax
		SBC	XMax+1
		BMI	@L2
		LDY	XMax
		LDX	XMax+1
@L2:    
		STY	XPosNew
	    STX	XPosNew+1
		jsr historesisCheck

; Move the mouse pointer to the new X pos

		TYA
		JSR	CMOVEX
		
		LDA	mouseCheck
		BNE	@SkipX

		LDA	#$01
		STA	mouseCheck

; Calculate the Y movement vector

@SkipX: 
		LDA	SID_ADConv2		   ;Get mouse Y movement
		LDY	flgMse1351
		BEQ	@full_y
		
		AND	#$7E
			
@full_y:	
		LDY	OldPotY
		JSR	MoveCheck			;Calculate movement
		STY	OldPotY

; Skip processing if nothing has changed

		BCC	@SkipY

; Calculate the new Y coordinate (--> a/y)

		ASL
		PHA
		TXA
		ROL
		TAX
		PLA

		STA	OldValue
		LDA	YPosNew
		SEC
		SBC	OldValue

		TAY
		STX	OldValue
		LDA	YPosNew+1
		SBC	OldValue
		TAX

; Limit the Y coordinate to the bounding box

		CPY	YMin
		SBC	YMin+1
		BPL	@L3
		LDY	YMin
		LDX	YMin+1
		JMP	@L4
@L3:    
		TXA

		CPY	YMax
		SBC	YMax+1
		BMI	@L4
		LDY	YMax
		LDX	YMax+1
@L4:   	
		STY	YPosNew
		STX	YPosNew+1

		jsr historesisCheck

; Move the mouse pointer to the new Y pos

		TYA
		JSR	CMOVEY

		LDA	mouseCheck
		BNE	@SkipY
		
		LDA	#$01
		STA	mouseCheck

; Done

@SkipY: 
;		JSR	CDRAW

;dengland	What is this for???
		CLC

	.if	.not C64_MODE
		LDA	$DC0D
		
		PLZ
		PLY
		PLX
		PLA
		PLP
		RTI
	.else
		JMP	(IIRQ2)
	.endif
	


historesisCheck:
	;; Dont actually update mouse unless it has moved more than 1 px in the same direction
	
	lda XPosNew
	cmp XPosPending
	bne @XChanged
	lda XPosNew+1
	cmp XPosPending+1
	beq @updatedXDirection
@XChanged:
	;;  Get sign of difference between XPos and XPosNew
	lda XPosNew
	sec
	sbc XPosPending
	lda XPosNew+1
	sbc XPosPending+1

	pha
	lda XPosNew
	sta XPosPending
	lda XPosNew+1
	sta XPosPending+1
	pla	
	
	;; Is the direction different to last time?
	and #$80
	sta DirectionTemp
	eor XDirection
	bne @UpdateXDirection
	;; Direction same, so update X position
	lda XPosNew+1
	sta XPos+1
	lda XPosNew
	sta XPos
	jmp @updatedXDirection
@UpdateXDirection:
	;;  Don't update X, but do update the direction of last movement
	lda DirectionTemp
	sta XDirection
@updatedXDirection:

	lda YPosNew
	cmp YPosPending
	bne @YChanged
	lda YPosNew+1
	cmp YPosPending+1
	beq @updatedYDirection
@YChanged:

	;;  Get sign of difference between YPos and YPosNew
	lda YPosNew
	sec
	sbc YPosPending
	lda YPosNew+1
	sbc YPosPending+1

	pha
	lda YPosNew
	sta YPosPending
	lda YPosNew+1
	sta YPosPending+1
	pla	
	
	;; Is the direction different to last time?
	and #$80
	sta DirectionTemp
	eor YDirection
	bne @UpdateYDirection
	;; Direction same, so update Y position
	lda YPosNew+1
	sta YPos+1
	lda YPosNew
	sta YPos
	jmp @updatedYDirection
@UpdateYDirection:
	;;  Don't update Y, but do update the direction of last movement
	lda DirectionTemp
	sta YDirection
@updatedYDirection:

	rts


;-------------------------------------------------------------------------------
MoveCheck:
; Move check routine, called for both coordinates.
;
; Entry:	   y = old value of pot register
;			a = current value of pot register
; Exit:	    y = value to use for old value
;			x/a = delta value for position
;-------------------------------------------------------------------------------
		STY	OldValue
		STA	NewValue
		LDX	#$00

		SEC				; a = mod64 (new - old)
		SBC	OldValue

	cmp #$3f
	bcs @notPositiveMovement
	LDY NewValue
	LDX #0
		SEC
	RTS
@notPositiveMovement:
	cmp #$c0
	bcc @notNegativeMovement
		LDY	NewValue
	ldx #$ff
		SEC
		RTS

@notNegativeMovement:
	ldy NewValue
		TXA					    ; A = $00
		CLC
		RTS


;-------------------------------------------------------------------------------
ButtonCheck:
;-------------------------------------------------------------------------------
		LDA	Buttons
		CMP	ButtonsOld
		BEQ	@done
		
		AND	#buttonLeft
		BNE	@testRight
		
		LDA	ButtonsOld
		AND	#buttonLeft
		BEQ	@testRight
		
		LDA	#$01
		STA	ButtonLClick
		
@testRight:
		AND	#buttonRight
		BNE	@done
		
		LDA	ButtonsOld
		AND	#buttonRight
		BEQ	@done
		
		LDA	#$01
		STA	ButtonRClick

@done:
		LDA	Buttons
		STA	ButtonsOld
		RTS


;-------------------------------------------------------------------------------
CMOVEX:
;-------------------------------------------------------------------------------
		CLC
		LDA	XPos
		ADC	#offsX
		STA	tempValue
		LDA	XPos + 1
		ADC	#$00
		STA	tempValue + 1
	
		LDA	tempValue
		STA	VICXPOS
		LDA	tempValue + 1
		CMP	#$00
		BEQ	@unset
	
		LDA	VICXPOSMSB
		ORA	#$01
		STA	VICXPOSMSB
		RTS
	
@unset:
		LDA	VICXPOSMSB
		AND	#$FE
		STA	VICXPOSMSB
		RTS
	
;-------------------------------------------------------------------------------
CMOVEY:
;-------------------------------------------------------------------------------
		CLC
		LDA	YPos
		ADC	#offsY
		STA	tempValue
		LDA	YPos + 1
		ADC	#$00
		STA	tempValue + 1
	
		LDA	tempValue
		STA	VICYPOS
	
		RTS


;-------------------------------------------------------------------------------
;Convienience values
;-------------------------------------------------------------------------------
screenRowsLo:
			.byte	<$0400, <$0428, <$0450, <$0478, <$04A0
			.byte	<$04C8, <$04F0, <$0518, <$0540, <$0568
			.byte	<$0590, <$05B8, <$05E0, <$0608, <$0630
			.byte	<$0658, <$0680, <$06A8, <$06D0, <$06F8
			.byte	<$0720, <$0748, <$0770, <$0798, <$07C0

screenRowsHi:
			.byte	>$0400, >$0428, >$0450, >$0478, >$04A0
			.byte	>$04C8, >$04F0, >$0518, >$0540, >$0568
			.byte	>$0590, >$05B8, >$05E0, >$0608, >$0630
			.byte	>$0658, >$0680, >$06A8, >$06D0, >$06F8
			.byte	>$0720, >$0748, >$0770, >$0798, >$07C0

colourRowsLo:
			.byte	<$D800, <$D828, <$D850, <$D878, <$D8A0
			.byte	<$D8C8, <$D8F0, <$D918, <$D940, <$D968
			.byte	<$D990, <$D9B8, <$D9E0, <$DA08, <$DA30
			.byte	<$DA58, <$DA80, <$DAA8, <$DAD0, <$DAF8
			.byte	<$DB20, <$DB48, <$DB70, <$DB98, <$DBC0

colourRowsHi:
			.byte	>$D800, >$D828, >$D850, >$D878, >$D8A0
			.byte	>$D8C8, >$D8F0, >$D918, >$D940, >$D968
			.byte	>$D990, >$D9B8, >$D9E0, >$DA08, >$DA30
			.byte	>$DA58, >$DA80, >$DAA8, >$DAD0, >$DAF8
			.byte	>$DB20, >$DB48, >$DB70, >$DB98, >$DBC0


;-------------------------------------------------------------------------------
heap0:
;dengland
;	Must be at end of code
;-------------------------------------------------------------------------------
