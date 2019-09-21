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

.define ht {
        .var ht = Hashtable()
        .eval ht.put(' ', $20)
        .eval ht.put('!', $21)
        .eval ht.put(@"\"", $22)
        .eval ht.put('#', $23)
        .eval ht.put('$', $24)
        .eval ht.put('%', $25)
        .eval ht.put('&', $26)
        .eval ht.put(''', $27)
        .eval ht.put('(', $28)
        .eval ht.put(')', $29)
        .eval ht.put('*', $2a)
        .eval ht.put('+', $2b)
        .eval ht.put(',', $2c)
        .eval ht.put('-', $2d)
        .eval ht.put('.', $2e)
        .eval ht.put('/', $2f)
        .eval ht.put('0', $30)
        .eval ht.put('1', $31)
        .eval ht.put('2', $32)
        .eval ht.put('3', $33)
        .eval ht.put('4', $34)
        .eval ht.put('5', $35)
        .eval ht.put('6', $36)
        .eval ht.put('7', $37)
        .eval ht.put('8', $38)
        .eval ht.put('9', $39)
        .eval ht.put(':', $3a)
        .eval ht.put(';', $3b)
        .eval ht.put('<', $3c)
        .eval ht.put('=', $3d)
        .eval ht.put('>', $3e)
        .eval ht.put('?', $3f)
        .eval ht.put('@', $40)
        .eval ht.put('A', $41)
        .eval ht.put('B', $42)
        .eval ht.put('C', $43)
        .eval ht.put('D', $44)
        .eval ht.put('E', $45)
        .eval ht.put('F', $46)
        .eval ht.put('G', $47)
        .eval ht.put('H', $48)
        .eval ht.put('I', $49)
        .eval ht.put('J', $4a)
        .eval ht.put('K', $4b)
        .eval ht.put('L', $4c)
        .eval ht.put('M', $4d)
        .eval ht.put('N', $4e)
        .eval ht.put('O', $4f)
        .eval ht.put('P', $50)
        .eval ht.put('Q', $51)
        .eval ht.put('R', $52)
        .eval ht.put('S', $53)
        .eval ht.put('T', $54)
        .eval ht.put('U', $55)
        .eval ht.put('V', $56)
        .eval ht.put('W', $57)
        .eval ht.put('X', $58)
        .eval ht.put('Y', $59)
        .eval ht.put('Z', $5a)
        .eval ht.put('[', $5b)
        .eval ht.put('\', $5c)
        .eval ht.put(']', $5d)
        .eval ht.put('^', $5e)
        .eval ht.put('_', $5f)
        .eval ht.put('`', $60)
        .eval ht.put('a', $61)
        .eval ht.put('b', $62)
        .eval ht.put('c', $63)
        .eval ht.put('d', $64)
        .eval ht.put('e', $65)
        .eval ht.put('f', $66)
        .eval ht.put('g', $67)
        .eval ht.put('h', $68)
        .eval ht.put('i', $69)
        .eval ht.put('j', $6a)
        .eval ht.put('k', $6b)
        .eval ht.put('l', $6c)
        .eval ht.put('m', $6d)
        .eval ht.put('n', $6e)
        .eval ht.put('o', $6f)
        .eval ht.put('p', $70)
        .eval ht.put('q', $71)
        .eval ht.put('r', $72)
        .eval ht.put('s', $73)
        .eval ht.put('t', $74)
        .eval ht.put('u', $75)
        .eval ht.put('v', $76)
        .eval ht.put('w', $77)
        .eval ht.put('x', $78)
        .eval ht.put('y', $79)
        .eval ht.put('z', $7a)
        .eval ht.put('{', $7b)
        .eval ht.put('|', $7c)
        .eval ht.put('}', $7d)
        .eval ht.put('~', $7e)
}

.macro ascii(text) {
        .for(var i=0; i<text.size(); i++) {
                .byte ht.get(text.charAt(i))
        }
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
