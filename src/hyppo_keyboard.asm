peekkeyboard:
	// We now use hardware-accelerated keyboard reading
	lda ascii_key_in
	cmp #$00
	beq nokey
	clc
	rts
nokey:	// no key currently down, so set carry and return
	sec
	rts

scankeyboard:
	jsr peekkeyboard
	cmp #$00
	beq nokey
        // clear key from buffer
yeskey:	sta ascii_key_in
	clc
	rts