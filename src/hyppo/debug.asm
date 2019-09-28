/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.

    These routines are included in the hickup-build-process primarily
    for debug purposes. It is anticipated that these routines will
    become removed as the code is verified.

    NOTE: that there are two main output streams:
    - the serial debugger (via the USB/COM)
      => messages are sent using the "Checkpoint" function.
    - the screen console (chars displayed by VIC on boot-screen)
      => messages are sent using the "printmessage" and "printhex"
         functions.
    ---------------------------------------------------------------- */

dumpcurrentfd:

        // this function prints to Checkpoint the current_file_descriptor and the offset.

        ldx dos_current_file_descriptor                        // convert .X to char-representation for display
        jsr checkpoint_bytetohex                        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dcfd0+1//
        sty dcfd0

        ldx dos_current_file_descriptor_offset
        jsr checkpoint_bytetohex
        stx dcfd1+1
        sty dcfd1

        jsr checkpoint
        .byte 0
        ascii("current file desc=")
dcfd0:  ascii("xx, and offset=")
dcfd1:  ascii("xx.")
        .byte 0

        rts


//         ========================

dumpfddata:

        // this function prints to Checkpoint the file-descriptor[0].

        ldx dos_file_descriptors+0        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd0+1
        sty dfdd0
        ldx dos_file_descriptors+1        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd1+1
        sty dfdd1
        ldx dos_file_descriptors+2        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd2+1
        sty dfdd2
        ldx dos_file_descriptors+3        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd3+1
        sty dfdd3
        ldx dos_file_descriptors+4        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd4+1
        sty dfdd4
        ldx dos_file_descriptors+5        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd5+1
        sty dfdd5
        ldx dos_file_descriptors+6        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd6+1
        sty dfdd6
        ldx dos_file_descriptors+7        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd7+1
        sty dfdd7

        ldx dos_file_descriptors+8        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd8+1
        sty dfdd8
        ldx dos_file_descriptors+9        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdd9+1
        sty dfdd9
        ldx dos_file_descriptors+10        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdda+1
        sty dfdda
        ldx dos_file_descriptors+11        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfddb+1
        sty dfddb
        ldx dos_file_descriptors+12        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfddc+1
        sty dfddc
        ldx dos_file_descriptors+13        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfddd+1
        sty dfddd
        ldx dos_file_descriptors+14        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfdde+1
        sty dfdde
        ldx dos_file_descriptors+15        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx dfddf+1
        sty dfddf

        jsr checkpoint
        .byte 0
        ascii("FileDesc<=")
dfdd0:  ascii("xx,")
dfdd1:  ascii("xx,")
dfdd2:  ascii("xx,")
dfdd3:  ascii("xx,")
dfdd4:  ascii("xx,")
dfdd5:  ascii("xx,")
dfdd6:  ascii("xx,")
dfdd7:  ascii("xx - ")

dfdd8:  ascii("xx,")
dfdd9:  ascii("xx,")
dfdda:  ascii("xx,")
dfddb:  ascii("xx,")
dfddc:  ascii("xx,")
dfddd:  ascii("xx,")
dfdde:  ascii("xx,")
dfddf:  ascii("xx")
        .byte 0

        rts

//         ========================

dumpsectoraddress:

        // print out this message to Checkpoint
        //

        ldx sd_address_byte3        // MSB        ; convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx sdrscp3+1//
        sty sdrscp3

        ldx sd_address_byte2
        jsr checkpoint_bytetohex
        stx sdrscp2+1
        sty sdrscp2

        ldx sd_address_byte1
        jsr checkpoint_bytetohex
        stx sdrscp1+1
        sty sdrscp1

        ldx sd_address_byte0        // LSB
        jsr checkpoint_bytetohex
        stx sdrscp0+1
        sty sdrscp0

        jsr checkpoint
        .byte 0
        ascii("sd_sector: $d681=")
sdrscp3:ascii("xx")
sdrscp2:ascii("xx")
sdrscp1:ascii("xx")
sdrscp0:ascii("xx.")
        .byte 0

        rts

//         ========================

printsectoraddress:

        // debug message to boot-screen
        //
        ldx #<msg_sectoraddress
        ldy #>msg_sectoraddress
        jsr printmessage

        ldy #$00
        ldz sd_address_byte3 // is $D681+3
        jsr printhex
        ldz sd_address_byte2 // is $D681+2
        jsr printhex
        ldz sd_address_byte1 // is $D681+1
        jsr printhex
        ldz sd_address_byte0 // is $D681+0
        jsr printhex
        rts

//         ========================

