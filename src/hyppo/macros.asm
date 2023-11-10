;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */


// Convenient macro for checkpoints. Uncomment the body to activate it
!macro Checkpoint .text {
;;jsr checkpoint
;;!8 0
;;!text .text
;;!8 0
}
