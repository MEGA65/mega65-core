#import "PseudoCmds.lib"		// <- Look in this file to see how the commands are defined
BasicUpstart2(start)
//----------------------------------------------------------
//----------------------------------------------------------
//			Double Speed Music player
//----------------------------------------------------------
//----------------------------------------------------------	
			* = $0900 "Main Program"
start:		sei
			ldy #$00
			jsr music_init
			mov #$35 : $01            // <- Notice how different addressing modes can be used
			mov16 #irq1 : $fffe		  // <- 16 bit commands (or higher) can also be made
			mov #$1b : $d011
			mov #$33 : $d012
			mov #$81 : $d01a
			mov #$7f : $dc0d
			mov #$7f : $dd0d
			lda $dc0d
			lda $dd0d
			mov #$ff : $d019
			cli
			jmp *

irq1:  		irqStart				// <- Pseudocmds can be made for standard procedures
			mov #WHITE : $d020
			jsr music_play
			mov #BLACK : $d020
			irqEnd #$d8 : #irq2 	// <- $d012 and $fffe values are optional

irq2:  		irqStart
			mov #WHITE : $d020
			jsr music_play
			mov #BLACK : $d020
			irqEnd #$33 : #irq1 
//----------------------------------------------------------
			* = $1000 "Music"
			.label music_init = *
			.label music_play = *+3
			.import c64 "DoubleSpeed.c64"
//----------------------------------------------------------





