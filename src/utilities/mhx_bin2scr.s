
        .setcpu "65C02"

        .export _mhx_bin2scr
        .import incsp8
        .importzp sp, ptr1, tmp1, tmp2, tmp3, tmp4

;* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
;*                                                                             *
;*                CONVERT 32-BIT BINARY TO ASCII NUMBER STRING                 *
;*                                                                             *
;*                             by BigDumbDinosaur                              *
;*                                                                             *
;* This 6502 assembly language program converts a 32-bit unsigned binary value *
;* into a null-terminated ASCII string whose format may be in  binary,  octal, *
;* decimal or hexadecimal.                                                     *
;*                                                                             *
;* --------------------------------------------------------------------------- *
;*                                                                             *
;* Copyright (C)1985 by BCS Technology Limited.  All rights reserved.          *
;*                                                                             *
;* Permission is hereby granted to copy and redistribute this software,  prov- *
;* ided this copyright notice remains in the source code & proper  attribution *
;* is given.  Any redistribution, regardless of form, must be at no charge  to *
;* the end user.  This code MAY NOT be incorporated into any package  intended *
;* for sale unless written permission has been given by the copyright holder.  *
;*                                                                             *
;* THERE IS NO WARRANTY OF ANY KIND WITH THIS SOFTWARE.  It's free, so no mat- *
;* ter what, you're getting a great deal.                                      *
;*                                                                             *
;* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
;
; This was adapted for the MEGA65 project in 2023 by
;    Oliver Graf <oliver@m-e-g-a.org>
;
; Changes:
;  - change conversion function to cdecl call
;  - use CC65 zeropage addresses (plus some more - C64 FPACC)
;  - make minimum length a parameter
;  - add space padding as an option
;  - add switch for hex upper/lowercase
;  - result is screencodes (letter codes are different)
;
; Calling syntax: see _mhc_bin2scr cdecl style function
;
;
;ATOMIC CONSTANTS
;
_zpage_  = $61                  ; start of ZP storage
;
;	------------------------------------------
;	Modify the above to suit your application.
;	------------------------------------------
;
a_hexdec = $c6                  ; lowercase hex to decimal difference (screencode)
a_hexdecupper = $06             ; uppercase hex to decimal difference (screencode)
m_bits   = 32                   ; operand bit size
m_cbits  = 48                   ; workspace bit size
m_strlen = m_bits+1             ; maximum printable string length
n_radix  = 4                    ; number of supported radices
s_pfac   = m_bits/8             ; primary accumulator size
s_ptr    = 2                    ; pointer size
s_wrkspc = m_cbits/8            ; conversion workspace size
;
;================================================================================
;
;ZERO PAGE ASSIGNMENTS
;
;	---------------------------------
;	The following may be relocated to
;	absolute storage if desired.
;	---------------------------------
;
pfac     = _zpage_              ; primary accumulator
wrkspc01 = pfac+s_pfac          ; conversion...
wrkspc02 = wrkspc01+s_wrkspc    ; workspace
radix    = tmp1                 ; radix index
stridx   = tmp2                 ; string buffer index
a_hexoff = tmp3                 ; variable hex offset for upper/lower
minlen   = tmp4                 ; minimum length
strbuf   = ptr1
;
;================================================================================
;
;CONVERT 32-BIT BINARY TO NULL-TERMINATED ASCII NUMBER STRING
;
;	----------------------------------------------------------------
;	WARNING! If this code is run on an NMOS MPU it will be necessary
;	         to disable IRQs during binary to BCD conversion unless
;	         the target system's IRQ handler clears decimal mode.
;	         Refer to the FACBCD subroutine.
;	----------------------------------------------------------------
;
;
.SEGMENT "CODE"

