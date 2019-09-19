#import "PseudoCmds.lib"		
BasicUpstart2(start)
.const xSpeed = 8
//----------------------------------------------------------
//----------------------------------------------------------
//			8xSpeed Music player								
//			NOTE.. Check out the 2xSpeedPlayer before this! 	<- NOTE	
//----------------------------------------------------------
//----------------------------------------------------------
			* = $0900 "Main Program"
start:		sei
			lda #$00
			jsr music_init
			mov #$35 : $01            
			mov16 #irq1 : $fffe		 
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

irq1:  		irqStart				

			incLim frameNo : #xSpeed 	// <- Increase with wraplimit. But know your commands, this is not that fast
			ldx frameNo
			mov intPlay,x : playJsr+1	// <- Notice how all addressing modes can be used for a pseudo cmds (Also ,x ,y (zp),y etc) 
			mov #WHITE : $d020
playJsr:	jsr music_play
			mov #BLACK : $d020

			ldx frameNo
			mov intD011,x : $d011	
			irqEnd intD012,x		// <- Notice the address of the next irq is not given (its optional) 	

frameNo:	.byte 0

intPlay:	.byte <music_play, <music_play+3, <music_play+3,<music_play+3,<music_play+3,<music_play+3,<music_play+3,<music_play+6
intD012:	.fill xSpeed, i*312/xSpeed
intD011:	.fill xSpeed, $1b + (((i*312/xSpeed)&$100)>>1)

//----------------------------------------------------------
			* = $1000 "Music"
			.label music_init = *
			.label music_play = *+3
			.import c64 "8thFrame.c64"
//----------------------------------------------------------