// print_disk_table:
//
//                 ; HELPER routine, for debug to screen
//
//                 ldx #<msg_diskdata0
//                 ldy #>msg_diskdata0
//                 jsr printmessage
//
//                 ldx #<msg_diskdata
//                 ldy #>msg_diskdata
//                 jsr printmessage
//
//                 ldy #$00
//                 ldz #$00                ; offset
//                 jsr printhex
//                 ldy #$00
//                 ldz dos_disk_table+0
//                 jsr printhex
//                 ldz dos_disk_table+1
//                 jsr printhex
//                 ldz dos_disk_table+2
//                 jsr printhex
//                 ldz dos_disk_table+3
//                 jsr printhex
//                 ldz dos_disk_table+4
//                 jsr printhex
//                 ldz dos_disk_table+5
//                 jsr printhex
//                 ldz dos_disk_table+6
//                 jsr printhex
//                 ldz dos_disk_table+7
//                 jsr printhex
//
//                 ldx #<msg_diskdata
//                 ldy #>msg_diskdata
//                 jsr printmessage
//
//                 ldy #$00
//                 ldz #$08                ; offset
//                 jsr printhex
//                 ldy #$00
//                 ldz dos_disk_table+8
//                 jsr printhex
//                 ldz dos_disk_table+9
//                 jsr printhex
//                 ldz dos_disk_table+10
//                 jsr printhex
//                 ldz dos_disk_table+11
//                 jsr printhex
//                 ldz dos_disk_table+12
//                 jsr printhex
//                 ldz dos_disk_table+13
//                 jsr printhex
//                 ldz dos_disk_table+14
//                 jsr printhex
//                 ldz dos_disk_table+15
//                 jsr printhex
//
//                 ldx #<msg_diskdata
//                 ldy #>msg_diskdata
//                 jsr printmessage
//
//                 ldy #$00
//                 ldz #$10                ; offset
//                 jsr printhex
//                 ldy #$00
//                 ldz dos_disk_table+16
//                 jsr printhex
//                 ldz dos_disk_table+17
//                 jsr printhex
//                 ldz dos_disk_table+18
//                 jsr printhex
//                 ldz dos_disk_table+19
//                 jsr printhex
//                 ldz dos_disk_table+20
//                 jsr printhex
//                 ldz dos_disk_table+21
//                 jsr printhex
//                 ldz dos_disk_table+22
//                 jsr printhex
//                 ldz dos_disk_table+23
//                 jsr printhex
//
//                 ldx #<msg_diskdata
//                 ldy #>msg_diskdata
//                 jsr printmessage
//
//                 ldy #$00
//                 ldz #$18                 ; offset
//                 jsr printhex
//                 ldy #$00
//                 ldz dos_disk_table+24
//                 jsr printhex
//                 ldz dos_disk_table+25
//                 jsr printhex
//                 ldz dos_disk_table+26
//                 jsr printhex
//                 ldz dos_disk_table+27
//                 jsr printhex
//                 ldz dos_disk_table+28
//                 jsr printhex
//                 ldz dos_disk_table+29
//                 jsr printhex
//                 ldz dos_disk_table+30
//                 jsr printhex
//                 ldz dos_disk_table+31
//                 jsr printhex
//
//                 rts

//         ========================

dump_disk_table:

        // this function prints to Checkpoint the dos_disk_table[0].

        jsr checkpoint
        .byte 0
        ascii("dos_disk_table")
        .byte 0

        ldx dos_disk_table+0                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt00+1
        sty ddt00
        ldx dos_disk_table+1                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt01+1
        sty ddt01
        ldx dos_disk_table+2                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt02+1
        sty ddt02
        ldx dos_disk_table+3                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt03+1
        sty ddt03
        ldx dos_disk_table+4                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt04+1
        sty ddt04
        ldx dos_disk_table+5                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt05+1
        sty ddt05
        ldx dos_disk_table+6                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt06+1
        sty ddt06
        ldx dos_disk_table+7                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt07+1
        sty ddt07

        jsr checkpoint
        .byte 0
ddt00:  ascii("xx,")
ddt01:  ascii("xx,")
ddt02:  ascii("xx,")
ddt03:  ascii("xx,")
ddt04:  ascii("xx,")
ddt05:  ascii("xx,")
ddt06:  ascii("xx,")
ddt07:  ascii("xx")
        .byte 0

        ldx dos_disk_table+8                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt08+1
        sty ddt08
        ldx dos_disk_table+9                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt09+1
        sty ddt09
        ldx dos_disk_table+10                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0a+1
        sty ddt0a
        ldx dos_disk_table+11                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0b+1
        sty ddt0b
        ldx dos_disk_table+12                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0c+1
        sty ddt0c
        ldx dos_disk_table+13                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0d+1
        sty ddt0d
        ldx dos_disk_table+14                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0e+1
        sty ddt0e
        ldx dos_disk_table+15                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt0f+1
        sty ddt0f

        jsr checkpoint
        .byte 0