;;
;; void cdecl mhx_bin2scr(uint8_t radix, uint8_t length, uint32_t bin, char *strbuf)
;;
;;   converts a binary unsigned 32 bit number into a string representation
;;   using commodore screencodes.
;;
;;   this is intended to be called from C (cc65 in this case) and expects all
;;   parameters on the stack!
;;
;; parameters:
;;   radix:  target conversion,
;;      bit 0+1 = conversion target id
;;        0 - DEC, 1 - BIN, 2 - OCT, 3 - HEX
;;      bit 4 (0x10) - enable space padding
;;      bit 7 (0x80) - use uppercase hex letters (0x41-0x46) instead of
;;                     lowercase (0x01-0x06)
;;   length: minimum length of the result string (1-32)
;;   bin:    binary 32 bit number (unsigned) to convert
;;   strbuf: 16bit pointer to a memory buffer for the result, this needs
;;           to be at least 33 bytes long. Terminating char is 0x80!
;;
;; returns:
;;   length of the converted string in A
;;    
_mhx_bin2scr:
        ; we do have 7 bytes of arguments on the stack, the first (radix)
        ; is the farthest down
        ldy #7

        .p02                    ; need to switch to 6502 mode to use sp zeropage
        lda (sp),y
        .p4510                  ; ... because 4510 has an opcode with sp addressing
        taz                     ; store radix in .Z for now
        dey

        .p02
        lda (sp),y
        .p4510
        bne @binstr00a
        inc a                   ; is length is zero we need to raise it to 1
        bra @binstr00
@binstr00a:
        cmp #$20                ; max 32 allowed
        bcc @binstr00
        lda #$20
@binstr00:
        inc a                   ; the length used internally needs to be one higher
        sta minlen
        dey

        ldx #3
@binstr00b:
        .p02
        lda (sp),y
        .p4510
        sta pfac,x
        dey
        dex
        bpl @binstr00b

        .p02
        lda (sp),y
        .p4510
        sta strbuf+1              ; pointer to strbuf
        dey
        .p02
        lda (sp),y
        .p4510
        sta strbuf
;
        ldy #0
        sty stridx              ; initialize string index
;
;	--------------
;	evaluate radix
;	--------------
;
        .p4510

        tza                     ; restore radix
        bpl @binstr01
        ldx #a_hexdecupper
        bra @binstr01a
@binstr01:
        ldx #a_hexdec
@binstr01a:
        stx a_hexoff

@binstr02:
        sta radix               ; save radix index for later
        and #$03
        bne @binstr06           ; no decimal converison
;;	------------------------------
;	prepare for decimal conversion
;	------------------------------
;

        jsr facbcd              ; convert operand to BCD
        lda #0
        beq @binstr09           ; skip binary stuff
;
;	-------------------------------------------
;	prepare for binary, octal or hex conversion
;	-------------------------------------------
;
@binstr06:
        ldx #0                  ; operand index
        ldy #s_wrkspc-1         ; workspace index
;
@binstr07:
        lda pfac,x              ; copy operand to...
        sta wrkspc01,y          ; workspace in...
        dey                     ; big-endian order
        inx
        cpx #s_pfac
        bne @binstr07
;
        lda #0
;
@binstr08:
        sta wrkspc01,y          ; pad workspace
        dey
        bpl @binstr08
;
;	----------------------------
;	set up conversion parameters
;	----------------------------
;
@binstr09:
        sta wrkspc02            ; initialize byte counter
        lda radix               ; radix index
        and #$03
        tay
        lda numstab,y           ; numerals in string
        sta wrkspc02+1          ; set remaining numeral count
        lda bitstab,y           ; bits per numeral
        sta wrkspc02+2          ; set
;
;	--------------------------
;	generate conversion string
;	--------------------------
;
@binstr10:
        lda #0
        ldy wrkspc02+2          ; bits per numeral
;
@binstr11:
        ldx #s_wrkspc-1         ; workspace size
        clc                     ; avoid starting carry
;
@binstr12:
        rol wrkspc01,x          ; shift out a bit...
        dex                     ; from the operand or...
        bpl @binstr12           ; BCD conversion result
;
        rol                     ; bit to .A
        dey
        bne @binstr11           ; more bits to grab
