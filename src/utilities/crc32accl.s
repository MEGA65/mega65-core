
        .setcpu "65C02"

        .export _make_crc32_tables
        .export _update_crc32
        .import incsp3, incsp4
        .importzp sp, ptr1

;;
;; This is evil code that just puts stuff into memory without caring about what the C compiler does!
;;

;;
;; based on CRC32 assembly by Paul Guertin (pg@sff.net), 18 August 2000
;; http://6502.org/source/integers/crc.htm
;;

CRC32_ZP = $5c         ; 4 bytes, the calculated checksum, needs to initialised with 0
CRCT0    = $9c00       ; Four 256-byte tables
CRCT1    = CRCT0+$100  ; (should be page-aligned for speed)
CRCT2    = CRCT0+$200  ; but those are actually UNUSED, as make_crc32_tables
CRCT3    = CRCT0+$300  ; will modify the code to use buffers from C!

.SEGMENT "CODE"

        .p4510

_make_crc32_tables:
        ;; void make_crc32_table(char *buf1, char *buf2)
        ;; setup of CRC32 tables

        ;; use two 512 byte buffers to store the crc32 tables
        ;;
        ;; THERE IS NO CHECK THAT THE TABLES ARE 512b EACH!
        ;;
        ;; THIS IS SELF MODIFYING CODE! DIRECTLY CHANGES TABLES
        ;; POSITIONS WITHIN make_crc32_tables AND update_crc32!
        ldy #3
        .p02
        lda (sp),y
        .p4510
        sta m_crct0_mod+2
        sta u_crct0_mod+2
        inc             ; second 256 byte of array 1
        sta m_crct1_mod+2
        sta u_crct1_mod+2
        dey
        .p02
        lda (sp),y
        .p4510
        sta m_crct0_mod+1   ; low byte is the same for both ranges
        sta m_crct1_mod+1
        sta u_crct0_mod+1
        sta u_crct1_mod+1
        dey
        .p02
        lda (sp),y
        .p4510
        sta m_crct2_mod+2
        sta u_crct2_mod+2
        inc             ; second 256 byte of array 2
        sta m_crct3_mod+2
        sta u_crct3_mod+2
        dey
        .p02
        lda (sp),y
        .p4510
        sta m_crct2_mod+1   ; low byte is the same for both ranges
        sta m_crct3_mod+1
        sta u_crct2_mod+1
        sta u_crct3_mod+1

        ldx #0          ; X counts from 0 to 255
byteloop:
        lda #0          ; A contains the high byte of the CRC-32
        sta CRC32_ZP+2  ; The other three bytes are in memory
        sta CRC32_ZP+1
        stx CRC32_ZP
        ldy #8          ; Y counts bits in a byte
@bitloop:
        lsr             ; The CRC-32 algorithm is similar to CRC-16
        ror CRC32_ZP+2  ; except that it is reversed (originally for
        ror CRC32_ZP+1  ; hardware reasons). This is why we shift
        ror CRC32_ZP    ; right instead of left here.
        bcc @noadd      ; Do nothing if no overflow
        eor #$ED        ; else add CRC-32 polynomial $EDB88320
        pha             ; Save high byte while we do others
        lda CRC32_ZP+2
        eor #$B8        ; Most reference books give the CRC-32 poly
        sta CRC32_ZP+2  ; as $04C11DB7. This is actually the same if
        lda CRC32_ZP+1  ; you write it in binary and read it right-
        eor #$83        ; to-left instead of left-to-right. Doing it
        sta CRC32_ZP+1  ; this way means we won't have to explicitly
        lda CRC32_ZP    ; reverse things afterwards.
        eor #$20
        sta CRC32_ZP
        pla             ; Restore high byte
@noadd:
        dey
        bne @bitloop    ; Do next bit
m_crct3_mod:            ; labels to modify code for external tables
        sta CRCT3,x     ; Save CRC into table, high to low bytes
        lda CRC32_ZP+2
m_crct2_mod:
        sta CRCT2,x
        lda CRC32_ZP+1
m_crct1_mod:
        sta CRCT1,x
        lda CRC32_ZP
m_crct0_mod:
        sta CRCT0,x
        inx
        bne byteloop    ; Do next byte

        jmp incsp4      ; get rid of arguments and return

_update_crc32:
        ;; void calc_attic_crc32(unsigned char len, unsigned char *buf)
        ;;
        ;; len 0 processes 256 bytes instead!
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
        
        tay             ; the length
        ldz #0          ; offset into buffer
one_byte:
        lda (ptr1),z
        ;;sta $6d0,y      ; DEBUG
        eor CRC32_ZP    ; Quick CRC computation with lookup tables
        tax
        lda CRC32_ZP+1
u_crct0_mod:            ; labels to modify code for external tables
        eor CRCT0,x
        sta CRC32_ZP
        lda CRC32_ZP+2
u_crct1_mod:
        eor CRCT1,x
        sta CRC32_ZP+1
        lda CRC32_ZP+3
u_crct2_mod:
        eor CRCT2,x
        sta CRC32_ZP+2
u_crct3_mod:
        lda CRCT3,x
        sta CRC32_ZP+3
        inz
        dey
        bne one_byte    ; count down to zero, if len was zero, this counts 256!
        
        jmp incsp3      ; get rid of arguments and return