ddt08:  ascii("xx,")
ddt09:  ascii("xx,")
ddt0a:  ascii("xx,")
ddt0b:  ascii("xx,")
ddt0c:  ascii("xx,")
ddt0d:  ascii("xx,")
ddt0e:  ascii("xx,")
ddt0f:  ascii("xx")
        .byte 0

        ldx dos_disk_table+0+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt10+1
        sty ddt10
        ldx dos_disk_table+1+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt11+1
        sty ddt11
        ldx dos_disk_table+2+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt12+1
        sty ddt12
        ldx dos_disk_table+3+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt13+1
        sty ddt13
        ldx dos_disk_table+4+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt14+1
        sty ddt14
        ldx dos_disk_table+5+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt15+1
        sty ddt15
        ldx dos_disk_table+6+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt16+1
        sty ddt16
        ldx dos_disk_table+7+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt17+1
        sty ddt17

        jsr checkpoint
        .byte 0
ddt10:  ascii("xx,")
ddt11:  ascii("xx,")
ddt12:  ascii("xx,")
ddt13:  ascii("xx,")
ddt14:  ascii("xx,")
ddt15:  ascii("xx,")
ddt16:  ascii("xx,")
ddt17:  ascii("xx")
        .byte 0

        ldx dos_disk_table+8+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt18+1
        sty ddt18
        ldx dos_disk_table+9+16                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt19+1
        sty ddt19
        ldx dos_disk_table+10+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1a+1
        sty ddt1a
        ldx dos_disk_table+11+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1b+1
        sty ddt1b
        ldx dos_disk_table+12+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1c+1
        sty ddt1c
        ldx dos_disk_table+13+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1d+1
        sty ddt1d
        ldx dos_disk_table+14+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1e+1
        sty ddt1e
        ldx dos_disk_table+15+16        // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx ddt1f+1
        sty ddt1f

        jsr checkpoint
        .byte 0
ddt18:  ascii("xx,")
ddt19:  ascii("xx,")
ddt1a:  ascii("xx,")
ddt1b:  ascii("xx,")
ddt1c:  ascii("xx,")
ddt1d:  ascii("xx,")
ddt1e:  ascii("xx,")
ddt1f:  ascii("xx")
        .byte 0

        rts

//         ========================

dump_disk_count:

        lda dos_disk_count

        // print out this message to Checkpoint
        //
        tax                                // convert .X to char-representation for display
        jsr checkpoint_bytetohex        // returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty ddc
        stx ddc+1
        jsr checkpoint
        .byte 0
        ascii("dos_disk_count = ")
ddc:    ascii("xx")
        .byte 0

        rts

//         ========================

delay1sec:

        ldy #$32        // 50dec (frames per sec)
d1s1:   lda $d012        // raster y-value
        cmp #$40
        bne d1s1
d1s2:   cmp $d012
        beq d1s2
        dey                // do this loop 50 times
        bne d1s1

        rts

//         ========================

debug_show_cluster_number:

        // work out where the cluster number should be
        jsr dos_get_file_descriptor_offset
        phx
        jsr checkpoint_bytetohex
        stx dfanc_fd
        plx
        txa
        clc
        adc #dos_filedescriptor_offset_currentcluster
        tay

        lda dos_file_descriptors+3,y
        phy
        tax
        jsr checkpoint_bytetohex
        sty dfanc_hex+0
        stx dfanc_hex+1

        ply
        phy

        ldy dos_scratch_byte_2
        lda dos_file_descriptors+2,y
        tax
        jsr checkpoint_bytetohex
        sty dfanc_hex+2
        stx dfanc_hex+3

        ply
        phy

        ldy dos_scratch_byte_2
        lda dos_file_descriptors+1,y
        tax
        jsr checkpoint_bytetohex
        sty dfanc_hex+4
        stx dfanc_hex+5

        ply

        ldy dos_scratch_byte_2
        lda dos_file_descriptors+0,y
        tax
        jsr checkpoint_bytetohex
        sty dfanc_hex+6
        stx dfanc_hex+7


        jsr checkpoint
        .byte 0
        ascii("File Desc #")
dfanc_fd:
        ascii("$: curr_cluster=$")
dfanc_hex:
        ascii("$$$$$$$$")
        .byte 0

        rts

