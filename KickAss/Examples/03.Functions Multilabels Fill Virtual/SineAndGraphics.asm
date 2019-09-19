:BasicUpstart2(start)

//--------------------------------------------
// Functions for calculating vic values and other stuff
// (normally we would put these in a library)


.function screenToD018(addr) {										// <- This is how we define a function
	.return ((addr&$3fff)/$400)<<4
}
.function charsetToD018(addr) {
	.return ((addr&$3fff)/$800)<<1
}
.function toD018(screen, charset) {
	.return screenToD018(screen) | charsetToD018(charset)			//<- This is how we call functions
}

.function toSpritePtr(addr) {
	.return (addr&$3fff)/$40
}

.function sinus(i, amplitude, center, noOfSteps) {
	.return round(center+amplitude*sin(toRadians(i*360/noOfSteps)))	
}


//--------------------------------------------
			*=$2000 "Program"
start: 		sei
			
			// Print chars to screen
			ldx #0
			lda #5
!loop: 		sta screen,x			// <- '!' in front of a label means a multilabel (You can have several labels with the same name)
			sta screen+$100,x
			sta screen+$200,x
			sta screen+$300,x
			sec
			sbc #1
			bcs !over+			// <- Referencing forward to the nearest a multilabel called 'over'
			lda #5				
!over:
			inx
			bne !loop-			// <- Referencing backward to the nearest multilabel called 'loop'
			
			
			lda #toD018(screen, charset)	// <- The d018 value is calculated by a function. You can move graphics around and not worry about d018 is properly set
			sta $d018							
			
			
			// Setup some sprites
			lda #$0f
			sta $d015
			ldx #7
!loop:		lda spritePtrs,x
			sta screen+$3f8,x
			txa
			lsr
			sta $d027,x
			dex
			bpl !loop-
			
			
			// Make an effect loop with nonsense sprite movement
			ldx #0
			ldy #$0
			
!loop: 		lda $d012		// Wait for frame
			cmp #$ff
			bne !loop-
			
			lda sinus,x		// Set sprite 1
			sta $d000
			lda sinus+$40,x
			sta $d001


			lda sinus,x		// Set sprite 2
			sta $d002
			lda sinus+$30,y
			sta $d003

			lda #$f0		// Set sprite 3
			sta $d004
			lda sinus,y
			sta $d005

			lda sinus+$70,x	 // Set sprite 4
			sta $d006
			lda sinus,y
			sta $d007
	
			inx
			iny
			iny
			iny
			jmp !loop-


//--------------------------------------------
			
spritePtrs:	.byte toSpritePtr(sprite1), toSpritePtr(sprite2)  // <- The spritePtr function is use to calculate the spritePtr
			.byte toSpritePtr(sprite1), toSpritePtr(sprite2)
			.byte 0,0,0,0

sinus:		.fill $100, round($a0+$40*sin(toRadians(i*360/$100)))	 	// <- The fill functions takes two argument. 
																		// The number of bytes to fill and an expression to execute for each
																		// byte. 'i' is the byte number 

			.fill $100, sinus(i, $40, $a0, $100)			//<- Its easier to use a function when you use the expression many times			
//--------------------------------------------
			.align $0800		// <-- You can use align to align data to memory boundaries

charset: 	.byte %11111110
			.byte %10000010
			.byte %10000010
			.byte %10000010
			.byte %10000010
			.byte %10000010
			.byte %11111110
			.byte %00000000
			
			.byte %00000000
			.byte %01111100
			.byte %01000100
			.byte %01000100
			.byte %01000100
			.byte %01111100
			.byte %00000000
			.byte %00000000
		
			.byte %00000000
			.byte %00000000
			.byte %00111000
			.byte %00101000
			.byte %00111000
			.byte %00000000
			.byte %00000000
			.byte %00000000
		
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00010000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
		
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000

			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
			.byte %00000000
	
//--------------------------------------------
			.align $40	
sprite1: 	.byte %00000000, %11111111, %00000000 	
		 	.byte %00000001, %11111111, %10000000 	
		 	.byte %00000011, %11111111, %11000000 	
		 	.byte %00000111, %11111111, %11100000 	
		 	.byte %00001111, %11111111, %11110000 	
		 	.byte %00011111, %11111111, %11111000 	
		 	.byte %00111111, %11111111, %11111100 	
		 	.byte %00000011, %11111111, %11000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
		 	.byte %00000000, %00000000, %00000000 	
			.byte $00

sprite2:	.byte %01110000, %00000000, %00000000
			.byte %11111000, %00000000, %00000000
			.byte %11111000, %00000000, %00000000
			.byte %01110000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte %00000000, %00000000, %00000000
			.byte $00
			
//--------------------------------------------
			* = $3c00 "Virtual data" virtual		// <- Data in a virtual block is not entered into memory 
screen: 	.fill $0400, 0
			
	
	