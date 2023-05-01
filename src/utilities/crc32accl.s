
        .setcpu "65C02"

        .export _make_crc32_tables
        .export _update_crc32
        .importzp sp, ptr1
        .import incsp3

;; CRC32 assembly by Paul Guertin (pg@sff.net), 18 August 2000
;; http://6502.org/source/integers/crc.htm

;;
;; This is evil code that just puts stuff into memory without caring about what the C compiler does!
;;

CRC      = $5c         ; the calculated checksum, needs to initialised with 0
CRCT0    = $9c00       ; Four 256-byte tables
CRCT1    = $9d00       ; (should be page-aligned for speed)
CRCT2    = $9e00
CRCT3    = $9f00

.SEGMENT "CODE"

        .p4510

_make_crc32_tables:
        ;; void make_crc32_table()
        ;; setup of CRC32 tables
        ldx #0          ; X counts from 0 to 255
@byteloop:
        lda #0          ; A contains the high byte of the CRC-32
        sta CRC+2       ; The other three bytes are in memory
        sta CRC+1
        stx CRC
        ldy #8          ; Y counts bits in a byte
@bitloop:
        lsr             ; The CRC-32 algorithm is similar to CRC-16
        ror CRC+2       ; except that it is reversed (originally for
        ror CRC+1       ; hardware reasons). This is why we shift
        ror CRC         ; right instead of left here.
        bcc @noadd      ; Do nothing if no overflow
        eor #$ED        ; else add CRC-32 polynomial $EDB88320
        pha             ; Save high byte while we do others
        lda CRC+2
        eor #$B8        ; Most reference books give the CRC-32 poly
        sta CRC+2       ; as $04C11DB7. This is actually the same if
        lda CRC+1       ; you write it in binary and read it right-
        eor #$83        ; to-left instead of left-to-right. Doing it
        sta CRC+1       ; this way means we won't have to explicitly
        lda CRC         ; reverse things afterwards.
        eor #$20
        sta CRC
        pla             ; Restore high byte
@noadd:
        dey
        bne @bitloop    ; Do next bit
        sta CRCT3,x     ; Save CRC into table, high to low bytes
        lda CRC+2
        sta CRCT2,x
        lda CRC+1
        sta CRCT1,x
        lda CRC
        sta CRCT0,x
        inx
        bne @byteloop   ; Do next byte
        rts

_update_crc32:
        ;; void calc_attic_crc32(unsigned char len, unsigned char *buf)
        ;;
        ;; len 0 means 256!
        ldy #1
        .p02
        lda (sp),y
        sta ptr1+1
        dey
        lda (sp),y
        sta ptr1
        ldy #2
        lda (sp),y
        .p4510
        
        tay
        ldz #0
@one_byte:
        lda (ptr1),z
        ;;sta $6d0,y      ; verify
        eor CRC         ; Quick CRC computation with lookup tables
        tax
        lda CRC+1
        eor CRCT0,x
        sta CRC
        lda CRC+2
        eor CRCT1,x
        sta CRC+1
        lda CRC+3
        eor CRCT2,x
        sta CRC+2
        lda CRCT3,x
        sta CRC+3
        inz
        dey
        bne @one_byte
        
        jmp incsp3
