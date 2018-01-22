;===============================================================================
;M65 Configuration Utility
;-------------------------
;
;Version 00.01A
;
;Written by Daniel England for the MEGA65 project.
;
;
;===============================================================================


;dengland
;	I'm enabling "leading_dot_in_identifiers" because I prefer to use a 
;	leading '.' in data definitions and I'm using a macro for them.
;
;	I'm enabling "loose_string_term" because I don't see a way of defining
;	a string with a double quote in it without it.

	.feature	leading_dot_in_identifiers, loose_string_term

	.macro  	.defPStr Arg
	.byte   	.strlen(Arg), Arg
        .endmacro


ptrCurrOpts	=	$40
selectedOpt	=	$42
optTempLine	=	$43
optTempIndx	=	$44

ptrTempData	=	$A0

ptrOptsTemp	= 	$FB
ptrCurrHeap	=	$FD


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
;-------------------------------------------------------------------------------
bootstrap:
		JMP	init
	
headerLine:
	.asciiz		"          mega65 configuration          "
menuLine:
	.asciiz		"systemBdiskBvideoBaudio             done"
footerLine:
	.asciiz		"                                page 1/1"

headerColours:
	.byte		$06, $06, $05, $05, $07, $07, $02, $02
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$0F, $0F, $0F, $0F, $0F, $0F, $0F, $0F
	.byte		$02, $02, $07, $07, $05, $05, $06, $06
	
menuColours:
	.byte		$03, $0C, $0C, $0C, $0C, $0C, $0C, $03
	.byte		$0C, $0C, $0C, $0C, $03, $0C, $0C, $0C
	.byte		$0C, $0C, $03, $0C, $0C, $0C, $0C, $0C
	.byte		$0C, $0C, $0C, $0C, $0C, $0C, $0C, $0C
	.byte		$0C, $0C, $0C, $0C, $0C, $0C, $0C, $03
	
;dengland
;	This will tell us whats happening on each line so we can use quick 
;	look-ups for the mouse etc.  Only 20 of the lines on the screen can be
;	used.
pageOptions:
	.byte		$FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	.byte		$FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
	.byte		$FF, $FF, $FF, $FF
	
	
;dengland
;	I'm making the input options defined by a type and a list of details
;	for that type.  They will have an offset and data byte followed by a
;	set of pascal-style strings.  The option is defined in the type byte
;	high nybble and the low nybble used to set the current value (except
;	for string input types, see below).  Pascal strings are used to 
;	speed up various operations (list traversal, on screen manipulation).
;
;	00	-	end of list, no data bytes
;	10	-	blank line, no data
;	20	-	option (on/off, one of two enabled)
;			followed by word offset and byte flags
;			requires 3 strings:  label, option unset, option set
;	30	-	string input.
;			followed by word offset and byte for string length
;			requires 1 string:  label
;			requires data area of string length for storage.
;			input string will be null or length terminated.
;	
	
systemOptions0:
	.byte		$30			;string input type
	.word		$0000			;offset into config table
	.byte		$10			;input string length
	.defPStr	"default disk image:"	;label
	.byte		$00, $00, $00, $00	;storage for value
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00
	.byte		$00, $00, $00, $00
	.byte		$00			;end of list type
	
diskOptions0:
	.byte		$20			;option input type
	.word		$0001			;offset into config table
	.byte		$01			;bits for testing/setting
	.defPStr	"f011 disk controller:"	;label
	.defPStr	'uses 3.5" floppy drive';option unset
	.defPStr	"uses sdcard disk image";option set
	.byte		$00			;end of list type

videoOptions0:
	.byte		$20
	.word		$0000
	.byte		$80
	.defPStr	"video mode:"
	.defPStr	"pal  50hz (800*600)"
	.defPStr	"ntsc 60hz (800*600)"
	.byte		$00


;-------------------------------------------------------------------------------
init:
;-------------------------------------------------------------------------------
; 	Init screen
		LDA 	#$0B			;Border colour
		STA 	$D020
		LDA 	#$00			;Screen colour
		STA 	$D021
		
;	Upper-case
		LDA 	#$8E			;Print to-upper-case character
		JSR 	$FFD2
		LDA	#$08			;Disable change of case
		JSR	$FFD2
		
		
;-------------------------------------------------------------------------------
main:
;-------------------------------------------------------------------------------
		JSR	setupDiskPage0

@halt:
		JMP	@halt

		RTS


;-------------------------------------------------------------------------------
setupSystemPage0:
;-------------------------------------------------------------------------------
		LDA	#<systemOptions0
		STA	ptrCurrOpts
		LDA	#>systemOptions0
		STA	ptrCurrOpts + 1
		
		LDA	#$00
		STA	selectedOpt
		
		JSR	displayOptionsPage
		
		RTS


;-------------------------------------------------------------------------------
setupDiskPage0:
;-------------------------------------------------------------------------------
		LDA	#<diskOptions0
		STA	ptrCurrOpts
		LDA	#>diskOptions0
		STA	ptrCurrOpts + 1
		
		LDA	#$00
		STA	selectedOpt
		
		JSR	displayOptionsPage
		
		RTS


;-------------------------------------------------------------------------------
displayOptionsPage:
;-------------------------------------------------------------------------------
		JSR 	clearScreen

		LDA	ptrCurrOpts
		STA	ptrOptsTemp
		LDA	ptrCurrOpts + 1
		STA	ptrOptsTemp + 1
		
		LDA	#<heap0
		STA	ptrCurrHeap
		LDA	#>heap0
		STA	ptrCurrHeap + 1
		
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
		
		
		
		RTS

@error:
;***fixme
;	Need something else here
		LDA	#$0A			
		STA	$D020
;***
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
		INY				;At least one data byte
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
		
		LDX	optTempLine		;Blank line, stub out
		LDA	#$FF
		STA	pageOptions, X
		INC	optTempLine		;and next line

		CLC	
		RTS
		
@tstToggOpt:
		CMP	#$20
		BNE	@tstStrOpt
		
		JSR	doDispToggleOpt
		RTS
		
@tstStrOpt:
		CMP	#$30
		BNE	@unknownOpt
		
		JSR	doDispStringOpt
		RTS
		
@unknownOpt:
		SEC
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
		
		LDX	optTempLine		;Set this line to be the option
		LDA	optTempIndx
		STA	pageOptions, X
		INC	optTempLine		;and next line
		
		PLA
		STA	dispOptTemp0

		TYA
		CLC
		ADC	dispOptTemp0
		TAY
				
		CLC
		RTS
		
	
dispOptTemp0:
	.byte		$00
dispOptTemp1:
	.byte		$00
	

;-------------------------------------------------------------------------------
doDispOptHdrLbl:
;-------------------------------------------------------------------------------
		TYA				;Store state
		PHA

		LDA	optTempLine		;Get current line #
		CLC
		ADC	#$03			;Add 3 for our menu/header
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
		ADC	#$03			;Add 3 for our menu/header
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
clearScreen:
;-------------------------------------------------------------------------------
;***fixme replace with DMAgic code for M65
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
;***

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
		
		LDA	menuColours, Y
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
;  	Magic string for Kickstart utility menu
;-------------------------------------------------------------------------------

	.asciiz "PROP.M65U.NAME=CONFIGURE MEGA65";


;-------------------------------------------------------------------------------
heap0:
;dengland
;	Must be at end of code
;-------------------------------------------------------------------------------
