
#define IRQ_UNDER_ROM	// <- here we define a preprocesssor symbol. This can also be done
#define STANDALONE

//-----------------------------------------------------
// Upstart program if we are in stand alone mode
//-----------------------------------------------------

#if STANDALONE		// <- The source inside the #if is discarded if STANDALONE is not defined
			BasicUpstart2(start)
start:		sei
	
	#if !IRQ_UNDER_ROM		//	<- If's can be nested. Notice the ! operator. Other operators are ==, !=, ||, && and () 
				lda #<irq1
				sta $0314
				lda #>irq1
				sta $0315
	#else
				lda #$35
				sta $01
				lda #<irq1
				sta $fffe
				lda #>irq1
				sta $ffff
	#endif	

			lda #$1b
			sta $d011
			lda #$32
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
			inc $d020
			jmp *
#endif



//-----------------------------------------------------
// Procedures for start and end of interupt
//-----------------------------------------------------

#if !IRQ_UNDER_ROM 

	.pseudocommand irqStart {  // <- Since preprocessor commands are executed before anything else, you can redefined macros, functions, imports etc dependant on your settings
							   // (This can't be done by normal .if directives)
				lda #$ff
				sta $d019
	}
		
	.pseudocommand irqEnd line : addr {  		 
				.if (line.getType()!=AT_NONE) {lda line; sta $d012; }	
				.if (addr.getType()!=AT_NONE) {lda #<addr.getValue(); sta $0314; lda #>addr.getValue(); sta $0315; }	
				jmp $ea81
	}
#else
	.pseudocommand irqStart {
				pha
				txa
				pha
				tya
				pha
				lda #$ff
				sta $d019
	}


	.pseudocommand irqEnd line : addr {
				.if (line.getType()!=AT_NONE) {lda line; sta $d012; }	
				.if (addr.getType()!=AT_NONE) {lda #<addr.getValue(); sta $fffe; lda #>addr.getValue(); sta $ffff; }	
				pla
				tay
				pla
				tax
				pla
				rti
	}
#endif
		
	

//-----------------------------------------------------
// The Irqs
//-----------------------------------------------------
#if !IRQ_UNDER_ROM
			.const delay = 3
#else
			.const delay = 7
#endif
			*=$5000
irq1:  		irqStart
			ldy #delay
			dey
			bne *-1
			lda #LIGHT_BLUE
			sta $d020
			irqEnd #$32+200 : #irq2


irq2:  		irqStart
			ldy #delay
			dey
			bne *-1
			lda #BLACK
			sta $d020
			irqEnd #$32 : #irq1



 
 