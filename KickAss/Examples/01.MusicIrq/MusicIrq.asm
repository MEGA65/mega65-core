BasicUpstart2(start)			// <- This creates a basic sys line that can start your program

//----------------------------------------------------------
//----------------------------------------------------------
//					Simple IRQ
//----------------------------------------------------------
//----------------------------------------------------------
			* = $4000 "Main Program"		// <- The name 'Main program' will appear in the memory map when assembling
start:		lda #$00
			sta $d020
			sta $d021
			lda #$00
			jsr music_init
			sei
			lda #$35
			sta $01
			lda #<irq1
			sta $fffe
			lda #>irq1
			sta $ffff
			lda #$1b
			sta $d011
			lda #$80
			sta $d012
			lda #$81
			sta $d01a
			lda #$7f
			sta $dc0d
			sta $dd0d

			lda $dc0d
			lda $dd0d
			lda #$ff
			sta $d019

			cli
			jmp *
//----------------------------------------------------------
irq1:  		pha
			txa
			pha
			tya
			pha
			lda #$ff
			sta	$d019

			SetBorderColor(RED)			// <- This is how macros are executed
			jsr music_play
			SetBorderColor(BLACK)		// <- There are predefined constants for colors

			pla
			tay
			pla
			tax
			pla
			rti
			
//----------------------------------------------------------
			*=$1000 "Music"
			.label music_init =*			// <- You can define label with any value (not just at the current pc position as in 'music_init:') 
			.label music_play =*+3			// <- and that is useful here
			.import binary "ode to 64.bin"	// <- import is used for importing files (binary, source, c64 or text)	

//----------------------------------------------------------
// A little macro
.macro SetBorderColor(color) {		// <- This is how macros are defined
	lda #color
	sta $d020
}