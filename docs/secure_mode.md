Secure mode disables all IO, except $D6Bx (touch pad) and $D6F0-E (audio),
the SIDs and the VIC-IV.  This is enabled by setting bit 7 of the protected
hardware register.

The CPU sets the two upper bits in protected_hardware ($D672), which is
detected by the monitor (in software in the embedded 65C02 that runs the
monitor).  The Hypervisor should infinite loop while waiting for this to happen.
The monitor then asks the user to ACCEPT or REJECT the transition. If the
user accepts, then the monitor should resume the CPU, and the CPU should be placed
into user mode, instead of hypervisor mode, presumably by having the monitor
synthesising a write to $D67F to exit hypervisor mode.

At this point, the secure compartment is running, and ANY hypervisor trap should
instead cause the monitor to reactivate in secure mode colours, and allow the
user to accept or reject.