;
        tay                     ; if numeral isn't zero...
        bne @binstr13           ; skip leading zero tests
;
        ldx wrkspc02+1          ; remaining numerals
        cpx minlen              ; leading zero threshold
        bcc @binstr13           ; below it, must convert
;
        ldx wrkspc02            ; processed byte count
        beq @binstr15           ; discard leading zero
;
@binstr13:
        cmp #10                 ; check range
        bcc @binstr14           ; is 0-9
;
        adc a_hexoff            ; apply hex adjust
;
@binstr14:
        adc #'0'                ; change to ASCII
        ldy stridx              ; string index
        sta (strbuf),y          ; save numeral in buffer
        inc stridx              ; next buffer position
        inc wrkspc02            ; bytes=bytes+1
;
@binstr15:
        dec wrkspc02+1          ; numerals=numerals-1
        bne @binstr10           ; not done
;
;	-----------------------
;	terminate string & exit
;	-----------------------
;
        lda #$10
        bit radix               ; check if we need to replace leading
        bne @binstr17           ; zeros with spaces

        dec stridx              ; don't do the last zero
        ldy #0
@binstr16:
        cpy stridx
        bcs @binstr16e
        lda (strbuf),y
        cmp #$30
        bne @binstr16e
        lda #$20
        sta (strbuf),y
        iny
        bra @binstr16
@binstr16e:
        inc stridx

@binstr17:
        lda #$80
        ldy stridx              ; printable string length
        sta (strbuf),y          ; terminate string
        tya
;
        jmp incsp8              ; remove parameters from stack
;
;================================================================================
;
;PER RADIX CONVERSION TABLES
;
; decimal, binary, octal, hex
bitstab:
        .byte 4,1,3,4         ;bits per numeral
numstab:
        .byte 12,48,16,12     ;maximum numerals
;
;================================================================================
;
;CONVERT PFAC INTO BCD
;
;	---------------------------------------------------------------
;	Uncomment noted instructions if this code is to be used  on  an
;	NMOS system whose interrupt handlers do not clear decimal mode.
;	---------------------------------------------------------------
;
facbcd:
        ldx #s_pfac-1           ; primary accumulator size -1
;
@facbcd01:
        lda pfac,x              ; value to be converted
        pha                     ; protect
        dex
        bpl @facbcd01           ; next
;
        lda #0
        ldx #s_wrkspc-1         ; workspace size
;
@facbcd02:
        sta wrkspc01,x          ; clear final result
        sta wrkspc02,x          ; clear scratchpad
        dex
        bpl @facbcd02      
;
        inc wrkspc02+s_wrkspc-1
        php                    ; !!! uncomment for NMOS MPU !!!
        sei                    ; !!! uncomment for NMOS MPU !!!
        sed                     ; select decimal mode
        ldy #m_bits-1           ; bits to convert -1
;
@facbcd03:
        ldx #s_pfac-1           ; operand size
        clc                     ; no carry at start
;
@facbcd04:
        ror pfac,x              ; grab LS bit in operand
        dex
        bpl @facbcd04
;
        bcc @facbcd06           ; LS bit clear
;
        clc
        ldx #s_wrkspc-1
;
@facbcd05:
        lda wrkspc01,x          ; partial result
        adc wrkspc02,x          ; scratchpad
        sta wrkspc01,x          ; new partial result
        dex
        bpl @facbcd05
;
        clc
;
@facbcd06:
        ldx #s_wrkspc-1
;
@facbcd07:
        lda wrkspc02,x          ; scratchpad
        adc wrkspc02,x          ; double &...
        sta wrkspc02,x          ; save
        dex
        bpl @facbcd07
;
        dey
        bpl @facbcd03           ; next operand bit
;
        plp                     ; !!! uncomment for NMOS MPU !!!
        ldx #0
;
@facbcd08:
        pla                     ; operand
        sta pfac,x              ; restore
        inx
        cpx #s_pfac
        bne @facbcd08           ; next
;
        rts
