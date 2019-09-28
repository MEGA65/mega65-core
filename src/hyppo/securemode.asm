/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

securemode_trap:

        // XXX - The following is what we SHOULD do for the complete system to work:
        // XXX Freeze current process to slot
        // XXX Find the requested service
        // XXX Load the requested service

        // Set secure mode flag, and set PC and memory map in the secure service

        // XXX - What we WILL do for now, is just enable secure mode, and set the PC to
        // $8000.

        // First, disable access to cartridge, force 50MHz mode and 4502 CPU personality
        lda #$32
        sta hypervisor_feature_enables

        // Second, disable all protecteed IO access, and mark matrix mode and secure mode.
        // This also freezes the CPU until the monitor acknowledges that the CPU is in
        // secure mode.  Only after that will the remainder of this routine proceed,
        // and thus allow the secure program to run.
        // XXX - This means that a little piece of the hypervisor is still running when we
        // go into the secure compartment.  For this reason, the CPU needs to be blocked
        // from writing to hypervisor_secure_mode_flags when in that state.
        lda #$c0
        sta hypervisor_secure_mode_flags


        // At this point, the monitor detects that we have asked for secure mode, and will
        // ask for the user to either accept or reject.  If they accept, the CPU will be
        // resumed into the loaded service.  If not, all memory will be erased, before the
        // CPU is resumed.  For now, a rejected action will just require a reboot. But
        // later, we will have the monitor tell the hypervisor by synthesising an appropriate
        // trap after wiping memory, presumbly by causing a write to a $D65x register.
        jmp nosuchtrap


leave_securemode_trap:

        // If we get here, we have left a secure compartment, with either memory erased
        // or intact.  Either way, we should hand control back to the user, and disable
        // matrix mode display.

        // XXX - Debug
        inc $d021

        lda #$00
        sta hypervisor_secure_mode_flags

        jmp nosuchtrap
