BasicUpstart2(mainProg)

.const scrollLine = $0400+24*40

//----------------------------------------------------
// 			Main Program
//----------------------------------------------------
			*=$1000
mainProg: 	{								// <- Here we define a scope
			sei
			lda #$17
			sta $d018

			// Wait for line $f2 and set d016	
loop1:		lda #$f2							//<- Here we define 'loop1'
			cmp $d012
			bne loop1
			jsr setScrollD016
			
			// Wait for line $ff and prepare next frame 
loop2:		lda #$ff							// <- Inside the scope labels can collide so we use 'loop2'	
			cmp $d012
			bne loop2
			lda #$c8
			sta $d016
			jsr moveScroll
			
			jmp loop1
}
//----------------------------------------------------
// 			Scroll Routines
//----------------------------------------------------

setScrollD016:	{
value:		lda #0									
			and #$07
			ora #$c0
			sta $d016
			rts			
}

moveScroll: {
			// Step d016
			dec setScrollD016.value+1			//<- We can access labels of other scopes this way!				
			lda setScrollD016.value+1
			and #$07
			cmp #$07
			bne exit
			
			// Move screen chars
			ldx #0
loop1:		lda scrollLine+1,x					// <- Since 'loop1' is in a new scope it doesn't collide with the first 'loop1' label 
			sta scrollLine,x
			inx
			cpx #39
			bne loop1
			
			// Print new char
count:		ldx #0
			lda text,x
			sta scrollLine+39	
			inx 
			lda text,x
			cmp #$ff
			bne over1
			ldx #0
over1:		stx count+1
			
exit:		rts
			
text:		.text "Hello friends, how are we doing today. Hope you enjoy this scoping demo. Now get ready for pseudocommands....   "
			.byte $ff
}






