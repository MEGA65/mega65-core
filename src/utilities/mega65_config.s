;===============================================================================
;M65 Configuration Utility
;-------------------------
;
;Version 00.99 alpha
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

	.macro  	.defPStr Arg
	.byte   	.strlen(Arg), Arg
        .endmacro
	
;	Set this define to 1 to run in "C64 mode" (uses the Kernal and will run
;	on a C64, using only C64 features).  Set to 0 to run in "M65 mode" 
;	(doesn't use Kernal, uses M65 features).  This is for the sake of 
;	debugging.
	.define		C64_MODE	0
	
;	Set this to use certain other debugging features
	.define		DEBUG_MODE	0
	
	.if		C64_MODE
	.setcpu 	"6502"
	.else
	.setcpu		"4510"
	.endif
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;Constants
;-------------------------------------------------------------------------------
optLineOffs	=	$04
optLineMaxC	=	(25 - optLineOffs - 2)
tabMaxCount	=	$04			;Don't include "Save".


optDfltBase	=	$C000
optSessBase	=	$C200


	.if	C64_MODE
IIRQ    	= 	$0314
	.else
IIRQ    	= 	$FFFE
	.endif

VIC     	= 	$D000         		; VIC REGISTERS
SID     	= 	$D400         		; SID REGISTERS
SID_ADConv1    	= 	SID + $19
SID_ADConv2    	= 	SID + $1A

spriteMemD	=	$0340
spritePtr0	=	$07F8
vicSprClr0	= 	$D027
vicSprEnab	= 	$D015
vicSpr16Col	=	$D06B
vicSprExYEn	=	$D055
vicSprExXEn	=	$D057
vicSprBitPlaneEn0to3=	$D049

CIA1_DDRA	=	$DC02
CIA1_DDRB	=	$DC03
CIA1_PRB	=	$DC01

offsX		=	24
offsY		=	50
buttonLeft	=	$10
buttonRight	=	$01


;
VICXPOS    	= 	VIC + $00      		; LOW ORDER X POSITION
VICYPOS    	= 	VIC + $01      		; Y POSITION
VICXPOSMSB 	=	VIC + $10      		; BIT 0 IS HIGH ORDER X POSITION


	.if	C64_MODE
keyF1		= 	$85
keyF2		=	$89
keyF3		=	$86
keyF4		=	$8A
keyF5		=	$87
keyF6		=	$8B
keyF7		=	$88
keyF8		=	$8C
	.else
keyF1		= 	$F1
keyF2		=	$F2
keyF3		=	$F3
keyF4		=	$F4
keyF5		=	$F5
keyF6		=	$F6
keyF7		=	$F7
keyF8		=	$F8
keyF9		=	$F9
;keyF10		=	$FA			;Doesn't work.
	.endif

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

ptrOptsTemp	= 	$FB
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
	.assert         * = $080D, error, "BASIC Loader incorrect!"
bootstrap:
		JMP	init
;-------------------------------------------------------------------------------


;-------------------------------------------------------------------------------
;Global data
;-------------------------------------------------------------------------------
;signature for utility menu
	.asciiz 	"PROP.M65U.NAME=CONFIGURE MEGA65"
	
	
headerLine:
	.byte		"          mega65 configuration          "

headerColours:
	.byte		$06, $06, $05, $05, $07, $07, $02, $02
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$02, $02, $07, $07, $05, $05, $06, $06
	
menuLine:
	.byte		"systemBdiskBvideoBaudio             save"
footerLine:
	.byte		"                                page  / "

helpText0:
	.byte		"version 00.99a             "
helpText1:
	.byte		"cursor up/down to navigate "
helpText2:
	.byte		"f1/f2 to change tabs       "
helpText3:
	.byte		"f3/f4 to change pages      "
helpText4:
	.byte		"f7 for save and exit       "
helpText5:
	.byte		"f8 to apply settings       "
helpText6:
	.byte		"space or return for toggle "
helpText7:
	.byte		"any key for data entry     "

helpTexts:
	.word		helpText0, helpText1, helpText2, helpText3
	.word		helpText4, helpText5, helpText6, helpText7

currHelpTxt:
	.byte		$00

saveConfExit0:
	.defPStr	"are you sure you wish to exit"
saveConfExit1:
	.defPStr	"without saving?"
saveConfAppl0:
	.defPStr	"are you sure you wish to apply"
saveConfAppl1:
	.defPStr	"the current settings?"
saveConfSave0:
	.defPStr	"are you sure you wish to save"
saveConfSess0:
	.defPStr	"for this boot and exit?"
saveConfDflt0:
	.defPStr	"as the defaults and exit?"

errorLine:
	.byte		"a version mismatch has been detected!   "

;	This will tell us whats happening on each line so we can use quick 
;	look-ups for the mouse etc.  Only optLineMaxC of the lines on the 
;	screen can be used (see above).  This will need to be adhered to by
;	the options lists!
pageOptions:
	.repeat		optLineMaxC
	.byte		$FF
	.endrep
	

	.include 	"mega65_config.inc"


;-------------------------------------------------------------------------------
init:
;-------------------------------------------------------------------------------

; 	Init screen
		LDA 	#$0B			;Border colour
		STA 	$D020
		LDA 	#$00			;Screen colour
		STA 	$D021

		LDA 	#$14			; Set screen address to $0400, upper-case font
	        STA	$D018  
	
	.if	C64_MODE
;	Upper-case
		LDA 	#$8E			;Print to-upper-case character
		JSR 	$FFD2
		LDA	#$08			;Disable change of case
		JSR	$FFD2
	.endif
	
		SEI             		;disable the interrupts
	
		JSR	initState		
		
		JSR	hypervisorLoadOrResetConfig
		
		.if	.not DEBUG_MODE	
		JSR	checkMagicBytes
	.endif
		
		JSR	initMouse

		CLI				;enable the interrupts
		
		LDA	#$00
		STA	tabSelected
		STA	progTermint
		
		LDA	#$00
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
		
@terminate:
		RTS

@cont:
		JSR	hotTrackMouse

		LDA	ButtonLClick
		BEQ	@tstKeys
		
		JSR	processMouseClick

@tstKeys:
	.if	C64_MODE
		JSR 	$FFE4			;call get character from input
		BEQ	@inputLoop
	.else
		LDA	$D610
		BEQ	@inputLoop
		
		LDX	#$00
		STX	$D610
	.endif
		
@tstDownKey:
		CMP	#$11
		BNE	@tstUpKey
		
		JSR	moveSelectDown	
		JMP	@inputLoop
		
@tstUpKey:
		CMP	#$91
		BNE	@tstF1Key
		
		JSR	moveSelectUp
		JMP	@inputLoop
				
@tstF1Key:
		CMP	#keyF1
		BNE	@tstF2Key
		
		JSR	moveTabLeft
		JMP	main
				
@tstF2Key:
		CMP	#keyF2
		BNE	@tstF3Key
		
		JSR	moveTabRight
		JMP	main
		
@tstF3Key:
		CMP	#keyF3
		BNE	@tstF4Key
		
		JSR	moveNextPage
		JMP	main
		
@tstF4Key:
		CMP	#keyF4
		BNE	@tstF7Key
		
		JSR	movePriorPage
		JMP	main
		
@tstF7Key:
		CMP	#keyF7
		BNE	@tstF8Key
		
		LDA	#tabMaxCount
		STA	tabSelected
		JSR	setupSelectedTab
		
		JMP	main
		
@tstF8Key:
		CMP	#keyF8
		BNE	@otherKey
		
		JSR	doJumpApplyNow
		JMP	main
		
				
@otherKey:
	.if	DEBUG_MODE
		STA	$0401
	.endif

		LDX	crsrIsDispl
		BEQ	@tstSaveTab
		
		JSR	doTestStringKeys
		JMP	@inputLoop
		
@tstSaveTab:
		LDX	tabSelected
		CPX	#tabMaxCount
		BNE	@toggleInput
		
		JSR	doTestSaveKeys
		JMP	@inputLoop
		
@toggleInput:
		JSR	doTestToggleKeys
		JMP	@inputLoop


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

@halt:
		JMP	@halt

@exit:
		RTS


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
hypervisorLoadOrResetConfig:	
;-------------------------------------------------------------------------------
		;; Load current options sector from SD card using Hypervisor trap		
		
		;; Hypervisor trap to read config
		LDA	#$00
		STA 	$D642
		NOP	     ; Required after hypervisor traps, as PC skips one
		
		;; Copy from sector buffer to optDfltBase
		LDA	#$81
		STA	$D680
		LDX	#$00
@rl:		LDA 	$DE00, X
		STA	optDfltBase, X
		LDA	$DF00, X
		STA	optDfltBase+$100, X
		INX
		BNE	@rl
		;; Demap sector buffer when done
		LDA	#$82
		STA	$D680

		;; Check for empty config
		LDA	optDfltBase+0
		ORA	optDfltBase+1
		bne	@notempty

		;; Empty config, so zero out and reset
		;; A=0, X=0 here already
@rl2:		STA	optDfltBase, X
		STA	optDfltBase+$100,X
		DEX
		BNE @rl2
		LDA	#$01   	; major and minor version
		STA	optDfltBase
		STA	optDfltBase+1
		
@notempty:
		RTS
		
;-------------------------------------------------------------------------------
readDefaultOpts:
;-------------------------------------------------------------------------------
		jsr hypervisorLoadOrResetConfig

		LDA	#<optDfltBase
		STA	ptrOptionBase0
		LDA	#>optDfltBase
		STA	ptrOptionBase0 + 1

		LDX	#$00
@loopSystem:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	systemPageIndex, X
		STA	ptrOptsTemp
		LDA	systemPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#systemPageCnt
		BNE	@loopSystem
		

		LDX	#$00
@loopDisk:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	diskPageIndex, X
		STA	ptrOptsTemp
		LDA	diskPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doReadOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#diskPageCnt
		BNE	@loopDisk


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
		LDA	(ptrTempData), Y
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
		BNE	@unknownOpt
		
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
		LDA	(ptrTempData), Y
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
		
		RTS


;-------------------------------------------------------------------------------
saveDefaultOpts:
;-------------------------------------------------------------------------------
		LDA	#<optDfltBase
		STA	ptrOptionBase0
		LDA	#>optDfltBase
		STA	ptrOptionBase0 + 1

		JSR	doSaveOptions

		RTS


;-------------------------------------------------------------------------------
doSaveOptions:
;-------------------------------------------------------------------------------
		LDX	#$00
@loopSystem:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	systemPageIndex, X
		STA	ptrOptsTemp
		LDA	systemPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#systemPageCnt
		BNE	@loopSystem


		LDX	#$00
@loopDisk:
		STX	readTemp3
		TXA
		ASL
		TAX
		LDA	diskPageIndex, X
		STA	ptrOptsTemp
		LDA	diskPageIndex + 1, X
		STA	ptrOptsTemp + 1

		JSR	doSaveOptList
		BCS	@error
		
		LDX	readTemp3
		INX
		CPX	#diskPageCnt
		BNE	@loopDisk

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
		LDA	(ptrTempData), Y
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
		STA	(ptrTempData), Y
		
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
		BNE	@unknownOpt
		
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
		STA	(ptrTempData), Y
		INC	readTemp0
		
		INX
		CPX	readTemp1
		BNE	@loopStr
		
		LDY	readTemp2
	
		CLC
		RTS

@unknownOpt:
		SEC
		RTS
		

;-------------------------------------------------------------------------------
doJumpApplyNow:
;-------------------------------------------------------------------------------
		LDA	#tabMaxCount
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
		LDX	#$00
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
doPerformSaveAction:
;-------------------------------------------------------------------------------
		LDX	saveSlctOpt
		BNE	@tstSaveApply
		
		LDA	#$01
		STA	progTermint
		RTS

@tstSaveApply:
		CPX	#$02
		BNE	@tstSaveThis
		
		JSR	saveSessionOpts
		RTS
		
@tstSaveThis:
		CPX	#$04
		BNE	@tstSaveSys
		
		JSR	saveSessionOpts
		LDA	#$01
		STA	progTermint
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
		
		JSR	setupSystemPage0
		RTS
		
@tstDisk:
		CMP	#$01
		BNE	@tstVideo
		
		JSR	setupDiskPage0
		RTS
		
@tstVideo:
		CMP	#$02
		BNE	@tstAudio
		
		JSR	setupVideoPage0
		RTS
		
@tstAudio:
		CMP	#$03
		BNE	@save
		
		JSR	setupAudioPage0
		RTS
		
@save:
		JSR	setupSavePage0
		RTS


;-------------------------------------------------------------------------------
highlightSelectedTab:
;-------------------------------------------------------------------------------
		LDA	tabSelected
		CMP	#$00
		BNE	@tstDisk
		
		JSR	highlightSystemTab
		RTS
		
@tstDisk:
		CMP	#$01
		BNE	@tstVideo
		
		JSR	highlightDiskTab
		RTS
		
@tstVideo:
		CMP	#$02
		BNE	@tstAudio
		
		JSR	highlightVideoTab
		RTS
		
@tstAudio:
		CMP	#$03
		BNE	@save
		
		JSR	highlightAudioTab
		RTS
		
@save:
		JSR	highlightSaveTab
		RTS


;-------------------------------------------------------------------------------
setupSystemPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#systemPageCnt
		STA	currPageCnt
		
		LDA	#<systemPageIndex
		STA	ptrPageIndx
		LDA	#>systemPageIndex
		STA	ptrPageIndx + 1
		
		RTS

;-------------------------------------------------------------------------------
highlightSystemTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$00
		LDA	#$01
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$07
		BNE	@loop

		RTS


;-------------------------------------------------------------------------------
setupDiskPage0:
;-------------------------------------------------------------------------------
		LDA	#$00
		STA	pgeSelected
		LDA	#diskPageCnt
		STA	currPageCnt
		
		LDA	#<diskPageIndex
		STA	ptrPageIndx
		LDA	#>diskPageIndex
		STA	ptrPageIndx + 1
		
		RTS


;-------------------------------------------------------------------------------
highlightDiskTab:
;-------------------------------------------------------------------------------
		LDX	#$01
		LDA	colourRowsLo, X		;Get colour RAM ptr for line #
		STA	ptrTempData
		LDA	colourRowsHi, X
		STA	ptrTempData + 1		
		
		LDY	#$07
		LDA	#$01
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$0C
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
		
		LDY	#$0C
		LDA	#$01
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$12
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
		
		LDY	#$12
		LDA	#$01
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$17
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
		LDA	#$01
@loop:
		STA	(ptrTempData), Y
		INY
		CPY	#$28
		BNE	@loop
		
		RTS
		
		
;-------------------------------------------------------------------------------
mouseTemp0:
	.word		$0000
mouseXCol:
	.byte		$00
mouseYRow:
	.byte		$00


;-------------------------------------------------------------------------------
hotTrackMouse:
;-------------------------------------------------------------------------------
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
		CMP	mouseYRow
		BEQ	@exit
		
		STA	mouseYRow
		
		CMP	#optLineOffs
		BCS	@tstInOptions
		

		CMP	#$01
		BNE	@exit

;***fixme Could do a nice little hot track on the menu, too.
		RTS
		
@tstInOptions:
		CMP	#(optLineMaxC + optLineOffs + 1)
		BCC	@isInOptions
		
		RTS

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

		LDA	#$0B
		JSR	doHighlightSelected

		PLA
		TAX

		STX	selectedOpt
		LDA	#$01
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

		LDA	#$0B
		JSR	doHighlightSelected

		PLA
		TAX

		STX	selectedOpt
		LDA	#$01
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		
		LDA	tabSelected
		CMP	#tabMaxCount
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
		BCS	@tstDiskTab
		
		LDA	#$00
		JMP	@tstUpdate
		
@tstDiskTab:
		CMP	#$0C
		BCS	@tstVideoTab
		
		LDA	#$01
		JMP	@tstUpdate
		
@tstVideoTab:
		CMP	#$12
		BCS	@tstAudioTab
		
		LDA	#$02
		JMP	@tstUpdate
		
@tstAudioTab:
		CMP	#$18
		BCS	@tstSaveTab
		
		LDA	#$03
		JMP	@tstUpdate

@tstSaveTab:
		CMP	#$24
		BCC	@exit
		
		LDA	#$04
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
		BNE 	@tstPrior
		
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
		
		LDX	#tabMaxCount - 1
		
@done:
		STX	tabSelected
		JSR	setupSelectedTab
		
		RTS


;-------------------------------------------------------------------------------
moveNextPage:
;-------------------------------------------------------------------------------
		LDX	tabSelected
		CPX	#tabMaxCount
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
		CPX	#tabMaxCount
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

		LDA	#$0B
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
		
		LDA	#$01
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
		
		LDA	#$0B
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
		
		LDA	#$01
		JSR	doHighlightSelected
		
		JSR	doUpdateSelected
		
@exit:
		RTS
		
		
;-------------------------------------------------------------------------------
doUpdateSelected:
;-------------------------------------------------------------------------------
		LDA	crsrIsDispl
		CMP	#$01
		BNE	@begin

		LDA	#$00
		STA	crsrIsDispl
		
		LDY	#$00
		LDA	(ptrCrsrSPos), Y
		ORA	#$80
		STA   	(ptrCrsrSPos), Y

@begin:
		LDX	selectedOpt
		LDA	pageOptions, X
		AND	#$F0
		CMP	#$30
		BNE	@exit
		
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
		
@exit:
		
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
		LDA	#$D7
		PHA
		
		JMP	@update
		
@isUnSet:
		LDA	#$D7
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
		
		JSR 	clearScreen
		
		JSR	highlightSelectedTab
		JSR	updateFooter
		
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
		
		CLC
		TYA
		ADC	ptrOptsTemp
		STA	ptrOptsTemp
		LDA	ptrOptsTemp + 1
		ADC	#$00
		STA	ptrOptsTemp + 1
		
		INC	optTempIndx

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
@dispOptionsChk:
		LDA	tabSelected
		CMP	#tabMaxCount
		BNE	@updateStd
	
		LDA	pgeSelected
		CMP	#$01
		BNE	@updateStd
		
		JSR	updateSaveConfirm
		JMP	@cont		
		
@updateStd:
		LDX	#$00
		LDA	pageOptions, X
		CMP	#$FF
		BEQ	@exit
		
		
@cont:
		STX	selectedOpt

		LDA	#$01
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
updateSaveConfirm:
;-------------------------------------------------------------------------------
		LDX	saveSlctOpt
		BNE	@tstSaveApply
		
		LDA	#<saveConfExit0
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

@tstSaveApply:
		CPX	#$02
		BNE	@tstSaveThis
		
		LDA	#<saveConfAppl0
		STA	ptrOptsTemp
		LDA	#>saveConfAppl0
		STA	ptrOptsTemp + 1
		
		LDY	#optLineOffs
		
		JSR	dispCentreText
		
		LDA	#<saveConfAppl1
		STA	ptrOptsTemp
		LDA	#>saveConfAppl1
		STA	ptrOptsTemp + 1
		
		LDY	#(optLineOffs + 2)
		
		JSR	dispCentreText
		JMP	@exit
		
@tstSaveThis:
		CPX	#$04
		BNE	@tstSaveSys
		
		LDA	#<saveConfSave0
		STA	ptrOptsTemp
		LDA	#>saveConfSave0
		STA	ptrOptsTemp + 1
		
		LDY	#optLineOffs
		
		JSR	dispCentreText
		
		LDA	#<saveConfSess0
		STA	ptrOptsTemp
		LDA	#>saveConfSess0
		STA	ptrOptsTemp + 1
		
		LDY	#(optLineOffs + 2)
		
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
		STA 	(ptrCurrHeap), Y
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
		TAX 				;Keep whole byte in .X
		
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
		BNE	@unknownOpt
		
		LDX	optTempLine		;Blank line 
		LDA	#$FF
		STA	pageOptions, X
		INC	optTempLine		;and next line
		CLC
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
		LDA	#$0C
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
		BEQ 	@cont
		
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
		
	
dispOptTemp0:
	.byte		$00
dispOptTemp1:
	.byte		$00
dispOptTemp2:
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
		
		LDA	#$0C			;Set colour for opt indicator
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
		
		LDA	#$0C			;Set colour for opt indicator
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

		LDA	#$D7			;unset opt indicator
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
		LDA	screenRowsLo, Y		;Get screen RAM ptr for line #
		STA	ptrTempData
		LDA	screenRowsHi, Y
		STA	ptrTempData + 1		
		
		LDY	#$00
		LDA	(ptrOptsTemp), Y
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
		
		RTS
		

;-------------------------------------------------------------------------------
	.if	.not	C64_MODE
clrScreenDAT:
	.byte		$0A			;F018A
	.byte		$00
	.byte 		$03 			; fill non-chained job 
	.word 		$03E8 			; number of bytes to copy
	.word 		$00A0 			; source address
	.byte 		$00 			; source bank number / direction
	.word 		$0400 			; destination address
	.byte 		$00 			; destination bank number / direction
	.word 		$0000 			; modulo	

clrColourDAT:
	.byte		$0A			;F018A
	.byte		$00
	.byte 		$03 			; fill non-chained job 
	.word 		$03E8 			; number of bytes to copy
	.word 		$000B 			; source address
	.byte 		$00 			; source bank number / direction
	.word 		$F800 			; destination address
	.byte 		$01 			; destination bank number / direction
	.word 		$0000 			; modulo	
	.endif

;-------------------------------------------------------------------------------
clearScreen:
;-------------------------------------------------------------------------------
	.if 	C64_MODE
		LDX 	#$00
@loop0:	 
		LDA 	#$A0			;Screen memory
		STA 	$0400, X
		STA 	$0500, X
		STA 	$0600, X
		STA 	$0700, X
		LDA 	#$0B			;Colour memory
		STA 	$D800, X
		STA 	$D900, X
		STA 	$DA00, X
		STA 	$DB00, X
		INX
		BNE 	@loop0
		
;	The above goes overboard and clears out the sprite pointers, too.  So, 
;	we need to restore it.
		LDA	#$0D
		STA	spritePtr0
	.else
		LDA 	#$00
		STA 	$D702
		STA 	$D704
		LDA 	#>clrScreenDAT
		STA 	$D701
		LDA 	#<clrScreenDAT
		STA 	$D705		

		LDA 	#$00
		STA 	$D702
		STA 	$D704
		LDA 	#>clrColourDAT
		STA 	$D701
		LDA 	#<clrColourDAT
		STA 	$D705		
	.endif

; 	Header and footer
		LDY 	#39
@loop1:	 
		LDA 	headerLine, Y		
		JSR 	asciiToCharROM		;Convert header for screen 
		ORA 	#$80			;Output in reverse
		STA 	$0400, Y
		
		LDA	headerColours, Y
		STA	$D800, Y
		
		LDA 	menuLine, Y		
		JSR 	asciiToCharROM		;Convert menu for screen 
		ORA 	#$80			;Output in reverse
		STA 	$0428, Y
		
		LDA	#$0C
		STA	$D828, Y
		
		LDA 	footerLine, Y		
		JSR 	asciiToCharROM		;Convert footer for screen 
		ORA 	#$80			;Output in reverse
		STA 	$07C0, Y
		
		LDA	#$0C
		STA	$DBC0, Y
		
		DEY
		BPL 	@loop1

		RTS
		
		
;-------------------------------------------------------------------------------
asciiToCharROM:
;	Must be re-entrant in the case the IRQ handler calls while the main 
;	code also does.
;-------------------------------------------------------------------------------
; 	NUL ($00) becomes a space
		CMP 	#0
		BNE 	atc0
		LDA 	#$20
atc0:
;	@ becomes $00
		CMP 	#$40
		BNE 	atc1
		LDA 	#0
		RTS
atc1:
		CMP 	#$5B
		BCS 	atc2
;	A to Z -> leave unchanged
		RTS
atc2:
		CMP 	#$5B
		BCC 	atc3
		CMP 	#$60
		BCS 	atc3
;	[ \ ] ^ _ -> subtract $40
		SEC
		SBC	#$40

		RTS
atc3:
		CMP 	#$61
		BCC 	atc4
		CMP 	#$7B
		BCS 	atc4
;	a - z -> subtract $60
		SEC
		SBC	#$60
atc4:		
		RTS
		

;-------------------------------------------------------------------------------
inputToCharROM:
;-------------------------------------------------------------------------------
; 	NUL ($00) becomes a space
		CMP 	#0
		BNE 	@atc0
		LDA 	#$20
@atc0:
;	@ becomes $00
		CMP 	#$40
		BNE 	@atc1
		LDA 	#0
		RTS
@atc1:
		CMP 	#$5B
		BCS 	@atc2
		
		CMP	#$41
		BCC	@atc4
		
;	A to Z -> subtract $40
		SEC
		SBC	#$40
		
		RTS
@atc2:
		CMP 	#$5B
		BCC 	@atc3
		CMP 	#$60
		BCS 	@atc3
;	[ \ ] ^ _ -> subtract $40
		SEC
		SBC	#$40

		RTS
@atc3:
		CMP 	#$61
		BCC 	@atc4
		CMP 	#$7B
		BCS 	@atc4
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
		
		INY				;Skip past type, offset and 
		INY				;data
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
;	Enable enhanced registers
		LDA 	#$47			;M65 knock knock
		STA 	$D02F
		LDA 	#$53
		STA 	$D02F
		LDA	#65
		STA	$00
	.endif
				
;		SEI             		;disable the interrupts
		CLD             		;clear decimal mode

		;; Make sure no colour RAM @ $DC00, no sector buffer overlaying $DCxx/$DDxx
		LDA	#$00
		STA	$D030
		LDA	#$82
		STA	$D680
		
		LDA 	#$7F        		;disable all interrupts
		STA 	$DC0D       		;save VIA 1 ICR
		STA 	$DD0D       		;save VIA 2 ICR
		STA 	$DC00       		;save VIA 1 DRA, keyboard column drive
		LDA 	#$08        		;set timer single shot
		STA 	$DC0E       		;save VIA 1 CRA
		STA 	$DD0E       		;save VIA 2 CRA
		STA 	$DC0F       		;save VIA 1 CRB
		STA 	$DD0F       		;save VIA 2 CRB
		LDX 	#$00        		;set all inputs
		STX 	$DC03       		;save VIA 1 DDRB, keyboard row
		STX 	$DD03       		;save VIA 2 DDRB, RS232 port
		STX 	$D418       		;clear the volume and filter select register
		DEX             		;set X = $FF
		STX 	$DC02       		;save VIA 1 DDRA, keyboard column
		LDA 	#$07        		;DATA out high, CLK out high, ATN out high, RE232 Tx DATA
						;high, video address 15 = 1, video address 14 = 1
		STA 	$DD00       		;save VIA 2 DRA, serial port and video address
		LDA 	#$3F        		;set serial DATA input, serial CLK input
		STA 	$DD02       		;save VIA 2 DDRA, serial port and video address

	.if	C64_MODE
		LDA 	#$E6        		;set 1110 0110, motor off, enable I/O, enable KERNAL,
						;disable BASIC
	.else
		LDA	#$E5			;set 1110 0101 - motor off, enable IO
						;disable Kernal and BASIC
	.endif
						
		STA 	$01         		;save the 6510 I/O port
		LDA 	#$2F        		;set 0010 1111, 0 = input, 1 = output
		STA 	$00         		;save the 6510 I/O port direction register
;		LDA 	$02A6       		;get the PAL/NTSC flag
;		BEQ 	$FDEC       		;if NTSC go set NTSC timing
						;else set PAL timing
		LDA 	#$25
		STA 	$DC04       		;save VIA 1 timer A low byte
		LDA 	#$40
;		JMP 	$FDF3
; FDEC:		LDA 	#$95
;		STA 	$DC04       		;save VIA 1 timer A low byte
;		LDA 	#$42
; FDF3:
		STA 	$DC05       		;save VIA 1 timer A high byte

		LDA 	#$81        		;enable timer A interrupt
		STA 	$DC0D       		;save VIA 1 ICR
		LDA 	$DC0E       		;read VIA 1 CRA
		AND 	#$80        		;mask x000 0000, TOD clock
		ORA 	#$11        		;mask xxx1 xxx1, load timer A, start timer A
		STA 	$DC0E       		;save VIA 1 CRA

		LDA 	$DD00       		;read VIA 2 DRA, serial port and video address
		ORA 	#$10        		;mask xxx1 xxxx, set serial clock out low
		STA 	$DD00       		;save VIA 2 DRA, serial port and video address

;		CLI				;enable the interrupts

		RTS
		

;-------------------------------------------------------------------------------
;Mouse driver variables
;-------------------------------------------------------------------------------
OldPotX:        
	.byte    	0               	; Old hw counter values
OldPotY:        
	.byte    	0

XPos:           
	.word    	0               	; Current mouse position, X
YPos:           
	.word    	0               	; Current mouse position, Y
XMin:           
	.word    	0               	; X1 value of bounding box
YMin:           
	.word    	0               	; Y1 value of bounding box
XMax:           
	.word    	319               	; X2 value of bounding box
YMax:           
	.word    	199           		; Y2 value of bounding box
Buttons:        
	.byte    	0               	; button status bits
ButtonsOld:
	.byte		0
ButtonLClick:
	.byte		0
ButtonRClick:
	.byte		0

OldValue:       
	.byte    	0               	; Temp for MoveCheck routine
NewValue:       
	.byte    	0               	; Temp for MoveCheck routine

tempValue:	
	.word		0
	
blinkCntr:
	.byte		$10
	
helpCntr:
	.word		$0000

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
;-------------------------------------------------------------------------------
		

;-------------------------------------------------------------------------------
initMouse:
;-------------------------------------------------------------------------------
		LDX	#$3E
@loop:
		LDA	spritePtr, X
		STA	spriteMemD, X
		DEX
		BPL	@loop

		LDA	#$0D
		STA	spritePtr0
		
		LDA	#$0A
		STA	vicSprClr0
		
		LDA	vicSprEnab
		ORA	#$01
		STA	vicSprEnab

		;; Normal sprite
		LDA	#$00
		STA	vicSpr16Col
		STA	vicSprExYEn
		STA	vicSprExXEn
		;; ... but with bitplane enable mode, so cursor
		;; is always visible, no matter what it is over
		LDA	vicSprBitPlaneEn0to3
		ORA	#$10
		STA	vicSprBitPlaneEn0to3
		
	.if	C64_MODE
		LDA 	IIRQ + 1
		CMP 	#>MIRQ
		BEQ 	L90
	.endif
		
;		PHP
;		SEI
		
	.if	C64_MODE
		LDA 	IIRQ
		STA 	IIRQ2
		LDA 	IIRQ + 1
		STA 	IIRQ2 + 1
	.endif

		LDA 	#<MIRQ
		STA 	IIRQ
		LDA 	#>MIRQ
		STA 	IIRQ + 1
;
;		PLP
L90:    
		JSR	CMOVEX
		JSR	CMOVEY

		LDA 	#$01			; Enable Amiga -> 1351 mouse translation
		STA	$D61B
	
		RTS

;-------------------------------------------------------------------------------
	.if	C64_MODE
IIRQ2:
	.word		$0000
	.endif
	
;-------------------------------------------------------------------------------
MIRQ:    
;-------------------------------------------------------------------------------
		CLD             		; JUST IN CASE.....
		
	.if	.not	C64_MODE
		PHP
		PHA
		PHX
		PHY
		PHZ
	.endif

;Do help text switching
		LDA	#$00
		CMP	helpCntr + 1
		BNE	@cont0
		CMP	helpCntr
		BNE	@cont0
		
		LDA	#$85
		STA	helpCntr
		LDA	#$03
		STA	helpCntr + 1
		
		LDA	currHelpTxt
		ASL
		TAX
		LDA	helpTexts, X
		STA	ptrIRQTemp0
		LDA	helpTexts + 1, X
		STA	ptrIRQTemp0 + 1
		
		LDY	#$1A
@loop:
		LDA	(ptrIRQTemp0), Y
		JSR	asciiToCharROM
		ORA	#$80
		STA	$07C0, Y
		DEY
		BPL	@loop
		
		INC	currHelpTxt
		LDA	currHelpTxt
		CMP	#$08
		BNE	@cont0
		
		LDA	#$00
		STA	currHelpTxt
	
@cont0:
		SEC
		LDA	helpCntr
		SBC	#$01
		STA	helpCntr
		LDA	helpCntr + 1
		SBC	#$00
		STA	helpCntr + 1


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

		LDY     #%00000000              ; Set ports A and B to input
		STY     CIA1_DDRB
		STY     CIA1_DDRA               ; Keyboard won't look like mouse
		LDA     CIA1_PRB                ; Read Control-Port 1
		DEC     CIA1_DDRA               ; Set port A back to output
		EOR     #%11111111              ; Bit goes up when button goes down
		STA     Buttons
		BEQ     @L0                     ;(bze)
		DEC     CIA1_DDRB               ; Mouse won't look like keyboard
		STY     CIA1_PRB                ; Set "all keys pushed"

@L0:    
		JSR	ButtonCheck

		LDA     SID_ADConv1             ; Get mouse X movement
		LDY     OldPotX
		JSR     MoveCheck               ; Calculate movement vector

; Skip processing if nothing has changed

		BCC     @SkipX
		STY     OldPotX

; Calculate the new X coordinate (--> a/y)

		CLC
		ADC	XPos

		TAY                             ; Remember low byte
		TXA
		ADC     XPos+1
		TAX

; Limit the X coordinate to the bounding box

		CPY     XMin
		SBC     XMin+1
		BPL     @L1
		LDY     XMin
		LDX     XMin+1
		JMP     @L2
@L1:    	
		TXA

		CPY     XMax
		SBC     XMax+1
		BMI     @L2
		LDY     XMax
		LDX     XMax+1
@L2:    
		STY     XPos
		STX     XPos+1

; Move the mouse pointer to the new X pos

		TYA
		JSR     CMOVEX

; Calculate the Y movement vector

@SkipX: 
		LDA     SID_ADConv2             ; Get mouse Y movement
		LDY     OldPotY
		JSR     MoveCheck               ; Calculate movement

; Skip processing if nothing has changed

		BCC     @SkipY
		STY     OldPotY

; Calculate the new Y coordinate (--> a/y)

		STA     OldValue
		LDA     YPos
		SEC
		SBC	OldValue

		TAY
		STX     OldValue
		LDA     YPos+1
		SBC     OldValue
		TAX

; Limit the Y coordinate to the bounding box

		CPY     YMin
		SBC     YMin+1
		BPL     @L3
		LDY     YMin
		LDX     YMin+1
		JMP     @L4
@L3:    
		TXA

		CPY     YMax
		SBC     YMax+1
		BMI     @L4
		LDY     YMax
		LDX     YMax+1
@L4:    	
		STY     YPos
		STX     YPos+1

; Move the mouse pointer to the new Y pos

		TYA
		JSR     CMOVEY

; Done

@SkipY: 
;		JSR     CDRAW
		CLC                             ; Interrupt not "handled"
        
		
	.if	.not C64_MODE
		LDA 	$DC0D
		
		PLZ
		PLY
		PLX
		PLA
		PLP
		RTI
	.else
		JMP	(IIRQ2)
	.endif
	


;-------------------------------------------------------------------------------
MoveCheck:
; Move check routine, called for both coordinates.
;
; Entry:        y = old value of pot register
;               a = current value of pot register
; Exit:         y = value to use for old value
;               x/a = delta value for position
;-------------------------------------------------------------------------------
		STY     OldValue
		STA     NewValue
		LDX     #$00

		SEC				; a = mod64 (new - old)
		SBC	OldValue

		AND     #%01111111
		CMP     #%01000000              ; if (a > 0)
		BCS     @L1                     ;
		LSR                             ;   a /= 2;
		BEQ     @L2                     ;   if (a != 0)
		LDY     NewValue                ;     y = NewValue
		SEC
		RTS                             ;   return

@L1:    
		ORA     #%11000000              ; else, "or" in high-order bits
		CMP     #$FF                    ; if (a != -1)
		BEQ     @L2
		SEC
		ROR                             ;   a /= 2
		DEX                             ;   high byte = -1 (X = $FF)
		LDY     NewValue
		SEC
		RTS

@L2:    
		TXA                             ; A = $00
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
			.byte 	<$0590, <$05B8, <$05E0, <$0608, <$0630
			.byte	<$0658, <$0680, <$06A8, <$06D0, <$06F8
			.byte	<$0720, <$0748, <$0770, <$0798, <$07C0

screenRowsHi:
			.byte	>$0400, >$0428, >$0450, >$0478, >$04A0
			.byte	>$04C8, >$04F0, >$0518, >$0540, >$0568
			.byte 	>$0590, >$05B8, >$05E0, >$0608, >$0630
			.byte	>$0658, >$0680, >$06A8, >$06D0, >$06F8
			.byte	>$0720, >$0748, >$0770, >$0798, >$07C0

colourRowsLo:
			.byte	<$D800, <$D828, <$D850, <$D878, <$D8A0
			.byte	<$D8C8, <$D8F0, <$D918, <$D940, <$D968
			.byte 	<$D990, <$D9B8, <$D9E0, <$DA08, <$DA30
			.byte	<$DA58, <$DA80, <$DAA8, <$DAD0, <$DAF8
			.byte	<$DB20, <$DB48, <$DB70, <$DB98, <$DBC0

colourRowsHi:
			.byte	>$D800, >$D828, >$D850, >$D878, >$D8A0
			.byte	>$D8C8, >$D8F0, >$D918, >$D940, >$D968
			.byte 	>$D990, >$D9B8, >$D9E0, >$DA08, >$DA30
			.byte	>$DA58, >$DA80, >$DAA8, >$DAD0, >$DAF8
			.byte	>$DB20, >$DB48, >$DB70, >$DB98, >$DBC0


;-------------------------------------------------------------------------------
heap0:
;dengland
;	Must be at end of code
;-------------------------------------------------------------------------------
