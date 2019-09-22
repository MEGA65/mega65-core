/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

// Display error and infinite loop on page fault
page_fault:
        jsr reset_machine_state
        ldx #<msg_pagefault
        ldy #>msg_pagefault
        jsr printmessage
        ldy #$00
        // Print PC
        ldz $d649
        jsr printhex
        ldz $d648
        jsr printhex
        // and MAPLO state
        ldz $d64f
        jsr printhex
        ldz $d64a
        jsr printhex
        ldz $d649
        jsr printhex

pf1:    inc $d020
        jmp pf1

msg_pagefault:
        .text "PAGE FAULT: PC=$$$$, MAP=$$.$$$$.00     "

memory_trap:
        sei
        cld
        and #$fe
        tax
        jmp_zp_x(memory_trap_table)

memory_trap_table:
        // $00-$0E
        .word rom_writeprotect
        .word rom_writeenable
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $10-$1E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $20-$2E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $30-$3E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $40-$4E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $50-$5E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $60-$6E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

        // $70-$7E
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction
        .word invalid_subfunction

rom_writeenable:
        lda #$04
        trb hypervisor_feature_enables
        jmp return_from_trap_with_success

rom_writeprotect:
        lda #$04
        tsb hypervisor_feature_enables
        jmp return_from_trap_with_success

