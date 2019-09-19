// Convenient macro for checkpoints. Uncomment the body to activate it
.macro Checkpoint(text) {
        /*jsr checkpoint
        .byte 0
        .text text
        .byte 0*/
}
.macro lda_bp_z(byte) {
        // lda (byte), z
        .byte $b2, byte
}
.macro sta_bp_z(byte) {
        // lda (byte), z
        .byte $92, byte
}
.macro jmp_zp_x(addr) {
        .byte $7c, <addr, >addr
}

.pseudocommand inc_a {
        .byte $1a
}
.pseudocommand dec_a {
        .byte $3a
}

.pseudocommand ldz arg {
        .if (arg.getType() == AT_IMMEDIATE) {
                .byte $a3, arg.getValue()
        }
        .if (arg.getType() == AT_ABSOLUTE) {
                .byte $ab, <arg.getValue(), >arg.getValue()
        }
}
.pseudocommand stz arg {
        .if (arg.getType() == AT_ABSOLUTE) {
                .byte $9c, <arg.getValue(), >arg.getValue()
        }
}
.pseudocommand bra arg {
        .byte $80, arg.getValue()
}
.pseudocommand phz {
        .byte $db
}
.pseudocommand plz {
        .byte $fb
}
.pseudocommand see {
        .byte $03
}
.pseudocommand map {
        .byte $5c
}
.pseudocommand eom {
        .byte $ea
}
.pseudocommand inz {
        .byte $1b
}
.pseudocommand inw arg {
        .byte $e3, arg.getValue()
}
.pseudocommand dez {
        .byte $3b
}
.pseudocommand phx {
        .byte $da
}
.pseudocommand phy {
        .byte $5a
}
.pseudocommand plx {
        .byte $fa
}
.pseudocommand ply {
        .byte $7a
}
.pseudocommand tsb arg {
        .byte $0c, <arg.getValue(), >arg.getValue()
}
.pseudocommand trb arg {
        .byte $1c, <arg.getValue(), >arg.getValue()
}
.pseudocommand cpz arg {
        .if (arg.getType() == AT_IMMEDIATE) {
                .byte $c2, arg.getValue()
        }
}
.pseudocommand tza {
        .byte $6b
}
.pseudocommand taz {
        .byte $4b
}
