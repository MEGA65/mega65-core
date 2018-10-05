Secure mode disables all IO, except $D6Bx (touch pad) and $D6F0-E (audio),
the SIDs and the VIC-IV.  This is enabled by setting bit 7 of the protected
hardware register.

The CPU sets the two upper bits in protected_hardware ($D672), which is
detected by the monitor (in software in the embedded 65C02 that runs the
monitor).  The Hypervisor should infinite loop while waiting for this to happen.

*** We should modify the CPU to stop itself at this point.

The monitor then asks the user to ACCEPT or REJECT the transition. If the
user accepts, then the monitor should resume the CPU, and the CPU should be placed
into user mode, instead of hypervisor mode, presumably by having the monitor
synthesising a write to $D67F to exit hypervisor mode.

*** Better is have the monitor provide the CPU a flag that indicates whether it
should be in a secure compartment or not. If that signal is wrong, then the CPU
stops.  When the flags match, this allows the hypervisor to resume the entry
routine, which causes the hypervisor to exit to user land with the loaded
secure service running.

At this point, the secure compartment is running, and ANY hypervisor trap should
instead cause the monitor to reactivate in secure mode colours, and allow the
user to accept or reject.

*** We should modify the CPU to stop itself at this point.

The user then types ACCEPT or REJECT in the monitor. If REJECT was typed, the
monitor erases all of memory before allowing the CPU to continue.

