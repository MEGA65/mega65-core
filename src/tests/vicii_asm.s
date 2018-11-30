	.export _irq_handler
	.export _install_irq

_install_irq:
	sei
	lda #<_irq_handler
	sta $0314
	lda #>_irq_handler
	sta $0315
	cli
	rts
	
_irq_handler:
	lda #$35
	sta $d018

	lda #$01
	sta $d020

	ldx #$00
loop:	dex
	bne loop

	lda #$15
	sta $d018

	lda #$00
	sta $d020

	inc $d019

	jmp $ea31
