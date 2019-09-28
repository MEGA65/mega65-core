/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

.define at {
        .var at = Hashtable()
        .eval at.put(' ', $20)
        .eval at.put('!', $21)
        .eval at.put(@"\"", $22)
        .eval at.put('#', $23)
        .eval at.put('$', $24)
        .eval at.put('%', $25)
        .eval at.put('&', $26)
        .eval at.put(''', $27)
        .eval at.put('(', $28)
        .eval at.put(')', $29)
        .eval at.put('*', $2a)
        .eval at.put('+', $2b)
        .eval at.put(',', $2c)
        .eval at.put('-', $2d)
        .eval at.put('.', $2e)
        .eval at.put('/', $2f)
        .eval at.put('0', $30)
        .eval at.put('1', $31)
        .eval at.put('2', $32)
        .eval at.put('3', $33)
        .eval at.put('4', $34)
        .eval at.put('5', $35)
        .eval at.put('6', $36)
        .eval at.put('7', $37)
        .eval at.put('8', $38)
        .eval at.put('9', $39)
        .eval at.put(':', $3a)
        .eval at.put(';', $3b)
        .eval at.put('<', $3c)
        .eval at.put('=', $3d)
        .eval at.put('>', $3e)
        .eval at.put('?', $3f)
        .eval at.put('@', $40)
        .eval at.put('A', $41)
        .eval at.put('B', $42)
        .eval at.put('C', $43)
        .eval at.put('D', $44)
        .eval at.put('E', $45)
        .eval at.put('F', $46)
        .eval at.put('G', $47)
        .eval at.put('H', $48)
        .eval at.put('I', $49)
        .eval at.put('J', $4a)
        .eval at.put('K', $4b)
        .eval at.put('L', $4c)
        .eval at.put('M', $4d)
        .eval at.put('N', $4e)
        .eval at.put('O', $4f)
        .eval at.put('P', $50)
        .eval at.put('Q', $51)
        .eval at.put('R', $52)
        .eval at.put('S', $53)
        .eval at.put('T', $54)
        .eval at.put('U', $55)
        .eval at.put('V', $56)
        .eval at.put('W', $57)
        .eval at.put('X', $58)
        .eval at.put('Y', $59)
        .eval at.put('Z', $5a)
        .eval at.put('[', $5b)
        .eval at.put('\', $5c)
        .eval at.put(']', $5d)
        .eval at.put('^', $5e)
        .eval at.put('_', $5f)
        .eval at.put('`', $60)
        .eval at.put('a', $61)
        .eval at.put('b', $62)
        .eval at.put('c', $63)
        .eval at.put('d', $64)
        .eval at.put('e', $65)
        .eval at.put('f', $66)
        .eval at.put('g', $67)
        .eval at.put('h', $68)
        .eval at.put('i', $69)
        .eval at.put('j', $6a)
        .eval at.put('k', $6b)
        .eval at.put('l', $6c)
        .eval at.put('m', $6d)
        .eval at.put('n', $6e)
        .eval at.put('o', $6f)
        .eval at.put('p', $70)
        .eval at.put('q', $71)
        .eval at.put('r', $72)
        .eval at.put('s', $73)
        .eval at.put('t', $74)
        .eval at.put('u', $75)
        .eval at.put('v', $76)
        .eval at.put('w', $77)
        .eval at.put('x', $78)
        .eval at.put('y', $79)
        .eval at.put('z', $7a)
        .eval at.put('{', $7b)
        .eval at.put('|', $7c)
        .eval at.put('}', $7d)
        .eval at.put('~', $7e)
}

.macro ascii(text) {
        .for(var i=0; i<text.size(); i++) {
                .byte at.get(text.charAt(i))
        }
}

// Convenient macro for checkpoints. Uncomment the body to activate it
.macro Checkpoint(text) {
        /*jsr checkpoint
        .byte 0
        ascii(text)
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
.macro cmp_bp_z(byte) {
        // cmp (byte), z
        .byte $d2, byte
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
        .var dist = arg.getValue() - *
        .var offset = dist - 2
        .byte $80, offset
}
.pseudocommand bnel arg {
        .var dist = arg.getValue() - *
        .var offset = dist - 2
        .byte $d3, <offset, >offset
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
