


C65GS
FPGA Computer
User Manual

1.0 Introduction
1.1 Purpose
1.2 Get Involved
2.0 Overview
2.1 Processing Cores
2.2 Power-on/Reset Via The C65GS Hypervisor
2.3 C65/C64 KERNAL & BASIC
3.0 Getting Started
3.1 Switching Modes, Mounting Disks and Loading Files via Ethernet
3.2 Simple D81 Chooser for the SD Card
4.0 System Documentation
4.1 Keyboard Control and Mapping
4.2 Remote Head and Screen-Shotting via VNC
4.3 Remote Serial Monitor (handy for debugging)
4.4 VIC-IV
4.4.1 Enhanced Sprites
4.5 Task Switcher
4.5.1 Overview
4.5.2 Hypervisor
4.5.3 Task Registers
4.5.4 Thumbnail
4.6 Colour RAM
5.0 Memory Maps
5.1 Banking Memory
5.2 Addressing 32-bit Locations
32-bit Memory Addresses using 32-bit indirect zero-page indexed addressing
5.3 Common Locations
5.4 C64 Locations
5.5 C65 Locations
5.6 GS Locations
6.0 Code Recipes
6.1 Overview
6.2 The MAP Opcode
6.3 Character Mode
6.4 Clear the Raster IRQ
6.5 Clearing bits in a byte
6.6 32-bit Memory Addresses using 32-bit indirect zero-page indexed addressing
6.7 Sending an Ethernet Frame
6.8 Loading Data Via Ethernet
7.0 Differences Between the C65’s 4502 and C65GS’s GS4510
7.1 Overview
7.2 Emulated NMOS Read-Modify-Write Behaviour for C64 Compatibility
7.3 Flat Memory Map Addressing Modes & Access
8. 4502 Opcodes
4502 Opcode Table
9. 4502 Registers
10. 65CE02 Interrupts
11. 65CE02 Addressing Modes
12. 65CE02 Instruction Set



1.0 Introduction
1.1 Purpose
“...rather a bit of reimagining the C65 for the 21st century with good backward compatibility.” - Paul (1 Feb 2014)

The C65GS is a re-imagination of the C65/C64DX computer using a modern FPGA to implement most functions.  It differs from the C65 in that it aims to offer a near 100% C64-compatible mode by providing a dedicated 6510+VIC-II emulation independent of the additional more capable processor and video chips. That plan is that both functions operate in parallel, and input and output is switched dynamically between the two under programmer control. Dedicated VIC-II is currently unlikely due to space constraints.  6510/6502 emulation, with illegal instructions, however is still planned. This will be implemented by the GS4510 emulating a 6502, using a little dedicated hardware support. 
 
The designer, Dr. Paul Gardner-Stephen, intends to create “the most powerful 8-bit computer to date by various measures”:

Better graphics than the Apple IIgs, Atari 800 or Plus/4: 1920x1200 @ 60Hz, 256 colour palette from 4,096 colours (and later from 24-bit colour palette with HDMI output) via the VIC-IV video controller.
Better sprites than the C64.
Faster CPU than the SuperCPU or any available 65C816 CPU (20MHz), and ideally with enough headroom to beat a 20MHz 65C816 running in 16-bit mode.
More RAM than a fully expanded Apple IIgs or C65 (~8.125MB). It will initially have 128KB of chipram like the C65, plus 16MB of slowram (which is also used as ROM).
    Presently the 128MB DDR2 RAM on the Nexys4 DDR board isn’t supported. I’ll take a look at this when I have time, but it has been rather frustrating so far.
Comparable or better sound capability than the Apple IIgs.
More backward compatible than the C65 or any 65C816 based machine. The main issue here is actually quite easy to fix, consisting of restoring the 6502 read-write-modify behaviour of instructions like INC and ASL.
Sufficiently C65 compatible to be able to run a stock C65 ROM.

Note that perfect C65 compatibility is not high on the list, given the relative lack of software available for it anyway. There is no intention of implementing the bit-planar graphics modes, as they were never really a good idea for an 8-bit computer, requiring way too many cycles to edit individual pixels, and the C65’s bitplanes lacking the features necessary to allow efficient scrolling.
 
Instead, the new graphics modes are enhanced forms of character mode. Enhancements to  text mode include:
16-bit character set mode, where two screen RAM and two colour RAM bytes describe each character, allowing up to 8,192 distinct characters in a character set.
Allowing characters to be composed of 8x8 fully addressable 256-colour pixels, i.e., requiring 64 bytes per character. This also saves lots of RAM and CPU cycles when most of the screen is blank or repetitive.
The same display can include a mix of 256-colour characters and regular bi-colour/multi-colour characters.
VIC-III extended attributes for each character: blink, bold, reverse and underline.
New VIC-IV extended attributes: flip horizontally and flip vertically.
Variable character width, to make rendering proportional fonts easier.
Variable character height, to make rendering proportional fonts easier (work in progress).
Terminate character generator token ($FFFF) in 16-bit character set mode to save screen and colour RAM with large and variable-width character displays.
Anti-aliased text mode where 64-byte character definitions are composed of alpha-values to blend between the current foreground and background colour, allowing multi-colour anti-aliased text without consuming extra palette entries (work in progress).
High-resolution bi-colour and multi-colour modes will also be available.  
As with the VIC-II, these modes can be mixed and matched on the same display. 

Enhanced sprites are also planned that will feature their own 4KB sprite data memory, allowing up to 64x64 256-colour sprites (work in progress).  

The new and enhanced features of the VIC-IV will be described more fully in the appropriate section of this document.

In short, this project aims to preserve most of the fun elements of an 8-bit computer, while providing some 21st century improvements that will make the machine fun to program and use, and who knows, maybe help foster new life in the demo scene.
 
From a hardware perspective, the C65GS is purposely being implemented using an off-the-shelf FPGA development board designed for university students (Nexys4 FPGA board and a 2 giga-byte SD card) for several reasons. First, the boards are relatively cheap for their performance, and the price will only reduce over time. Second, the Nexys4 board has many built-in peripherals, like ethernet, VGA output, USB keyboard input. Finally, availability of the C65GS will not be based on community production runs.

1.2 Get Involved
                   
You can follow Dr. Paul's blog at: http://c65gs.blogspot.com/, where he posts regular progress reports.

If you're a hardware hacker and into VHDL, you can tinker with the programming itself at: https://github.com/gardners/c65gs. Equipment you need:

A Nexys4 FPGA board, available from Digilent and their distributors. If you have a university or school email address, i.e., *@*.edu.* or *@*.edu, the board is available at half-price.
An SD card.  For the time being it is safest to use a 2GB or smaller SD card, as large capacity card (SDHC) support is not well tested.

You can also join the Google Group at: https://groups.google.com/forum/#!forum/c65gs-development.


2.0 Overview
The following diagram gives a general, if slightly misleading view of the C65GS architecture.
KEYS
 + USER PORT
 | + CONTROL PORTS                 EXPANSION PORT
 | | +                                  + +  +---+
 | | |                                  | |  |   |
++-+-+++++++                            | |  |   |-+
|          |                            | |  |   | +------> RGBA
|          +---------------------------+------+   |     
|  GS4510  +----------------------------------+   |
|          |                             | |  |   |
|     +---+|  +---+  +---+  +---+  +---+ | |  | V |
|     |   ||  |   |  |   |  |   |  |   | | |  | I |     
|     | D ++--+ F +--+ S +--+ S +--+ R +-+----+ C |  +--+  +--+  +--+  +--+
|     | M ++--+ D +--+ I +--+ I +--+ O +------+ | |  |  |  |  |  |  |  |  |
|     | A ||  | C |  | D |  | D |  | M |   |  | I +--+  +--+  +--+  +--+  |
|     | G ||  |   |  |   |  |   |  |   |   |  | V +--+  +--+  +--+  +--+  |
|     | I ++--+   +--+   +--+   +--+   +---+--+   +--+  +--+  +--+  +--+  |
|     | C ++--+   +--+   +--+   +--+   +------+   +--+  +--+  +--+  +--+  |
|     |   ||  |   |  |   |  |   |  |   |      |   |  |  |  |  |  |  |  |  |
+--+--+---+|  +++-+  +-+-+  +-+-+  +---+      +---+  +--+  +--+  +--+  +--+
   |           ||      |      |                       128KB CHIPRAM + 16MB SLOWRAM
   |           ||      R      L
SERIAL BUS     ||      SPEAKERS
               ++
             SD CARD

2.1 Processing Cores

The C65GS computer is planned to have several processing cores and video cores that operate in an integrated manner.

For C65GS mode:

- GS4510 (SailFish), a 4502 instruction-compatible processor with integrated MMU capable of addressing 256MB of RAM. This is effectively a 48MHz 4502-compatible CPU, except for the changes that allow access to additional address space.  Some instructions take one or two more cycles than on a real 4502, this being a small trade-off for approximately 15x higher clock speed than the C65’s 4502.

- GS6569 VIC-IV (VampireSquid), a 6569-inspired video controller, directly driving a 1920x1200@60Hz VGA output, supporting a 256-colour palette drawn from a 24-bit* colour space, and higher-resolution modes, up to 1920x1200. All higher-resolution modes are normally text modes (although high-resolution VIC-II bitmap mode is also supported), using standard or 256-colour colour characters, so that high resolution modes can be used without consuming too much memory. Support for variable-width is also included, and anti-aliased characters are planned in the near future.

Highly accurate compatibility cores for C64 mode (not yet implemented, likely to be created with the help of the 6502hackers community):

- 6510 compatible processor
- 6567/9 (VIC-II) compatible video generator.

Compatibility cores for 1541 emulation (not yet implemented, likely to be created with the help of the 6502hackers community):

- 6502 compatible processor
- 6522 compatible CIA cores.

* On the prototype Nexys4 FPGA and some other FPGA boards the colour depth of the VIC-IV is limited to 12-bit due to limitations in the VGA interface hardware.
2.2 Power-on/Reset Via The C65GS Hypervisor 
                   
On reset C65GS switches the CPU to hypervisor mode, maps the 16KB hypervisor ROM at $8000-$BFFF, and jumps to $8100.  In hypervisor mode all CPU registers, including the normally inaccessible memory mapping registers are exposed at $D640-$D67F, allowing the hypervisor to freely manipulate the state of the computer.  In this mode, it initialises the SD card interface, uses a simple FAT32 implementation to find the 128KB C65 ROM which must be called C65GS.ROM and be located in the root directory, loads it into fastram at $20000-$3FFFF, configures the machine state to act as though it had just reset and loaded the reset vector from the ROM. The hypervisor then exits and transfers control to the loaded rom by writing to $D67F.

To provide further convenience, the hypervisor code checks if any of the numbers 0 through 9 are held down on reset, and if so, loads C65GSx.ROM instead of C65GS.ROM, where x is the number that was held down.  This allows easy selection between 11 different ROMs.

The hypervisor also attempts to find a D81 disk image named C65GS.D81 in the root directory of the SD card, and then mount it using the F011 emulation hardware. 

The final convenience that the hypervisor provides is to load two utility programs into memory between $C000 and $CFFF, so that they can be easily accessed from C64 mode.  A D81 image selector is loaded at $C000 (SYS 49152), allowing mounting of any D81 file from the root directory of the SD card.  A simple ethernet loading programme is loaded at $CF80 (SYS 53120) that can be used to execute special UDP packets.  The etherload programme from the C65GS github repository uses this to provide a very fast loader, achieving typical load speeds of around 2,000KB/second.  Typical 40KB C64 programmes appear to load instantaneously.
2.3 C65/C64 KERNAL & BASIC
                   
The C65GS currently uses a stock C65 ROM (currently version 910111) to operate C65 and C64 mode.  This has several benefits.  First, it provides the most convenient path for C65 compatibility.  Second, it is also convenient for a reasonable level of C64 compatibility, while still providing access to the SD card interface via the C65 internal drive DOS. 
 
This is supported by the GS4510 implementing all 4510 instructions and addressing modes, and by the C65GS’s SD card controller providing C65 F011 floppy-controler emulation registers.

For the curious, the differences between the C64 KERNAL and the C65 one is primarily the removal of the cassette routines and putting in sufficient intercepts to allow the C65 DOS to be used from C64 mode. Other smaller changes include making 8 the default device number, and changing the shift-RUN/STOP text so that it loads the first file from disk and runs it. Also, unlike the C128, the C65 boots first into C64 mode, and the CPU’s reset vector is pointed to a small routine at $E4B8 that initialises DOS for the internal drive, and then checks for a C64 cartridge or if the C= key is being held down.  If there is no reason to remain in C64 mode, then it switches to C65 mode.

The internal drive DOS routines have been intercepted using an interesting approach. First, $C0 ceases to indicate the tape motor state, and instead indicates whether the current drive is on the serial IEC bus, or handled by the internal 1581 DOS. This is checked using one of the new 4510 opcodes, BBS7, which branches on whether bit 7 is set in a zero-page byte, without having to use the accumulator. If the drive is on the IEC bus, then the normal C64 KERNAL routine is used. However, if the drive is the internal one, then the C65 1581 DOS is banked in to $8000 - $BFFF (conveniently leaving the C64 KERNAL still in view), and then the appropriate vector in that ROM is called. Notice the use of the new indirect mode of the JSR instruction (opcode $22).

Memory banking, including to switch between C64, C65 and DOS memory contexts involves the use of the MAP instruction, which sets the memory map. One of the curious features of the 4510 is that all interrupts, both IRQs and NMIs are inhibited until a NOP instruction ($EA) is  The interesting thing for now is to know that NOP is no longer really NOP. The MAP instruction prevents both IRQ and NMI interrupts until a NOP instruction is run. NOP is consequentially also known as End Of Mapping (EOM) on the 4510.
3.0 Getting Started
3.1 Switching Modes, Mounting Disks and Loading Files via Ethernet
                   
GO64 will get you from C65 mode into C64 mode.

SYS49152 ($C000) in C64 mode will give you a crude menu to select a D81 disk image to mount from the SD card storage.

SYS53120 ($CF80) in C64 mode will start an ethernet slave program that allows memory to be loaded very quickly from another computer.  Typical LOAD speed is 2.4MB/sec, with a theoretical maximum of about 10MB/sec.

SYS58552 in C64 mode will take you back to C65 mode, without un-mounting the last disk image.


3.2 Simple D81 Chooser for the SD Card
                   
This chooser reuses much of the FAT32 code from the kickstart ROM, and allows you to say Y or N to each image in turn. Once you say Y to an image, it makes it available for use. It is included in the Kickstart ROM, which then copies the program to $C000, so that it can be entered with SYS49152 from C64 mode.

One of Paul’s students is working on an improved menu-based disk chooser.




4.0 System Documentation
4.1 Keyboard Control and Mapping
The USB keyboard layout is designed for use with a KeyRah v2, and is largely positional.  RESTORE is PAGEUP.

Holding RESTORE down for 3 - 5 seconds will reset the machine instead of triggering an NMI.  Consequently, NMIs are triggered when the RESTORE key is released.  Holding RESTORE down for more than about 5 seconds does nothing -- neither an NMI nor RESET is produced.
4.2 Remote Head and Screen-Shotting via VNC
The C65GS is also capable of automatically outputting its 1920x1200 graphical display via its 100mbit ethernet port.  This can be combined with the videoproxy and vncserver programmes for UNIX-like systems (Linux and Mac) in the http://github.com/gardners/c65gs repository to provide remote VNC access to the C65GS -- complete with graphical display and keyboard/joystick input -- and to the serial monitor interface.  By default the VNC server runs on port 5900, and the serial monitor interface is made available on port 4510.

To start the VNC server, first make sure that vncserver and videoproxy are compiled.  The videoproxy program currently requires promiscuous mode on the ethernet adapter, so must be run as root.  It takes the name of the ethernet port to which the C65GS is connected as its sole argument.  It may be run in the background. The ethernet adapter must be configured to allow ethernet frames of at least 2048 bytes.  The method for configuring this varies from operating-system to operating-system.  The final step is to run vncserver giving it the full path to the virtual serial port as its sole argument.  This is required because the serial monitor interface is used to deliver key-presses to the C65GS.  Drawing this all together, the following commands are one example of how the VNC server can be started:
$ sudo ./videoproxy en0 &
$ ./vncserver /dev/cu.usbserial-1237B

You should now be able to connect to the C65GS via VNC on localhost:5900.  Note that on some operating systems you will need to install a VNC client, because the included VNC client may not work with VNC servers that do not require a password. VNC Viewer is a good option for Apple computers.

Note that when connected by VNC, RESTORE is mapped to F9.  Thus to reset the C65GS via VNC one must hold the F9 key for approximately 3 seconds.
Note also that the remote head reflects the display of the single C65GS instance. That is, a local operator and one or more remote operators will all be typing into the same computer.  This can have both entertaining and frustrating effect.

Finally, the remote video display is quantised to an 8-bit colour cube, and does not display the full data of each raster line due to bandwidth limitations of the 100mbit ethernet interface.  Therefore colour tinting and at times severe artifacts may be visible on the remote display.  Also, the remote display is 1920x1200, and so you may need to manually configure client window scaling in your VNC client so that your “big” computer can handle the display from your “little” one.
4.3 Remote Serial Monitor (handy for debugging)
The USB power cable for the Nexys4 also provides a virtual serial port. This is used to create a debug interface for the C65GS.  By connecting at 230400 bps to the serial port exposed by the cable, one is able to interact with a monitor-like interface that allows dumping, filling and setting of memory, as well as inspecting, single-stepping and issuing breakpoints to the CPU.

Note that you may not put a space between serial monitor commands and their first argument, or you will receive a syntax error. You may, however, leave leading zeroes off of hexadecimal values.  For example “s 0400 08 05 0c 0c 0f” would be invalid, but “s400 8 5 c c f” would be accepted.

r - display CPU registers and last instruction executed.

d<addr> - display memory from the perspective of the current CPU memory map, thus addresses are limited to $0000-$ffff

m<addr> - display memory from the 28-bit flat address space, thus addresses may be between $0000000-$FFFFFFF.

D<addr> - like d, but shows 512 bytes of memory

D - like D, but assumes to continue from the last address

M<addr> - like m, but shows 512 bytes of memory

M - like M, but assumes to continue from the last address

s<addr> <value …> - set memory, using 28-bit address.

S<addr> <value …> - set memory from the perspective of the current CPU memory map, thus addresses are limited to $0000-$FFFF.

b<addr> - Set a cpu breakpoint at the specified address. Note this is triggered whenever PC equals the address.  There are some bugs with this, as pre-fetching of instructions can trigger the break-point, and break-points might not be correctly caught between certain instructions. Only one break point can be set at a time.

b - disable cpu breakpoint.

w<addr> - Like b<addr>, but sets a breakpoint to trigger when the specified address is modified.

w - clear ‘w’ breakpoint.

t0 - resume CPU after a breakpoint.

t1 - stop CPU

tc - display CPU state after every instruction executed.  Runs at about 100Hz effective speed. Handy for debugging.

ENTER - (i.e., an empty line). Single step one instruction if CPU is stopped

e - set a break point to occur based on CPU flags.

h - display slightly outdated and misleading help.

f<addr> <addr> <value> - fill memory
4.4 VIC-IV
4.4.1 Enhanced Sprites
               
The basic design of the new VIC-IV sprites, is that each sprite will have a dedicated 4KB memory buffer, and will be strictly one byte per pixel.  This allows for sprites of up to 64x64 256 colour pixels. It is likely that different sizes and shapes will be selectable.

Like with the VIC-II, one physical sprite can be used multiple times on a frame without reloading the data by altering the data offset within the 4KB block, and possibly the height and width of the sprite.  I am also thinking about allowing sprites to be much wider.

Foreground/background priority will be by applying a bit mask to the character/bitmap data to decide whether it should appear in front of the sprite or behind the sprite.  This will allow sprites and the background to perform many of the functions of Amiga-style bit planes, although the way it will be done will be rather different.

Bit masks are also provided to allow modification of the colours of sprites.  For example applying and AND mask of $1f and an OR mask of $80 will translate all colours to $80-$9F.  This can be used to allow a common image to be used for different characters in a game, with selected colours being altered.  The 256 colour sprite palette can be separated from the bitmap palette, so there is improved flexibility compared to just applying bit masks to a flat 256 colour palette shared by all on-screen elements.  If I get really excited it might even be possible to use the other two 256 colour palettes for different sprites.

Finally, I intend to provide hardware scaling and rotation support.  I thought about having simple angle and zoom factor settings, but currently I am thinking that I will simply provide a linear 2D transformation matrix per sprite so that other effects can also be used.

The registers for the VIC-IV sprites are currently planned to live at $D710-$D7FF, allowing for up to 15 of these sprites, but there may end up being less than these depending on how many I can wrangle in.

All this is subject to change, as is the register map, but here is the structure I am currently looking at:

$D7x0-$D7x1 - Enhanced sprite X position in physical pixels (lower 12 bits)
$D7x1.4-7   - Enhanced sprite width (4 -- 64 pixels)
$D7x2-$D7x3 - Enhanced sprite Y position in physical pixels (16 bits)
$D7x3.4-7   - Enhanced sprite height (4 -- 64 pixels)
$D7x4       - Enhanced sprite data offset in its 4KB SpriteRAM (x16 bytes)
$D7x5       - Enhanced sprite foreground mask
$D7x6       - Enhanced sprite colour AND mask (sprite not visible if result = $00)
$D7x7       - Enhanced sprite colour OR mask
$D7x8-$D7x9 - Enhanced sprite 2x2 linear transform matrix 0,0 (5.11 bits)
$D7xA-$D7xB - Enhanced sprite 2x2 linear transform matrix 0,1 (5.11 bits)
$D7xC-$D7xD - Enhanced sprite 2x2 linear transform matrix 1,0 (5.11 bits)
$D7xE-$D7xF - Enhanced sprite 2x2 linear transform matrix 1,1 (5.11 bits)

The attentive reader will note that nowhere does this address the 4KB data blocks for each sprite.  This will be direct mapped in the 28-bit address space.  I am tossing around the idea of over-mapping it with the 64KB colour RAM at $FF80000 (the first 1KB of which is also available at $D800 for C64 compatibility).  The reason for this is that the 4KB sprite RAM will probably be write-only to simplify the data plumbing.  However, to allow for freezing (and hence multi-tasking), I really do want some way to read the sprite data.  The trade-off of course is that this means that you wouldn't be able to use all 64KB for colour RAM if it also being used as a proxy to the sprite RAM data.
4.5 Task Switcher               
4.5.1 Overview 
One of the features I have wanted to include in the C65GS from early on is some sort of task switching and rudimentary multi-tasking.

Given the memory and processor constraints, I don't see the C65GS as running lots of independent processes at the same time.  Rather, I want it to be possible to easily switch between different tasks you have running.

For example, you might be using Turbo Assembler to write some code, and decide to take a break playing a game for a few minutes, but don't want to have to reload Turbo Assembler and your source code again.

Or better, with a patched version of Turbo Assembler you might want to edit in one task and have it assemble into a separate task, and switch back and forth between them as you see fit.

It would also be nice to be able to have certain types of background processing supported.  For example, being able to leave IRC or a download running in the background, with it waking up whenever a packet arrives or a timeout occurs.

For all these scenarios, it also makes sense to be able to quarantine one task from another, so that they cannot write to one another' memory or IO without permission.  This implies the need for some sort of memory protection, and supervisor mode that can run a small operating system to control the tasks (and their own operating systems) running under it.

Thus, what we really want is something like VirtualBox that can run a hypervisor to virtualise the C65GS, so that it can have C64 or C65 "guest operating systems" beneath, and keep them all separate from each other.

This doesn't actually need much extra hardware to do in a simplistic manner.
4.5.2 Hypervisor
                   
First, we need the supervisor/hypervisor CPU mode that maps some extra registers.  I have already implemented this with registers at $D640-$D67F.
Second, to make hypervisor calls fast, the CPU should save all CPU registers and automatically switch the memory map when entering and leaving the hypervisor.  I have already implemented this, so that a call-up into the hypervisor takes just one cycle, as does returning from the hypervisor.

Third, we need to make the hypervisor programme memory only visible from in hypervisor mode.  I have already implemented this.  The hypervisor program is mapped at $8000-$BFFF, with the last 1KB reserved as scratch space, relocated zero-page (using the 4510's B register), and relocated stack (again, using the 4510's SPH register).  The KickStart ROM starts in hypervisor mode, loads the target operating system, prepares the CPU state for the target, including reading the reset entry vector from $FFFC-D of the target ROM, and then exits hypervisor mode, causing the target operating system to start.
4.5.3 Task Registers               
Fourth, we need some registers that allow us to control which address lines on the 16MB RAM are available to a given task, and what the value of the other address lines should be.  This would allow us to allocate any power-of-two number of 64KB memory blocks to a task.  When a task is suspended, it's 128KB chipram and 64KB colour RAM and IO status can be saved into other 64KB memory blocks that are not addressable by the task when it is running.  This I have yet to do.

Fifth, we need to be able to control what events result in a hypervisor trap, so that background processes can run, and also so that the hypervisor can switch tasks.  The NMI line is one signal I definitely want to trap, so that pressing RESTORE can activate the hypervisor.

By finishing these things, and then writing the appropriate software for the hypervisor, it shouldn't be too hard to get task switching running on the C65GS.
4.5.4 Thumbnail                   
For a task-switcher to be nice, it would be really handy to be able to show a low-res screen-shot of the last state of each task so that the user can visually select which one they want.  In other words, to have something that is not too unlike the Windows and OSX window/task switcher interfaces.

However, this is tricky on an 8-bit computer that has no frame buffer, and may be using all sorts of crazy raster effects.

Thus I need some way to have the VIC-IV update a little low-res screen shot, i.e., a thumbnail image, that the hypervisor can read out, and retain for later task-switching calls to show the user what was running in each task before they were suspended.

So I set about implementing a little 4KB thumbnail buffer which is automatically written to by the VIC-IV, and which can be read from the hypervisor.  This resolution allows for 80x50, which should be sufficient to get the idea of what is on a display.  Each pixel is an 8-bit RRRGGGBB colour byte.

Because the VIC-IV writes the thumbnail data directly from the pixel stream, it occurs after palette selection, sprites and all raster effects.  That is, the thumbnails it generates should be "true".
4.6 Colour RAM
                   
The $DFFx memory accesses are not to the CIAs, but to the end of screen RAM.  Setting bit 0 in $D030 replaces $DC00-$DFFF with an extra 1KB of colour RAM, which is in fact the last 2KB of the 128KB of main RAM of a C65, and hence is 8 bit RAM, unlike the 4-bit colour RAM on the C64.
The $D030 flag is primarily for making the 2KB colour RAM conveniently available to the kernel when working with an 80-column, and hence 2,000 byte screen.  Of course this leaves a few bytes spare at the end that are nicely used here to save and restore registers when the stack cannot be used because memory is being remapped.

On the C64 the colour RAM is a separate 1KB x 4 bit memory.  The C65, however, which can require almost 2KB of colour RAM for 80 column mode.  Also, the upper four bits of the colour RAM represent extended attributes.  As a result the C65 needs 2KB of 8-bit RAM for colour RAM.  Rather than require a separate part, the designers of the C65 would have its colour RAM as the top 2KB ($1F800-$1FFFF) of the 128KB main memory.

This means that a stock C65 actually has a little bit less RAM available than a C128. Actually, a stock C65 has quite a bit less available RAM, because the DOS eats another 8KB of RAM.
When I began designing the C65GS, I had in mind that it would support much larger text modes than the C64 or C65. With a native resolution of 1920x1200, it is possible to run a 240x150 character text mode. This means we need up to 36,000 (35.2KB) bytes of colour RAM. It seemed bad enough to lose 2KB of precious chip RAM, let alone losing more than 1/4 of all RAM, just for colour data for text mode. Factoring in the actual screen RAM, this would mean that 240x150 text mode would consume more than 1/2 of the total memory. That just wasn't going to fly.

My preferred solution was to have 256KB or 512KB of chipram, but the FPGA I am using can't combine that much BRAM at a high enough clock speed. However, I was pleasantly surprised to find that I could make a 64KB x 8-bit memory as well as the 128KB chipram (in its 16KB x 64-bit form factor). So I implemented colour RAM that way, mapping it to $D800-$DBFF (or $DFFF when the right bit is set in the VIC-III), as well as at the C65GS extended address $FF80000-$FF8FFFF.  Colour RAM is currently 32KB because I ran out of BRAM.

All was happy until I remembered that the C65 direct maps the colour RAM at $1F800-$1FFFF, as described above.

My solution to this was to tweak the C65GS memory map, so that it also mapped at $1F800-$1FFFF, masking the 2KB of chipram there, a bit like how memory locations $0000 and $0001 are masked on the C64. In fact, like those locations on the C64, there is no way for the CPU (or DMAgic, since DMAgic on the C65GS is just the CPU in drag) to access the last 2KB of chipram on the C65GS. You would have to use some sort of reflective process to even read them, like the sprite trick that can be used to read $0000/$0001 on the C64.

This is a bit of a hack architecturally, since it means that you can't actually use those two kilobytes of chipram as real chipram now. However, that is more or less the case on a real C65, as the colour RAM cannot be relocated elsewhere. It is possible to point bitplanes there, which would produce different results on the C65GS. Maybe one day I will have to revisit this, and make some magic that copies writes to $1F800 - $1FFFF through to the colour RAM, so that it has perfect compatibility.

Coming back to the point, it turns out that the logic to write to the colour RAM image at $1F800-$1FFFF was buggy, and would return the CPU to the wrong micro-code state. I had noticed something odd in this regard previously, in that the serial monitor interface would get upset if you tried to write to colour RAM at $1F800 - $1FFFF.

Some more poking around revealed that accessing colour RAM at $FF8xxxx worked perfectly, so I adjusted the memory read/write parts of the 45GS10 CPU to translate the addresses with a cleaner abstraction layer than previously. After FPGA rebuild, the result was happiness, with all the weirdness going away.

To use this feature, you first enable 16-bit text mode / color mode, by setting bit 0 in $D054 ($D054 = $01). Two bytes are used to describe each character. The first byte is the low 8 bits of the character number, and the low nybl of the second byte are extra character number bits. The top two bits of the second byte set the width of the character as it is displayed on screen.

Second byte of screen RAM:
bits 0 - 4 = bits 8 - 12 of the character number. i.e., there can now be 8,192 characters in a character set.
bits 5 - 7 = character width (000 = standard, 111 = only the left-most pixel is drawn)
Second byte of colour RAM:
bit 7 = flip character vertically
bit 6 = flip character horizontally
    bits 3 - 5 = number of rows of pixels to trim from top of character    
bits 0 - 2 = number of rows of pixels to trim from bottom of character

NOTE: These bit assignments are likely to change!

The ability to flip characters is designed to be used with full-colour text mode, where (some or all) characters on the screen consist of 64 8-bit pixels, providing a graphics mode that can be quickly scrolled.  Flipping characters in such a mode allows 64-byte characters to be reused in a graphical display without too much obvious repetition, e.g., for in textures in games.  

Combining this with variable width characters introduces even more opportunity to reuse characters, and thus allow more interesting and complex high-resolution graphics within the limits of the 128KB of chipram.




5.0 Memory Maps
5.1 Banking Memory
                   
The $0000/$0001 CPU register only appears in bank 0, and the MAP and $D030 methods of banking take precedence over it, except for controlling the appearance of IO at $D000.
5.2 Addressing 32-bit Locations
Once I started to write software for the machine, it became immediately apparent that using DMA and memory banking are fine for accessing slabs of memory, but would be rather inconvenient for the normal use case of reading or writing some random piece of memory somewhere.
What I found was that if I had a pointer to memory and wanted to PEEK or POKE through that pointer, it was going to be a herculean task, and one that would waste many bytes of code and cycles of CPU to accomplish -- not good for a task that is the mainstay of software.
I was also reminded that the ($nn),Y operations of the 6502 are essentially pointer-dereference operations.  So I thought, why don't I just allow the pointers to grow from 16-bits to 32-bits.  Then one could just use ($nn),Y or ($nn),Z operations to act directly on distant pieces of memory.
Slight problem with this is that the 4502 has all 256 opcodes occupied, so I couldn't just assign a new one.  I would need some sort of flag to indicate what size pointers should be.  This had to be done in a way that would not break existing 6502 or 4502 code.
The experience of the 65816 led me to think that a global flag was not a good idea, because it makes it really hard to work out what is going on just by looking at a piece of code, especially where instruction lengths change.
So I decided to go for a bit of an ugly hack: If an instruction that uses the ($nn),Z addressing mode immediately follows and EOM instruction (which is what NOP is called on the 4502), then the pointer would be 32-bits instead of 16-bits.
While ugly, it seems to me that it should be safe, because no 6502 code uses ($nn),Z, because it doesn't exist. Similarly, there is so little C65 software that it is unlikely that any even uses ($nn),Z, and even less of it should have an EOM just before such an instruction.  
In fact, in the process of implementing 32-bit pointers, I discovered that ($nn),Z on the 4510 was actually doing ($nn),Y, among other bugs.  So clearly the C65 ROM mustn't have even been using the addressing mode at all!
Here is the summary of how this new addressing mode works in practise. 
32-bit Memory Addresses using 32-bit indirect zero-page indexed addressing

The ($nn),Z addressing mode is normally identical in behaviour to ($nn),Y other than that the indexing is by the Z register instead of the Y register.  That is, two bytes of zero-page memory are used to form a 16-bit pointer to the address to be accessed. However, if an instruction  using the ($nn),Z addressing mode is immediately preceded by an EOM instruction, then it uses four bytes of zero-page address to form a 32-bit address.  So for example:

zppointer: .byte $11,$22,$33,$04

lda #<zppointer
tab
ldz #$05
eom
lda (<zppointer),Z

Would load the contents of memory location $4332216 into the accumulator.

LDA, STA, EOR, AND, ORA, ADC and SBC are all available with this addressing mode.

Memory accesses made using 32-bit indirect zero-page indexed addressing require three extra cycles compared to 16-bit indirect zero-page indexed addressing: one for the EOM, and two for the extra pointer value fetches.

This makes it fairly easy to access any byte of memory in the full 28-bit address space.  The upper four bits should be zeroes for now, so that in future we can expand the C65GS to 4GB address space.

Document far-JMP, far-JSR and far-RTS
5.3 Common Locations

5.4 C64 Locations

C64 $D400-$D43F = right SID
C64 $D440-$D47F = left SID
C64 $D500-$D53F = also the left SID
C64 $D480-$D4FF = repeated images of SIDs. Don’t use these, as they may end up being extra SIDs in future, or something else completely different.

C64 $DE01.0 Enable RR-NET emulated clock port ethernet interface
C64 $DE02 RRNET register select register (low)
C64 $DE03 RRNET register select register (low)
C64 $DE06 write to even numbered RR-NET register
C64 $DE06 write to odd numbered RR-NET register
C64 $DE08 RR-NET buffer port (even byte)
C64 $DE09 RR-NET buffer port (even byte)
C64 $DE0C RRNET tx_cmd register (high)
C64 $DE0C RRNET tx_cmd register (low)
C64 $DE0E Set RR-NET TX packet size
C64 $DE0F Set RR-NET TX packet size
5.5 C65 Locations

C65 $D030.0 2nd KB of colour RAM @ $DC00-$DFFF
C65 $D030.1 VIC-III EXT SYNC (not implemented)
C65 $D030.2 Use PALETTE ROM or RAM entries for colours 0 - 15
C65 $D030.3 Map C65 ROM @ $8000
C65 $D030.4 Map C65 ROM @ $A000
C65 $D030.5 Map C65 ROM @ $C000
C65 $D030.6 Select between C64 and C65 charset.
C65 $D030.7 Map C65 ROM @ $E000
C65 $D031 VIC-III Control Register B
C65 $D031.0 VIC-III INT(erlaced?) (not implemented)
C65 $D031.1 VIC-III MONO (not implemented)
C65 $D031.2 VIC-III H1280 (1280 horizontal pixels)
C65 $D031.3 VIC-III V400 (400 vertical pixels)
C65 $D031.4 VIC-III Bit-Plane Mode (not implemented)
C65 $D031.5 VIC-III Enable extended attributes and 8 bit colour entries
C65 $D031.6 C65 FAST mode (~3.5MHz)
C65 $D031.7 VIC-III H640 (640 horizontal pixels)

C65 $D080 - F011 FDC control
C65 $D081 - F011 FDC command
C65 $D082 - F011 FDC Status A port (read only)
C65 $D083 - F011 FDC Status B port (read only)
C65 $D084 - F011 FDC track
C65 $D085 - F011 FDC data register
C65 $D085 - F011 FDC sector
C65 $D086 - F011 FDC side
C65 $D100-$D1FF red palette values (reversed nybl order)
C65 $D200-$D2FF green palette values (reversed nybl order)
C65 $D300-$D3FF blue palette values (reversed nybl order)

5.6 GS Locations
                   
$0000000        6510/45GS10 CPU port DDR
$0000001        6510/45GS10 CPU port data
$0400-            Screen RAM
$8000-$BFFF        Hypervisor
$D000-$D01F        VIC-II compatibility (same as C64)
$D020            Border color (all 8 bits when C65 extended attributes are enabled)
$D021            Background color (all 8 bits when C65 extended attributes are enabled)
$D022            VIC multicolor 1 (all 8 bits when C65 extended attributes are enabled)
$D023            VIC multicolor 2 (all 8 bits when C65 extended attributes are enabled)
$D024            VIC multicolor 3 (all 8 bits when C65 extended attributes are enabled)
$D025-$D02E        VIC-II compatibility (same as C64)
$D02F            GS: write $47 then $53 to enable C65GS/VIC-IV registers.
            C65: write $A5 then $96 to enable C65/VIC-III registers.
            C65: write anything else to return to VIC-II map.
$D030            C65: VIC-III control register A


GS $D040 VIC-IV characters per logical text row (LSB)
GS $D041 VIC-IV characters per logical text row (MSB)
GS $D042 VIC-IV horizontal hardware scale setting
GS $D043 VIC-IV vertical hardware scale setting
GS $D044 VIC-IV left bordS $D045 VIC-IV left border position (MSB)
GS $D046 VIC-IV right border position (LSB)
GS $D047 VIC-IV right border position (MSB)
GS $D048 VIC-IV top border position (LSB)
GS $D049 VIC-IV top border position (MSB)
GS $D04A VIC-IV bottom border position (LSB)
GS $D04B VIC-IV bottom border position (MSB)
GS $D04C VIC-IV character generator horizontal position (LSB)
GS $D04D VIC-IV character generator horizontal position (MSB)
GS $D04E VIC-IV character generator vertical position (LSB)
GS $D04F VIC-IV character generator vertical position (MSB)
GS $D050 VIC-IV read horizontal position (LSB)
GS $D051 VIC-IV read horizontal position (MSB)
GS $D052 VIC-IV read physical raster/set raster compare (LSB)
GS $D053 VIC-IV read physical raster/set raster compare (MSB)
GS $D054 VIC-IV Control register C
GS $D054.0 VIC-IV enable 16-bit character numbers (two screen bytes per character)
GS $D054.1 VIC-IV enable full-colour mode for character numbers <=$FF
GS $D054.2 VIC-IV enable full-colour mode for characF
GS $D054.3 VIC-IV video output smear filter enable
GS $D054.6 VIC-IV/C65GS FAST mode (48MHz)
GS $D060 VIC-IV screen RAM precise base address (bits 0 - 7)
GS $D061 VIC-IV screen RAM precise base address (bits 15 - 8)
GS $D062 VIC-IV screen RAM precise base address (bits 23 - 16)
GS $D063 VIC-IV screen RAM precise base address (bits 31 - 24)
GS $D064 VIC-IV colour RAM base address (bits 0 - 7)
GS $D065 VIC-IV colour RAM base address (bits 15 - 8)
GS $D068 VIC-IV character set precise base address (bits 0 - 7)
GS $D069 VIC-IV character set precise base address (bits 15 - 8)
GS $D06A VIC-IV character set precise base address (bits 23 - 16)
GS $D06B VIC-IV character set precise base address (bits 31 - 24)
GS $D06C VIC-IV sprite pointer address (bits 7 - 0)
GS $D06D VIC-IV sprite pointer address (bits 15 - 8)
GS $D06E VIC-IV sprite pointer address (bits 23 - 16)
GS $D06F VIC-IV sprite pointer address (bits 31 - 24)
GS $D070 VIC-IV palette bank selection
GS $D070.3-2 VIC-IV sprite palette bank
GS $D070.5-4 VIC-IV bitmap/text palette bank
GS $D070.7-6 VIC-IV palette bank mapped at $D100-$D3FF
GS $D07C VIC-IV debug X position (LSB)
GS $D07D VIC-IV debug X position (MSB)
GS $D07E VIC-IV debug Y position (LSB)
GS $D07F VIC-IV debug X position (MSB)
GS $D500-$D53F - 8x 64bit FPU input registers
GS $D540-$D5BF - 16x 64bit FPU intermediate/output registers (read only)
GS $D5C0 - FPU SIN/COS input register
GS $D5C1 - FPU SIN/COS output register
GS $D640 - Hypervisor A register storage
GS $D641 - Hypervisor X register storage
GS $D642 - Hypervisor Y register storage
GS $D643 - Hypervisor Z register storage
GS $D644 - Hypervisor B register storage
GS $D645 - Hypervisor SPL register storage
GS $D646 - Hypervisor SPH register storage
GS $D647 - Hypervisor P register storage
GS $D648 - Hypervisor PC-low register storage
GS $D649 - Hypervisor PC-high register storage
GS $D64A - Hypervisor MAPLO register storage (high bits)
GS $D64B - Hypervisor MAPLO register storage (low bits)
GS $D64C - Hypervisor MAPHI register storage (high bits)
GS $D64D - Hypervisor MAPHI register storage (low bits)
GS $D64E - Hypervisor MAPLO mega-byte number register storage
GS $D64F - Hypervisor MAPHI mega-byte number register storage
GS $D650 - Hypervisor CPU port $00 value
GS $D651 - Hypervisor CPU port $01 value
GS $D652 - Hypervisor VIC-IV IO mode
GS $D653 - Hypervisor DMAgic source MB
GS $D654 - Hypervisor DMAgic destination MB
GS $D655 - Hypervisor DMAGic list address bits 0-7
GS $D656 - Hypervisor DMAGic list address bits 15-8
GS $D657 - Hypervisor DMAGic list address bits 23-16
GS $D658 - Hypervisor DMAGic list address bits 27-24
GS $D67F - Trigger trap to hypervisor
GS $D680 - SD controller status/command
GS $D681-$D684 - SD controller SD sector address
GS $D68B - F011 emulation control register
GS $D68B.0 - F011 disk 1 disk image enable
GS $D68B.1 - F011 disk 1 present
GS $D68B.2 - F011 disk 1 write protect
GS $D68B.3 - F011 disk 2 disk image enable
GS $D68B.4 - F011 disk 2 present
GS $D68B.5 - F011 disk 2 write protect
GS $D68C-$D68F - F011 disk 1 disk image address on SD card
GS $D690-$D693 - F011 disk 2 disk image address on SD card
GS $D6E0 Ethernet control
GS $D6E0.0 Clear to reset ethernet PHY
GS $D6E0.1-2 Read ethernet TX bits currently on the wire
GS $D6E0.3 Read ethernet RX data valid
GS $D6E0.4 Allow remote keyboard input via magic ethernet frames
GS $D6E1 - Ethernrupt and control register
GS $D6E1.0 reset ethernet PHY
GS $D6E1.1 - Set which RX buffer is memory mapped
GS $D6E1.2 - Indicate which RX buffer was most recently used
GS $D6E1.3 Enable real-time video streaming via ethernet
GS $D6E1.4 - Ethernet TX IRQ status
GS $D6E1.5 - Ethernet RX IRQ status
GS $D6E1.6 - Enable ethernet TX IRQ
GS $D6E1.7 - Enable ethernet RX IRQ
GS $D6E2 - TX Packet size (low byte)
GS $D6E2 Set low-order size of frame to TX
GS $D6E3 - TX Packet size (high byte)
GS $D6E3 Set high-order size of frame to TX
GS $D6E4 = $00 = Clear ethernet TX trigger (debug)
GS $D6E4 = $01 = Transmit packet
GS $D6E4 Ethernet command
GS $D6F3 - Accelerometer bit-bashing port
GS $D6F5 - Temperature sensor bit-bashing port
GS $D6F6 - Keyboard scan code reader (lower byte)
GS $D6F7 - Keyboard scan code reader (upper nybl)
GS $D6F7 - microphone input (right)
GS $D6F8 - 8-bit digital audio out (left)
GS $D6F9.0 - Enable audio amplifier
GS $D6FA - 8-bit digital audio out (left)
GS $D6FB - microphone input (left)
GS $D6FF - Flash bit-bashing port
GS $D710-$D7FF - Enhanced sprite control registers (16 per enhanced sprite)
GS $D718-$D7FF - Enhanced sprite linear transform matricies. These allow for hardware rotation, flipping etc.
GS $D7x0-$D7x1 - Enhanced sprite X position in physical pixels (lower 12 bits)
GS $D7x1.4-7 - Enhanced sprite width (4 -- 64 pixels)
GS $D7x2-$D7x3 - Enhanced sprite Y position in physical pixels (16 bits)
GS $D7x3.4-7 - Enhanced sprite height (4 -- 64 pixels)
GS $D7x4 - Enhanced sprite data offset in its 4KB SpriteRAM (x16 bytes)
GS $D7x5 - Enhanced sprite foreground mask
GS $D7x6 - Enhanced sprite colour AND mask (sprite not visible if result = $00)
GS $D7x7 - Enhanced sprite colour OR mask
GS $D7x8-$D7x9 - Enhanced sprite 2x2 linear transform matrix 0,0 (5.11 bits)
GS $D7xA-$D7xB - Enhanced sprite 2x2 linear transform matrix 0,1 (5.11 bits)
GS $D7xC-$D7xD - Enhanced sprite 2x2 linear transform matrix 1,0 (5.11 bits)
GS $D7xE-$D7xF - Enhanced sprite 2x2 inear transform matrix 1,1 (5.11 bits)
GS $FF9x000-$FF9xFFF - Enhanced sprite data buffers (4KB each)
GS $FFC00A0 45GS10 slowram wait-states (write-only)
GS $FFDE800 - $FFDEFFF Ethernet RX buffer (read only)
GS $FFDE800 - $FFDEFFF Ethernet TX buffer (write only)
GS RR-NET emulation: cs_packet_data high
GS RR-NET emulation: cs_packet_data low




$D800    -$DFFF        IO-mapped color memory
$DE041            bit 7 = enable IRQ on frame RX
                bit 6 = enable IRQ on completion of frame TX
                bit 5 = a frame has been received since $DE041 was written
                bit 4 = a frame has been sent since $DE041 was written
                bit 3 = ?
                bit 2 = which RX buffer was last written to by the ethernet adaptor
                bit 1 = which RX buffer is mapped at $DE800-$DEFFF for reading.
                ** To clear any IRQs write anything to $DE041
$FFDE000-$FFDE7FF    Ethernet RX buffer read-only.
$FFDE800-$FFDEFFF    Ethernet TX buffer write-only. 2k received frame buffer. Bytes 0, 1 are the frame length.
                If bit 15 is high, then the frame failed CRC.
$FFDE043-4            Ethernet TX frame length
$FFDE045            Ethernet command register. Write $01 to send frame.





6.0 Code Recipes
6.1 Overview
6.2 The MAP Opcode
The 4502 MAP instruction works on 8KB pieces.  It relies on the Accumulator (A)’s upper four bits as flags to indicate whether mapping is done at $0000, $2000, $4000, or $6000.  The lower four bits form bits 8 thru 11 of the mapping offset.  Meanwhile, the X register has bits 12 thru 19.

A good MAP example is when using the Ethernet controller’s read buffer.  This lives at $FFDE800-$FFDEFFF.  We will map it to $6800-$6FFF.  Since the 4502 MAP instruction works on 8KB pieces, we will actually map $6000-$7FFF to $FFDE000-$FFDFFFF.  Since this is above $00FFFFF, we need to set the C65GS-specific 45GS02 mega-byte number to $FF, i.e., to indicate the memory range $FF00000-$FFFFFFF, for the memory mapper before mapping the memory.  We only need to do this for the bottom-half of memory, so we will leave Y and Z zeroed out so that we don't change that one.

lda #$ff
ldx #$0f
ldy #$00
ldz #$00
map
eom

Now looking at the $DE800 address within the mega-byte, we use the normal 4502/C65 MAP instruction semantic.  The Accumulator (A) contains four bits to select whether mapping happens at $0000, $2000, $4000 and/or $6000. We want to map only at $6000, so we only set bit 7. The bottom four bits of A are bits 8 to 11 of the mapping offset, which in this case is zero.  X has bits 12 to 19, which needs to be $D8, so that the offset all together is $D8000.  We use this value, and not $DE000, because it is an offset, and $D8000 + $6000 = $DE000, our target address.  It's all a bit weird until you get used to it.
6.3 Character Mode          
$F4 is the C65 BASIC/KERNEL reverse flag, distinct from the VIC-III/IV reverse glyph flag. Setting and clearing reverse character mode is done by setting bit 7 in $F4. On the C64 or C128 this would require an LDA / ORA / STA or LDA / AND / STA instruction sequence, requiring six bytes and a dozen or so cycles.

The C65's 4510 on the other hand has instructions for setting and clearing bits in bytes directly. SMB0 through SMB7 set the corresponding bit in a zero-page memory location, and RMB0 through RMB7 clear the bit. As a result the C65's reverse-on routine is simply SMB7 $F4 followed by an RTS. Three bytes instead of six, and just four cycles for the memory modification, and no registers or flags modified in the process. Those new instructions really do help to write faster and more compact bit-fiddling code.
6.4 Clear the Raster IRQ
INC $D019
6.5 Clearing bits in a byte         
LDA #01
TRB $D030
...clears out bit 0 in $D030, which on a C65 will bank out the second kilobyte of color RAM from $DC00 thru $DFFF so you can see the CIAs again.
6.6 32-bit Memory Addresses using 32-bit indirect zero-page indexed addressing
The ($nn),Z addressing mode is normally identical in behaviour to ($nn),Y other than that the indexing is by the Z register instead of the Y register.  That is, two bytes of zero-page memory are used to form a 16-bit pointer to the address to be accessed. However, if an instruction using the ($nn),Z addressing mode is immediately preceded by an EOM instruction, then it uses four bytes of zero-page address to form a 32-bit address.  So for example:

zppointer:    .byte $11,$22,$33,$04

        lda #>zppointer
tab
        ldz #$05
        eom
        lda (<zppointer),Z
        

Would load the contents of $4332216 into the accumulator.

LDA, STA, EOR, AND, ORA, ADC and SBC are all available with this addressing mode.

Memory accesses made using 32-bit indirect zero-page indexed addressing require three extra cycles compared to 16-bit indirect zero-page indexed addressing: one for the EOM, and two for the extra pointer value fetches.

This makes it fairly easy to access any byte of memory in the full 28-bit address space.  The upper four bits should be zeroes for now, so that in future we can expand the C65GS to 4GB address space.
6.7 Sending an Ethernet Frame     
To send a frame, you write the bytes to $FFDE800 - $FFDEFFF, write the frame length to $DE043/$DE044, and then write $01 to $DE045. $D6Ex provides access to some of these registers so that ethernet operations can be more easily performed without having to bank things.
Note that the TX buffer is mapped to the same address range as the RX buffer. In other words, the TX buffer is write-only, while the RX buffers are read-only. When you transmit a frame, the ethernet adapter automatically calculates and appends the ethernet CRC to the end of the frame.

6.8 Loading Data Via Ethernet              
Note: The ethernet controller will not load a packet to the buffer that the CPU is watching, so the CPU needs to make sure that it is not watching the buffer that the ethernet controller wants to write to next. It is just a few lines of code to do this.
Because the C65GS ethernet buffer is direct memory mapped, I can use a nice trick, of having the main loading routine actually inside the packets. This means that the ethernet load programme on the C65GS can be <128 bytes, and yet support very flexible features, since the sending side can send whatever code it likes. It is only about 100 lines of 4502 assembler, so I'll just include the whole thing here.


.org $CF80
First, we need to turn on C65GS enhanced IO so that we can access the ethernet controller:
lda #$47
sta $d02f
lda #$53
sta $D02f
Then we need to map the ethernet controller's read buffer.  This lives at $FFDE800-$FFDEFFF.  We will map it at $6800-$6FFF.  The 4502 MAP instruction works on 8KB pieces, so we will actually map $6000-$7FFF to $FFDE000-$FFDFFFF.  Since this is above $00FFFFF, we need to set the C65GS mega-byte number to $FF for the memory mapper before mapping the memory.  We only need to do this for the bottom-half of memory, so we will leave Y and Z zeroed out so that we don't change that one.
lda #$ff
ldx #$0f
ldy #$00
ldz #$00
map
eom
Now looking at the $DE800 address within the mega-byte, we use the normal 4502/C65 MAP instruction semantic.  A contains four bits to select whether mapping happens at $0000, $2000, $4000 and/or $6000. We want to map only at $6000, so we only set bit 7.  The bottom four bits of A are bits 8 to 11 of the mapping offset, which in this case is zero.  X has bits 12 to 19, which needs to be $D8, so that the offset all together is $D8000.  We use this value, and not $DE000, because it is an offset, and $D8000 + $6000 = $DE000, our target address.  It's all a bit weird until you get used to it.
lda #$80
ldx #$8d
ldy #$00
ldz #$00
map
eom
Now we are ready to make sure that the ethernet controller is running:
lda #$01
sta $d6e1
Finally we get to the interesting part, where we loop waiting for packets.  Basically we wait until the packet RX flag is set
loop:

waitingforpacket:
lda $d6e1
and #$20
beq waitingforpacket
So a packet has arrived.  Bit 2 has the buffer number that the packet was read into (0 or 1), and so we shift that down to bit 1, which selects which buffer is currently visible.  Then we write this to $D6E1, which also has the effect of clearing the ethernet IRQ if it is pending.
lda $d6e1
and #$04
lsr
ora #$01
sta $d6e1
Now we check that it is an IPv4 UDP packet addressed to port 4510
; is it IPv4?
lda $6810
cmp #$45
bne waitingforpacket
; is it UDP?
lda $6819
cmp #$11
bne waitingforpacket
; UDP port #4510
lda $6826
cmp #>4510
bne waitingforpacket
lda $6827
cmp #<4510
bne waitingforpacket
If it is, we give some visual indication that stuff is happening. I'll take this out once I have the whole thing debugged, because it wastes a lot of time to copy 512 bytes this way, since I am not even using the DMAgic to do it efficiently.  In fact, this takes more time than actually loading a 1KB packet of data.
; write ethernet status to $0427
lda $d6e1
sta $0427

; Let's copy 512 bytes of packet to the screen repeatedly
ldx #$00
loop1: lda $6800,x
sta $0428,x
lda $6900,x
sta $0528,x
inx
bne loop1
The final check we do on the packet is to see that the first data byte is $A9 for LDA immediate mode.  If so, we assume it is a packet that contains code we can run, and we then JSR to it:
lda $682c
cmp #$a9
bne loop
jsr $682C
Then we just go looking for the next packet:
jmp loop

As you can see, the whole program is really simple, especially once it hits the loop.  This is really due to the hardware design, which with the combination of DMA and memory mapping avoids insane fiddling to move data around, particularly the ability to execute an ethernet frame as code while it sits in the buffer.

The code in the ethernet frame just executes a DMAgic job to copy the payload into the correct memory location.  Thus the complete processing of a 1024 byte ethernet frame takes somewhere between 2,048 and 4,096 clock cycles -- fast enough that the routine can load at least 12MB/sec, i.e., match the wire speed of 100mbit ethernet.

On the server side, I wrote a little server program that sends out the UDP packets as it reads through a .PRG file.  Due to a bug in the ethernet controller buffer selection on the C65GS it currently has to send every packet twice, effectively halving the maximum speed to a little under 6MB/sec.  That bug should be easy to fix, allowing the load speed to be restored to ~10MB/sec.  (Note that at the moment the protocol is completely unidirectional, but that this could be changed by sending packets that download code that is able to send packets.)

When the server reaches the end of the file, the server sends a packet with a little routine that pops the return address from the JSR to the packet from the stack, and then returns, thus effectively returning to BASIC -- although it does seem to mess up sometimes, which I need to look int
7.0 Differences Between the C65’s 4502 and C65GS’s GS4510
7.1 Overview
7.2 Emulated NMOS Read-Modify-Write Behaviour for C64 Compatibility
One of the greatest incompatibilities between the C65 and the C64 was the move to the CMOS 4502 processor, which lacked the dummy write in read-modify-write (RMW) instructions. The RMW instructions are those that both read and write a memory location, and include INCrement, DECrement, Arithmetic Shift Left and several others.  

On the NMOS 6502, which is the heart of the C64’s 6510, these instructions read the target memory location, write the original value that was in that location back, and then write back the updated value.  So, for example, INC $D019, where $D019 contains $81 would do the following three memory accesses:
    #1 - read $81 from $D019
    #2 - write $81 back to $D019, while calculating that $81 + $01 = $82
    #3 - write $82 back to $D019
On the CMOS 6502 and derivatives, memory access #2 doesn’t happen, instead it is just:
    #1 - read $81 from $D019, and calculate $81 + $01 = $82
    #2 - write $82 to $D019
This is normally a good thing, because the faster internal logic of the CMOS implementation allows that extra cycle to be avoided, and so INC on a CMOS 6502, like the 4502 or 65816, is one cycle faster than on the C64’s NMOS 6502.

However, there is a lot of software for the C64 that assumes that the dummy write occurs, even if the people writing the software didn’t realise that this was the case.  This is because INC $D019, DEC $D019, ASL $D019, LSR $D019 or some other RMW instruction is commonly used to clear VIC-II raster interrupts.  This works because to clear an interrupt on the VIC-II you need to write back the bits that are set in $D019.  

As in the example above, when a raster interrupt occurs, $D019 will contain $81.  Writing $81 back, as happens in the extra memory access of the NMOS 6502 accomplishes this -- the final writing of $82 to $D019, which is what the instruction is supposed to do, has absolutely no effect!

On the CMOS 6502, only the intentional write of $82 to $D019 occurs, which doesn’t clear the raster interrupt flag.  The accidental effect of the extra write cycle on the NMOS 6502 is missing, and so the raster interrupt never gets cleared, and the software doesn’t work correctly.

Thus for C64 compatibility the dummy write must be present.  However, for maximum performance it should be avoided.  The GS4510 achieves both, by including the extra write ONLY if the target address is $D019, thus incurring the one cycle penalty only when it is required, and avoiding it completely otherwise.

7.3 Flat Memory Map Addressing Modes & Access
TODO: PGS plans to add 32-bit indirect indexed modes, so that ($nn),Z addressing mode works on a 32-bit pointer instead of a 16-bit pointer, but ONLY when the ($nn),Z mode instruction immediately follows and EOM (opcode $EA = NOP on 6502).  This will allow easy access to full 28-bit address space. Expect instruction to take 3 cycles longer than a normal ($nn),Y or ($nn),Z (one for the EOM preceeding it, and two extra cycles for reading the extra pointer bytes.  Combined with TAB/TBA, this allows any piece of RAM to be used as a 32-bit pointer.

(These will allow faster more convenient random memory access than using DMAgic, which is more efficient for block transfers.)

The above is now implemented for ($nn),Z only.

TODO: PGS plans to add 32-bit absolute addressing modes to JMP and JSR to make JMPF and JSRF, and a matching RTSF (Return from Far Subroutine).  These will work by mapping $4000-$7FFF to the relevant 16KB block of RAM, and then setting PC to $4000 + (address & $3FFF).  The current CPU map and PC will be pushed to the stack (8 bytes total).  RTSF will pop the CPU memory map and PC from the stack.  

(The “Far” instructions will probably be implemented internally as CLD+CLD+JMP, CLD+CLD+JSR, CLD+CLD+RTS, since all opcodes are currently allocated.  These Decimal mode fiddles were chosen as being highly unlikely constructions with no legitimate function.  This means that the far operations will require two extra cycles for the decimal fiddle, plus the two extra cycles for popping the CPU map state off the stack.)

The above is now mostly implemented, including virtual memory support, which has also reduced the length of the return address on the stack to just 4 bytes.

These changes allow programs to be arbitrarily large, with the only caveat that each routine much be not longer than 16KB in length.





8. 4502 Opcodes
                   
TODO: Double check the new opcodes with 64NET.OPC on github, as I have a vague recollection that one or more opcodes have been moved or renamed.
Overview
The 4502, upon reset, looks and acts like any other CMOS 6502 processor, with the exception that many instructions are shorter or require less cycles than they used to. This causes programs to execute in less time that older versions, even at the same clock frequency.

The stack pointer has been expanded to 16 bits, but can be used in two different modes. It can be used as a full 16-bit (word) stack pointer, or as an 8-bit (byte) pointer whose stack page is programmable. On reset, the byte mode is selected with page 1 set as the stack page. This is done to make it fully 65C02 compatible.

The zero page is also programmable via a new register, the "B" or "Base Page" register. On reset, this register is cleared, thus giving a true "zero" page for compatability reasons, but the user can define any page in memory as the "zero" page.

A third index register, "Z", has been added to increase flexibility in data manipulation. This register is also cleared, on reset, so that the STZ instructions still do what they used to, for compatibility.

This is a list of opcodes that have been added to the 210 previously defined MOS, Rockwell, and GTE opcodes.
Branches and Jumps
93 BCC label word-relative
B3 BCS label word-relative
F3 BEQ label word-relative
33 BMI label word-relative
D3 BNE label word-relative
13 BPL label word-relative
83 BRA label word-relative
53 BVC label word-relative
73 BVS label word-relative

63 BSR label Branch to subroutine (word relative)
22 JSR (ABS) Jump to subroutine absolute indirect
23 JSR (ABS,X) Jump to subroutine absolute indirect, X
62 RTN # Return from subroutine and adjust stack pointer

Arithmetic Operations
42 NEG A Negate (or 2's complement) accumulator

43 ASR A Arithmetic Shift right accumulator or memory
44 ASR ZP
54 ASR ZP,X

E3 INW ZP Increment Word
C3 DEW ZP Decrement Word

1B INZ Increment and
3B DEZ Decrement Z register

CB ASW ABS Arithmetic Shift Left Word
EB ROW ABS Rotate Left Word

ORA (ZP),Z These were formerly (ZP) non-indexed
AND (ZP),Z now are indexed by Z register
EOR (ZP),Z (when .Z=0, operation is the same)

ADC (ZP),Z
CMP (ZP),Z
SBC (ZP),Z

C2 CPZ IMM Compare Z register with memory immediate,
D4 CP2 ZP zero page, and
DC CPZ ABS absolute.
Loads, Stores, Pushes, Pulls and Transfers    
LDA (ZP),Z formerly (ZP)

A3 LDZ IMM Load Z register immediate,
AB LDZ ABS absolute,
BB LDZ ABS,X absolute,X.

E2 LDA (d,SP),Y Load Accu via stack vector indexed by Y
82 STA (d,SP),Y and Store

9B STX ABS,Y Store X Absolute,Y
8B STY ABS,X Store Y Absolute,X

STZ ZP Store Z register (formerly store zero)
STZ ABS
STZ ZP,X
STZ ABS,X

STA (ZP),Z formerly (ZP)

F4 PHD IMM Push Data Immediate (word)
FC PHD ABS Push Data Absolute (word)

DB PHZ Push Z register onto stack
FB PLZ Pull Z register from stack

4B TAZ Transfer Accumulator to Z register
6B TZA Transfer Z register to Accumulator

5B TAB Transfer Accumulator to Base page register
7B TBA Transfer Base page register to Accumulator

0B TSY Transfer Stack Pointer High byte to Y register
and set "byte" stack-pointer mode

***KEN*** According to the detailed info below, the TSY instruction does not change the state of the E bit, which controls the 16 bit stack mode.

2B TYS Transfer Y register to Stack Pointer High byte
and set "word" stack-pointer mode

***KEN*** According to the detailed info below, the TYS instruction does not change the state of the E bit, which controls the 16 bit stack mode.

***KEN*** I've added the following three entries as summaries of the CLE, SEE, and MAP instructions

02 CLE Clear the Extend Disable bit in the P register. In other
words, set the stack pointer to 16 bit mode.
03 SEE Set the Extend Disable bit in the P register. In other
words, set the staack pointer to 8 bit mode.

5C MAP Enter MAP mode, and start setting up a memory mapping.
Exit MAP mode by executing a NOP, opcode EA.




4502 Opcode Table
  0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BRK |ORA |CLE*|SEE*|TSB |ORA |ASL |RMB0|PHP |ORA |ASL |TSY*|TSB |ORA |ASL |BBR0|
|    |INDX|    |    |ZP  |ZP  |ZP  |ZP  |    |IMM |    |    |ABS |ABS |ABS |ZP  | 0
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BPL |ORA |ORA |BPL*|TRB |ORA |ASL |RMB1|CLC |ORA |INC |INZ*|TRB |ORA |ASL |BBR1|
|REL |INDY|INDZ|WREL|ZP  |ZPX |ZPX |ZP  |    |ABSY|    |    |ABS |ABSX|ABSX|ZP  | 1
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|JSR |AND |JSR*|JSR*|BIT |AND |ROL |RMB2|PLP |AND |ROL |TYS*|BIT |AND |ROL |BBR2|
|ABS |INDX|IND |INDX|ZP  |ZP  |ZP  |ZP  |    |IMM |    |    |ABS |ABS |ABS |ZP  | 2
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BMI |AND |AND |BMI*|BIT |AND |ROL |RMB3|SEC |AND |DEC |DEZ*|BIT |AND |ROL |BBR3|
|REL |INDY|INDZ|WREL|ZPX |ZPX |ZPX |ZP  |    |ABSY|    |    |ABSX|ABSX|ABSX|ZP  | 3
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|RTI |EOR |NEG*|ASR*|ASR*|EOR |LSR |RMB4|PHA |EOR |LSR |TAZ*|JMP |EOR |LSR |BBR4|
|    |INDX|    |    |ZP  |ZP  |ZP  |ZP  |    |IMM |    |    |ABS |ABS |ABS |ZP  | 4
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BVC |EOR |EOR |BVC*|ASR*|EOR |LSR |RMB5|CLI |EOR |PHY |TAB*|MAP*|EOR |LSR |BBR5|
|REL |INDY|INDZ|WREL|ZPX |ZPX |ZPX |ZP  |    |ABSY|    |    |    |ABSX|ABSX|ZP  | 5
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|RTS |ADC |RTN*|BSR*|STZ |ADC |ROR |RMB6|PLA |ADC |ROR |TZA*|JMP |ADC |ROR |BBR6|
|    |INDX|    |WREL|ZP  |ZP  |ZP  |ZP  |    |IMM |    |    |IND |ABS |ABS |ZP  | 6
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BVS |ADC |ADC |BVS*|STZ |ADC |ROR |RMB7|SEI |ADC |PLY |TBA*|JMP |ADC |ROR |BBR7|
|REL |INDY|INDZ|WREL|ZPX |ZPX |ZPX |ZP  |    |ABSY     |    |INDX|ABSX|ABSX|ZP  | 7
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BRU |STA |STA*|BRU*|STY |STA |STX |SMB0|DEY |BIT |TXA |STY*|STY |STA |STX |BBS0|
|REL |INDX|IDSP|WREL|ZP  |ZP  |ZP  |ZP  |    |IMM |    |ABSX|ABS |ABS |ABS |ZP | 8
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BCC |STA |STA |BCC*|STY |STA |STX |SMB1|TYA |STA |TXS |STX*|STZ |STA |STZ |BBS1|
|REL |INDY|INDZ|WREL|ZPX |ZPX |ZPY |ZP  |    |ABSY|    |ABSY|ABS |ABSX|ABSX|ZP  | 9
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|LDY |LDA |LDX |LDZ*|LDY |LDA |LDX |SMB2|TAY |LDA |TAX |LDZ*|LDY |LDA |LDX |BBS2|
|IMM |INDX|IMM |IMM |ZP  |ZP  |ZP  |ZP  |    |IMM |    |ABS |ABS |ABS |ABS |ZP  | A
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BCS |LDA |LDA |BCS*|LDY |LDA |LDX |SMB3|CLV |LDA |TSX |LDZ*|LDY |LDA |LDX |BBS3|
|REL |INDY|INDZ|WREL|ZPX |ZPX |ZPY |ZP  |    |ABSY|    |ABSX|ABSX|ABSX|ABSY|ZP  | B
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|CPY |CMP |CPZ*|DEW*|CPY |CMP |DEC |SMB4|INY |CMP |DEX |ASW*|CPY |CMP |DEC |BBS4|
|IMM |INDX|IMM |ZP  |ZP  |ZP  |ZP  |ZP  |    |IMM |    | ABS|ABS |ABS |ABS |ZP  | C
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BNE |CMP |CMP |BNE*|CPZ*|CMP |DEC |SMB5|CLD |CMP |PHX |PHZ*|CPZ*|CMP |DEC |BBS5|
|REL |INDY|INDZ|WREL|ZP  |ZPX |ZPX |ZP  |    |ABSY|    |    |ABS |ABSX|ABSX|ZP  | D
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|CPX |SBC |LDA*|INW*|CPX |SBC |INC |SMB6|INX |SBC |EOM |ROW*|CPX |SBC |INC |BBS6|
|IMM |INDX|IDSP|ZP  |ZP  |ZP  |ZP  |ZP  |    |IMM |NOP |ABS |ABS |ABS |ABS |ZP  | E
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
|BEQ |SBC |SBC |BEQ*|PHD*|SBC |INC |SMB7|SED |SBC |PLX |PLZ*|PHD*|SBC |INC |BBS7|
|REL |INDY|INDZ|WREL|IMM |ZPX |ZPX |ZP  |    |ABSY|    |    |ABS |ABSX ABSX|ZP  | F
+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+

9. 4502 Registers

Overview
The 4502 has the following 8 user registers:

A accumulator
X index-X
Y index-Y
Z index-Z

B Base-page
P Processor status
SP Stack pointer
PC Program counter
            
Accumulator
The accumulator is the only general purpose computational register. It can be used for arithmetic functions add, subtract, shift, rotate, negate, and for Boolean functions and, or, exclusive-or, and bit operations. It cannot, however, be used as an index register.

Index X
The index register X has the largest number of opcodes pertaining to, or using it. It can be incremented, decremented, or compared, but not used for arithmetic or logical (Boolean) operations. It differs from other index registers in that it is the only register that can be used in indexed-indirect or (bp,X) operations. It cannot be used in indirect-indexed or (bp),Y mode.
        
Index Y        
The index register Y has the same computational constraints as the X register, but finds itself in a lot less of the opcodes, making it less generally used. But the index Y has one advantage over index X, in that it can be used in indirect-indexed operations or (bp),Y mode.

Index Z        
The index register Z is the most unique, in that it is used in the smallest number of opcodes. It also has the same computation limitations as the X and Y registers, but has an extra feature. Upon reset, the Z register is cleared so that the STZ (store zero) opcodes and non-indexed indirect opcodes from previous 65C02 designs are emulated. The Z register can also be used in indirect-indexed or (bp),Z operations.

Base page B register
Early versions of 6502 microprocessors had a special subset of instructions that required less code and less time to execute. These were referred to as the "zero page" instructions. Since the addressing page was always known, and known to be zero, addresses could be specified as a single byte, instead of two bytes.

The CSG 4502 also implements this same "zero page" set of instructions, but goes one step further by allowing the programmer to specify which page is to be the "zero page". Now that the programmer can program this page, it is now, not necessarily page zero, but instead, the "selected page". The term "base page" is used, however.

The B register selects which page will be the "base page", and the user sets it by transferring the contents of the accumulator to it. At reset, the B register is cleared, giving initially a true "zero page".

Processor status P register
The processor status register is an 8-bit register which is used to indicate the status of the microprocessor. It contains 8 processor "flags". Some of the flags are set or reset based on the results of various types of operations. Others are more specific. The flags are...
Flag Name Typical indication

N Negative result of operation is negative
V Overflow result of add or subtract causes signed overflow
E Extend disables stack pointer extension
B Break interrupt was caused by BRK opcode
D Decimal perform add/subtract using BCD math
I Interrupt disable IRQ interrupts
Z Zero result of Operation is zero
C Carry operation caused a carry

Stack Pointer SP
The stack pointer is a 16 bit register that has two modes. It can be programmed to be either an 8-bit page programmable pointer, or a full 16-bit pointer. The processor status E bit selects which mode will be used. When set, the E bit selects the 8-bit mode. When reset, the E bit selects the 16-bit mode.

Upon reset, the CSG 4502 will come up in the 8-bit page- programmable mode, with the stack page set to 1. This makes it compatible with earlier 6502 products. The programmer can quickly change the default stack page by loading the Y register with the desired page and transferring its contents to the stack pointer high byte, using the TYS opcode. The 8-bit stack pointer can be set by loading the X register with the desired value, and transferring its contents to the stack pointer low byte, using the TXS opcode.

To select the 16-bit stack pointer mode, the user must execute a CLE (for CLear Extend disable) opcode. Setting the 16-bit pointer is done by loading the X and Y registers with the desired stack pointer low and high bytes, respectively, and then transferring their contents to the stack pointer using TXS and TYS. To return to 8-bit page mode, simple execute a SEE (SEt Extend disable) opcode.

*************************************************************
* WARNING *
* 
* If you are using Non-Maskable-Interrupts, or Interrupt *
* Request is enabled, and you want to change BOTH stack *
* pointer bytes, do not put any code between the TXS and *
* TYS opcodes. Taking this precaution will prevent any *
* interrupts from occuring between the setting of the two *
* stack pointer bytes, causing a potential for writing *
* stack data to an unwanted area. *
*************************************************************

Program Counter PC
The program counter is a 16-bit up-only counter that determines what area of memory that program information will be fetched from. The user generally only modifies it using jumps, branches, subroutine calls, or returns. It is set initially, and by interrupts, from vectors at memory addresses $FFFA through $FFFF (hex). See "Interrupts" below.


10. 65CE02 Interrupts
Overview
There are four basic interrupt sources on the CSG 4502. These are RES*, IRQ*, NMI*, and SO, for Reset, Interrupt Request, Non-Maskable Interrupt, and Set Overflow. The Reset is a hard non-recoverable interrupt that stops everything. The IRQ is a "maskable" interrupt, in that its occurance can be prevented. The MMI is "non-maskable", and if such an event occurs, cannot be prevented. The SO, or Set Overflow, is not really an interrupt, but causes an externally generated condition, which can be used for control of program flow.
One important design feature, which must be remembered is that no interrupt can occur immediately after a one-cycle opcode. This is very important, because there are times when you want to temporarily prevent interrupts from occurring. The best example of this is, when setting a 16-bit stack pointer, you do not want an interrupt to occur between the times you set the low-order byte, and the high-order byte. If it could happen, the interrupt would do stack writes using a pointer that was only partially set, thus, writing to an unwanted area.

IRQ*
The IRQ* (Interrupt ReQuest) input will cause an interrupt, if it is at a low logic level, and the I processor status flag is reset. The interrupt sequence will begin with the first SYNC after a multiple-cycle opcode. The two program counter bytes PCH and PCL, and the processor status register P, are pushed onto the stack. (This causes the stack pointer SP to be decremented by 3.) Then the program counter bytes PCL and PCH are loaded from memory addresses FFFE and FFFF, respectively.
An interrupt caused by the IRQ* input, is similar to the BRK opcode, but differs, as follows. The program counter value stored on the stack points to the opcode that would have been executed, had the interrupt not occurred. On return from interrupt, the processor will return to that opcode. Also, when the P register is pushed onto the stack, the B or "break" flag pushed, is zero, to indicate that the interrupt was not software generated.

NMI*
The NMI* (Non-Maskable Interrupt) input will cause an interrupt after receiving high to low transition. The interrupt sequence will begin with the first SYNC after a multiple-cycle opcode. NMI* inputs cannot be masked by the processor status register I flag. The two program counter bytes PCH and PCL, and the processor status register P, are pushed onto the stack. (This causes the stack pointer SP to be decremented by 3.) Then the program counter bytes PCL and PCH are loaded from memory addresses FFFA and FFFB.
As with IRQ*, when the P register is pushed onto the stack, the B or "break" flag pushed, is zero, to indicate that the interrupt was not software generated.

RES*
The RES* (RESet) input will cause a hard reset instantly as it is brought to a low logic level. This effects the following conditions. The currently executing opcode will be terminated. The B and Z registers will be cleared. The stack pointer will be set to "byte" mode/with the stack page set to page 1. The processor status bits E and I will be set.
The RES* input should be held low for at least 2 clock cycles. But once brought high, the reset sequence begins on the CPU cycle. The first four cycles of the reset sequence do nothing. Then the program counter bytes PCL and PCH are loaded from memory addresses FFFC and FFFD, and normal program execution begins.



11. 65CE02 Addressing Modes
Overview
It should be noted that all 8-bit addresses are referred to as "byte" addresses, and all 16-bit addresses are referred to as "word" addresses. In all word addresses, the low-order byte of the address is fetched from the lower of two consecutive memory addresses, and the high-order byte of the address is fetched the higher of the two. So, in all operations, the low-order address is fetched first.

Implied                 OPR
The register or flag affected is identified entirely by the opcode in this (usually) single cycle instruction. In this document, any implied operation, where the implied register is not explicitly declared, implies the accumulator. Example: INC with no arguments implies "increment the accumulator".

Immediate (byte, word)        OPR #xx
The data used in the operation is taken from the byte or bytes immediately following the opcode in the 2-byte or 3-byte instruction.

Base Page                OPR bp (formerly Zero Page)
The second byte of the two-byte instruction contains the low-order address byte, and the B register contains the high-order address byte of the memory location to be used by the operation.

Base Page, indexed by X        OPR bp,X (formerly Zero Page,X)
The second byte of the two-byte instruction is added to the X index register to form the low-order address byte, and the B register contains the high-order address byte of the memory location to be used by the operation.

Base Page, indexed by Y        OPR bp,Y (formerly Zero Page,Y)
The second byte of the two-byte instruction is added to the Y index register to form the low-order address byte, and the B register contains the high-order address byte of the memory location to be used by the operation.

Absolute                OPR abs
The second and third bytes of the three-byte instruction contain the low-order and high-order address bytes, respectively, of the memory location to be used by the operation.

Absolute, indexed by X        OPR abs,X
The second and third bytes of the three-byte instruction are added to the unsigned contents of the X index register to form the low-order and high-order address bytes, respectively, of the memory location to be used by the operation.

Absolute, indexed by Y        OPR abs,Y
The second and third bytes of the three-byte instruction are added to the unsigned contents of the Y index register to form the low-order and high-order address bytes, respectively, of the memory location to be used by the operation.

Indirect (word)            OPR (abs) (JMP and JSR only)
The second and third bytes of the three-byte instruction contain the low-order and high-order address bytes, respectively, of two memory locations containing the low-order and high-order JMP or JSR addresses, respectively.

Indexed by X, indirect (byte)    OPR (bp,X) (formerly (zp,X) )
The second byte of the two-byte instruction is added to the contents of the X register to form the low-order address byte, and the contents of the B register contains the high-order address byte, of two memory locations that contain the low-order and high-order address of the memory location to be used by the operation.

Indexed by X, indirect (word) OPR (abs,X) (JMP and JSR only)
The second and third bytes of the three-byte instruction are added to the unsigned contents of the X index register to form the low-order and high-order address bytes, respectively, of two memory locations containing the low-order and high-order JMP or JSR address bytes.

Indirect, indexed by Y OPR (bp),Y (formerly (zp),Y )
The second byte of the two-byte instruction contains the low-order byte, and the B register contains the high-order address byte of two memory locations whose contents are added to the unsigned Y index register to form the address of the memory location to be used by the operation.

Indirect, indexed by Z OPR (bp),Z (formerly (zp) )
The second byte of the two-byte instruction contains the low-order byte, and the B register contains the high-order address byte of two memory locations whose contents are added to the unsigned Z index register to form the address of the memory location to be used by the operation.

Stack Pointer Indirect, indexed by Y OPR (d,SP),Y (new)
The second byte of the two-byte instruction contains an unsigned offset value, d, which is added to the stack pointer (word) to form the address of two memory locations whose contents are added to the unsigned Y register to form the address of the memory location to be used by the operation.

Relative (byte) Bxx LABEL (branches only)
The second byte of the two-byte branch instruction is sign-extended to a full word and added to the program counter (now containing the opcode address plus two). If the condition of the branch is true, the sum is stored back into the program counter.

Relative (word) Bxx LABEL (branches only)
The second and third bytes of the three-byte branch instruction are added to the low-order and high-order program counter bytes, respectively. (the program counter now contains the opcode address plus two). If the condition of the branch is true, the sum is stored back into the program counter.



12. 65CE02 Instruction Set
Add memory to accumulator with carry ADC

A=A+M+C

Addressing Mode Abbrev. Opcode

immediate IMM 69
base page BP 65
base page indexed X BP,X 75
absolute ABS 6D
absolute indexed X ABS,X 7D
absolute indexed Y ABS,Y 79
base page indexed indirect X (BP,X) 61
base page indirect indexed Y (BP),Y 71
base page indirect indexed Z (BP),Z 72

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

The ADC instructions add data fetched from memory and carry to
the contents of the accumulator. The results of the add are then
stored in the accumulator. If the "D" or Decimal Mode flag, in the
processor status register, then a Binary Coded Decimal (BCD) add is
performed.

The "N" or Negative flag will be set if the sum is negative,
otherwise it is cleared. The "V" or Overflow flag will be set if the
sign of the sum is different from the sign of both addends, indicating
a signed overflow. Otherwise, it is cleared. The "Z" or Zero flag is
set if the sum (stored into the accumulator) is zero, otherwise, it is
cleared. The "C" or carry is set if the sum of the unsigned addends
exceeds 255 (binary mode) or 99 (decimal mode).

Flags
N V E B D I Z C
N V - - - - Z C


And memory logically with accumulator AND

A=A.and.M

Addressing Mode Abbrev. Opcode

immediate IMM 29
base page BP 25
base page indexed X BP,X 35
absolute ABS 2D
absolute indexed X ABS,X 3D
absolute indexed Y ABS,Y 39
base page indexed indirect X (BP,X) 21
base page indirect indexed Y (BP),Y 31
base page indirect indexed 2 (BP),Z 32

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

The AND instructions perform a logical "and" between data bits
fetched from memory and the accumulator bits. The results are then
stored in the accumulator. For each accumulator and corresponding
memory bit that are both logical 1's, the result is a 1. Otherwise it
is 0.

The "N" or Negative flag will be set if the bit 7 result is a 1.
Otherwise it is cleared. The "Z" or Zero flag is set if all result
bits are zero, otherwise, it is cleared.

Flags
N V E B D I Z C
N - - - - - Z -


Arithmetic shifts, memory or accumulator, left or right ASL ASR ASW

ASL Arithmetic shift left A or M A<A<<1 or M<M<<1
ASR Arithmetic shift right A or M A<A>>1 or M<M>>1
ASW Arithmetic shift left M (word) Mx<Mw<<1

Opcodes
Addressing Mode Abbrev. ASL ASR ASW

register (A) 0A 43
base page BP 06 44
base page indexed X BP,X 16 54
absolute ABS 0E CB
absolute indexed X ABS,X 1E

Bytes Cycles Mode
1 1 register (ASL)
1 2 register (ASR)
2 4 base page (byte) non-indexed, or indexed X
3 5 absolute non-indexed, or indexed X
3 7 absolute (ASW)

The ASL instructions shift a single byte of data in memory or the
accumulator left (towards the most significant bit) one bit position.
A 0 is shifted into bit 0.

The "N" or Negative bit will be set if the result bit 7 is
(operand bit 6 was) a 1. Otherwise, it is cleared. The "Z" or Zero
flag is set if ALL result bits are zero. The "C" or Carry flag is set
if the bit shifted out is (operand bit 7 was) a 1. Otherwise, it is
cleared.

The ASR instructions shift a single byte of data in memory or the
accumulator right (towards the least significant bit) one bit
position. Since this is an arithmetic shift, the sign of the operand
will be maintained.

The "N" or Negative bit will be set if bit 7 (operand and result)
a 1. Otherwise, it is cleared. The "Z" or Zero flag is set if ALL
result bits are zero. The "C" or Carry flag is set if the bit shifted
out is (operand bit 0 was) a 1. Otherwise, it is cleared.

The ASW instruction shifts a word (two bytes) of data in memory
left (towards the most significant bit) one bit position. A zero is
shifted into bit 0.

The "N" or Negative bit will be set if the result bit 15 is
(operand bit 14 was) a 1. Otherwise, it is cleared. The "Z" or Zero
flag is set if ALL result bits (both bytes) are zero. The "C" or Carry
flag is set if the bit shifted out is (operand bit 15 was) a 1.
Otherwise, it is cleared.

Flags
N V E B D I Z C
N - - - - - Z C


Branch conditional or unconditional BCC BCS BEQ BMI BNE
BPL BRA BVC BVS

Opcode Opcode Byte Opcode Word Opcode
Title Relative Relative Purpose

BCC 90 93 Branch if Carry Clear
BCS B0 B3 Branch if Carry Set
BEQ F0 F3 Branch if EQual (Z flag set)
BMI 30 33 Branch if MInus (N flag set)
BNE D0 D3 Branch if Not Equal (Z flag clear)
BPL 10 13 Branch if PLus (N flag clear)
BRA 80 83 BRanch Always
BVC 50 53 Branch if oVerflow Clear
BVS 70 73 Branch if oVerflow Set

Bytes Cycles Mode
2 2 byte-relative
3 3 word-relative

All branches of this type are taken, if the condition indicated
by the opcode is true. All branch relative offsets are referenced to
the branch opcode location+2. This means that for byte-relative, the
offset is relative to the location after the two instruction bytes.
For word-relative, the offset is relative to the last of the three
instruction bytes.

Flags
N V E B D I Z C
- - - - - - - -


Break: (force an interrupt) BRK

Bytes Cycles Mode Opcode
2 7 implied 00 (stack)<PC+1w,P SP<SP-2

The BRK instruction causes the processor to enter the IRQ or
Interrupt ReQuest state. The program counter (now incremented by 2),
bytes PCH and PCL, and the processor status register P, are pushed
onto the stack. (This causes the stack pointer SP to be decremented by
3.) Then the program counter bytes PCL and PCH are loaded from memory
addresses FFFE and FFFF, respectively.

The BRK differs from an externally generated interrupt request
(IRQ) as follows. The program counter value stored on the stack is
PC+2, or the address of the BRK opcode+2. On return from interrupt,
the processor will return to the BRK address+2, thus skipping the
opcode byte, and a following "dummy" byte. A normal IRQ will not add
2, so that a return will execute the interrupted opcode. Also, when
the P register is pushed onto the stack, the B or "break" flag is set,
to indicate that the interrupt was software generated. All outside
interrupts push P with the B flag cleared.

Flags
N V E B D I Z C
- - - - - - - -

Branch to subroutine BSR

Bytes Cycles Mode Opcode
3 5 word-relative 63 (stack)<PC+2w SP<SP-2

The BSR Branch to SubRoutine instruction pushes the two program
counter bytes PCH and PCL onto the stack. It then adds the
word-relative signed offset to the program counter. The relative
offset is referenced to the address of the BSR opcode+2, hence, it is
relative to the third byte of the three-byte BSR instruction. The
return address, on the stack, also points to this address. This was
done to make it compatible with the RTS functionality, and to be
consistant will other word-relative operations.

Flags
N V E B D I Z C
- - - - - - - -


Clear processor status bits CLC CLD CLE CLI CLV

Opcode Cycles Flags

N V E B D I Z C
CLC Clear the Carry bit 18 1 - - - - - - - R
CLD Clear the Decimal mode bit D8 1 - - - - R - - -
CLE Clear stack Extend disable bit 02 2 - - R - - - - -
CLI Clear Interrupt disable bit 58 2 - - - - - R - -
CLV Clear the Oveflow bit B8 1 - R - - - - - -

Bytes Mode
1 implied

All of the P register bit clear instructions are a single byte
long. Most of them require a single CPU cycle. The CLI and CLE require
2 cycles. The purpose of extending the CLI to 2 cycles, is to enable
an interrupt to occur immediately, if one is pending. Interrupts
cannot occur after single cycle instructions.


Compare registers with memory CMP CTX CPY CPZ

CMP Compare accumulator with memory (A-M)
CPX Compare index X with memory (X-M)
CPY Compare index Y with memory (Y-M)
CPZ Compare index Z with memory (Z-M)

Opcodes
Addressing Mode Abbrev. CMP CPX CPY CPZ

immediate IMM C9 E0 C0 C2
base page BP C5 E4 C4 D4
base page indexed X BP,X D5
absolute ABS CD EC CC DC
absolute indexed X ABS,X DD
absolute indexed Y ABS,Y D9
base page indexed indirect X (BP,X) C1
base page indirect indexed Y (BP),Y D1
base page indirect indexed Z (BP),Z D2

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

Compares are performed by subtracting a value in memory from the
register being tested. The results are not stored in any register,
except the following status flags are updated.

The "N" or Negative flag will be set if the result is negative
(assuming signed operands), otherwise it is cleared. The "Z" or Zero
flag is set if the result is zero, otherwise it is cleared. The "C" or
carry flag is set if the unsigned register value is greater than or
equal to the unsigned memory value.

Flags
N V E B D I Z C
N - - - - - Z C


Compare registers with memory CMP CPX CPY CPZ

CMP Compare accumulator with memory (A-M)
CPX Compare index X with memory (X-M)
CPY Compare index Y with memory (Y-M)
CPZ Compare index Z with memory (Z-M)

Opcodes
Addressing Mode Abbrev. CMP CPX CPY CPZ

immediate IMM C9 E0 C0 C2
base page BP C5 E4 C4 D4
base page indexed X BP,X D5
absolute ABS CD EC CC DC
absolute indexed X ABS,X DD
absolute indexed Y ABS,Y D9
base page indexed indirect X (BP.X) C1
base page indirect indexed Y (BP),Y D1
base page indirect indexed Z (BP),Z D2

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

Compares are performed by subtracting a value in memory from the
register being tested. The results are not stored in any register,
except the following status flags are updated.

The "N" or Negative flag will be set if the result is negative
(assuming signed operands), otherwise it is cleared. The "Z" or Zero
flag is set if the result is zero, otherwise it is cleared. The "C" or
carry flag is set if the unsigned register value is greater than or
equal to the unsigned memory value.

Flags
N V E B D I Z C
N - - - - - Z C


Exclusive OR accumulator logically with memory EOR

A=A.or.M.and..not.(A.and.M)

Addressing Mode Abbrev. Opcode

immediate IMM 49
base page BP 45
base page indexed X BP,X 55
absolute ABS 4D
absolute indexed X ABS,X 5D
absolute indexed Y ABS,Y 59
base page indexed indirect X (BP,X) 41
base page indirect indexed Y (BP),Y 51
base page indirect indexed Z (BP),Z 52

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

The EOR instructions perform an "exclusive or" between bits
fetched from memory and the accumulator bits. The results are then
stored in the accumulator. For each accumulator or corresponding
memory bit that are different (one 1, and one 0) the result is a 1.
Otherwise it is 0.

The "N" or Negative flag will be set if the bit 7 result is a 1.
Otherwise it is cleared. The "Z" or Zero flag is set if all result
bits are zero, otherwise, it is cleared.

Flags
N V E B D I Z C
N - - - - - Z -


Jump to subroutine JSR

Addressing Mode Abbrev. Opcode bytes cycles

absolute ABS 20 3 5
absolute indirect (ABS) 22 3 7
absolute indexed indirect X (ABS,X) 23 3 7

The JSR Jump to SubRoutine instruction pushes the two program
counter bytes PCH and PCL onto the stack. It then loads the program
counter with the new address. The return address, stored on the stack,
is actually the address of the JSR opcode+2, or is pointing to the
third byte of the three-byte JSR instruction.

Flags
N V E B D I Z C
- - - - - - - -


Load registers LDA LDX LDY LDZ

LDA Load Accumulator from memory A<M
LDX Load index X from memory X<M
LDY Load index Y from memory Y<M
LDZ Load index Z from memory Z<M

Addressing Mode Abbrev. LDA LDX LDY LDZ

immediate IMM A9 A2 A0 A3
base page BP A5 A6 A4
base page indexed X BP,X B5 B4
base page indexed Y BP,Y B6
absolute ABS AD AE AC AB
absolute indexed X ABS,X BD BC BB
absolute indexed Y ABS,Y B9 BE
base page indexed indirect X (BP,X) A1
base page indirect indexed Y (BP),Y B1
base page indirect indexed Z (BP),Z B2
stack vector indir indexed Y (d,SP),Y E2

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z
2 6 stack vector indirect indexed Y

These instructions load the specified register from memory. The
"N" or Negative flag will be set if the bit 7 loaded is a 1. Otherwise
it is cleared. The "Z" or Zero flag is set if all bits loaded are
zero, otherwise, it is cleared.

Flags
N V E B D I Z C
7 - - - - - Z -

Negate (twos complement) accumulator NEG

A=-A

Addressing Mode Opcode Bytes Cycles
implied 42 1 2

The NEG or "negate" instruction performs a two's-complement
inversion of the data in the accumulator. For example, 1 becomes -1,
-5 becomes 5, etc. The same can be achieved by subtracting A from
zero.

The "N" or Negative flag will be set if the accumulator bit 7
becomes a 1. Otherwise it is cleared. The "2" or Zero flag is set if
the accumulator is (and was) zero.

Flags
N V E B D I Z C
N - - - - - Z -


No-operation NOP

Addressing Mode Opcode Bytes Cycles

implied EA 1 1

The NOP no-operation instruction has no effect, unless used
following a MAP opcode. Then its is interpreted as a EOM end-of-map
instruction. (See EOM)

Flags
N V E B D I Z C
- - - - - - - -

Or memory logically with accumulator ORA

A=A.or.M

Addressing Mode Abbrev. Opcode

immediate IMM 09
base page BP 05
base page indexed X BP,X 15
absolute ABS 0D
absolute indexed X ABS,X ID
absolute indexed Y ABS,Y 19
base page indexed indirect X (BP,X) 01
base page indirect indexed Y (BP),Y 11
base page indirect indexed Z (BP),2 12

Bytes Cycles Mode
2 2 immediate
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z

The ORA instructions perform a logical "or" between data bits
fetched from memory and the accumulator bits. The results are then
stored in the accumulator. For either accumulator or corresponding
memory bit that is a logical 1's, the result is a 1. Otherwise it is
0.

The "N" or Negative flag will be set if the bit 7 result is a 1.
Otherwise it is cleared. The "Z" or Zero flag is set if all result
bits are zero, otherwise, it is cleared.

Flags
N V E B D I Z C
N - - - - - Z -


Pull register data from stack PLA PLP PLX PLY PLZ

Opcode

PLA Pull Accumulator from stack 68
PLX Pull index X from stack FA
PLY Pull index Y from stack 7A
PLZ Pull index Z from stack FB
PLP Pull Processor status from stack 28

Bytes Cycles Mode
1 3 register

The Pull register operations, first, increment the stack pointer
SP, and then, load the specified register with data from the stack.

Except in the case of PLP, the "N" or Negative flag will be set
if the bit 7 loaded is a 1. Otherwise it is cleared. The "Z" or Zero
flag is set if all bits loaded are zero, otherwise, it is cleared.

In the case of PLP, all processor flags (P register bits) will be
loaded from the stack, except the "B" or "break" flag, which is always
a 1, and the "E" or "stack pointer Extend disable" flag, which can
only be set by SEE, or cleared by CLE instructions.

Flags
N V E B D I Z C
N - - - - - Z - (except PLP)
7 6 - - 3 2 1 0 (PLP only)


Push registers or data onto stack PHA PHP PHW PHX PHY PHZ

PHA Push Accumulator onto stack
PHP Push Processor status onto stack
PHW Push a word from memory onto stack
PHX Push index X onto stack
PHY Push index Y onto stack
PHZ Push index Z onto stack

Opcodes
Addressing Mode Abbrev. PHA PHP PHW PHX PHY PHZ

register 48 08 DA 5A DB
word immediate IMMw F4
word absolute ABSw FC

Bytes Cycles Mode
1 3 register
3 5 word immediate
3 7 word absolute

These instructions push either the contents of a register onto
the stack, or push two bytes of data from memory (PHW) onto the stack.
If a register is pushed, the stack pointer will decrement a single
address. If a word from memory is pushed ([SP]<-PC(LO),
[SP-1]<-PC(HI)), the stack pointer will decrement by 2. No flags are
changed.

Flags
N V E B D I Z C
- - - - - - - -


Reset memory bits RMB

M=M.and.-bit

Opcode to reset bit
0 1 2 3 4 5 6 7

07 17 27 37 47 57 67 77

Bytes Cycles Mode
2 4 base-page

These instructions reset a single bit in base-page memory, as
specified by the opcode. No flags are modified.

Flags
N V E B D I Z C
- - - - - - - -


Rotate memory or accumulator, left or right ROL ROR ROW

ROL Rotate memory or accumulator left throught carry
ROR Rotate memory or accumulator right throught carry
ROW Rotate memory (word) left throught carry

Opcodes
Addressing Mode Abbrev. ROL ROR ROW

register (A) 2A 6A
base page BP 26 66
base page indexed X BP,X 36 76
absolute ABS 2E 6E EB
absolute indexed X ABS,X 3E 7E

Bytes Cycles Mode
1 1 register
2 4 base page (byte) non-indexed, or indexed X
3 5 absolute non-indexed, or indexed X
2 6 absolute (word)

The ROL instructions shift a single byte of data in memory or the
accumulator left (towards the most significant bit) one bit position.
The state of the "C" or "carry" flag is shifted into bit 0.

The "N" or Negative bit will be set if the result bit 7 is
(operand bit 6 was) a 1. Otherwise, it is cleared. The "Z" or Zero
flag is set if ALL result bits are zero. The "C" or Carry flag is set
if the bit shifted out is (operand bit 7 was) a 1. Otherwise, it is
cleared.

The ROR instructions shift a single byte of data in memory or the
accumulator right (towards the least significant bit) one bit
position. The state of the "C" or "carry" flag is shifted into bit 7.

The "N" or Negative bit will be set if bit 7 is (carry was) a 1.
Otherwise, it is cleared. The "Z" or Zero flag is set if ALL result
bits are zero. The "C" or Carry flag is set if the bit shifted out is
(operand bit 0 was) a 1. Otherwise, it is cleared.

The ROW instruction shifts a word (two bytes) of data in memory
left (towards the most significant bit) one bit position. The state of
the "C" or "carry" flag is shifted into bit 0.

The "N" or Negative bit will be set if the result bit 15 is
(operand bit 14 was) a 1. Otherwise, it is cleared. The "Z" or Zero
flag is set if ALL result bits (both bytes) are zero. The "C" or Carry
flag is set if the bit shifted out is (operand bit 15 was) a 1.
Otherwise, it is cleared.

Flags
N V E B D I Z C
N - - - - - Z C

Return from BRK, interrupt, kemal, or subroutine RTI RTN RTS

Operation description Opcode bytes cycles

RTI Return from interrupt 40 1 5 P,PCw<(SP),SP<SP+3
RTN #n Return from kernal 62 2 7 PCw<(SP)+1,SP<SP+2+N
RTS Return from subroutine 60 1 4 PCw<(SP)+1,SP<SP+2

The RTI or ReTurn from Interrupt instruction pulls P register
data and a return address into program counter bytes PCL and PCH from
the stack. The stack pointer SP is resultantly incremented by 3.
Execution continues at the address recovered from the stack.

Flags
N V E B D I Z C
7 6 - - 3 2 1 0 (RTI only)

The RTS or ReTurn from Subroutine instruction pulls a return
address into program counter bytes PCL and PCH from the stack. The
stack pointer SP is resultantly incremented by 2. Execution continues
at the address recovered + 1, since BSR and JSR instructions set the
return address one byte short of the desire return address.

The RTN or ReTurn from kerNal subroutine is similar to RTS,
except that it contains an immediate parameter N indicating how many
extra bytes to discard from the stack. This is useful for returning
from subroutines which have arguments passed to them on the stack. The
stack pointer SP is incremented by 2 + N, instead of by 2, as in RTS.

Flags
N V E B D I Z C
- - - - - - - - (RTN and RTS)
7 6 - - 3 2 1 0 (RTI)

Set memory bits SMB

M=M.or.bit

Opcode to set bit
0 1 2 3 4 5 6 7
87 97 A7 B7 C7 D7 E7 F7

Bytes Cycles Mode
2 4 base-page

These instructions set a single bit in base-page memory, as
specified by the opcode. No flags are modified.

Flags
N V E B D I Z C

Store registers STA STX STY STZ

STA Store Accumulator to memory M<A
STX Store index X to memory M<X
STY Store index Y to memory M<Y
STZ Store index Z to memory M<Z

Opcodes
Addressing Mode Abbrev. STA STX STY STZ

base page BP 85 86 84 64
base page indexed X BP,X 95 94 74
base page indexed Y BP,Y 96
absolute ABS 8D 8E 8C 9C
absolute indexed X ABS,X 9D SB 9E
absolute indexed Y ABS,Y 99 9B
base page indexed indirect X (BP,X) 81
base page indirect indexed Y (BP),Y 91
base page indirect indexed Z (BP),Z 92
stack vector indir indexed Y (d,SP),Y 82

Bytes Cycles Mode
2 3 base page non-indexed, or indexed X or Y
3 4 absolute non-indexed, or indexed X or Y
2 5 base page indexed indirect X, or indirect indexed Y or Z
2 6 stack vector indirect indexed Y

These instructions store the specified register to memory. No
flags are affected.

Flags
N V E B D I Z C
- - - - - - - -

Transfers (between registers) TAB TAX TAY TAZ
TBA TSX TSY TXA
TXS TYA TYS TZA

Operation Flags Transfer
Symbol Code N V E B D I Z C from to

TAB 5B - - - - - - - - accumulator base page reg
TAX AA N - - - - - Z - accumulator index X reg
TAY A8 N - - - - - Z - accumulator index Y reg
TAZ 4B N - - - - - Z - accumulator index Z reg
TBA 7B N - - - - - Z - base page reg accumulator
TSX BA N - - - - - Z - stack ptr low index X reg
TSY 0B N - - - - - Z - stack ptr high index Y reg
TXA 8A N - - - - - Z - index X reg accumulator
TXS 9A - - - - - - - - index X reg stack ptr low
TYA 98 N - - - - - Z - index Y reg accumulator
TYS 2B - - - - - - - - index Y reg stack ptr high
TZA 6B N - - - - - Z - index Z reg accumulator

These instructions transfer the contents of the specified source
register to the specified destination register. Any transfer to A, X,
Y, or Z will affect the flags as follows. The "N" or "negative" flag
will be set if the value moved is negative (bit 7 set), otherwise, it
is cleared. The "Z" or "zero" flag will be set if the value moved is
zero (all bits 0), otherwise, it is cleared. Any transfer to SPL or
SPH will not alter any flags.

************************************************************
* WARNING *
* *
* If you are using Non-Maskable-Interrupts, or Interrupt *
* Request is enabled, and you want to change BOTH stack *
* pointer bytes, do not put any code between the TXS and *
* TYS opcodes. Taking this precaution will prevent any *
* interrupts from occuring between the setting of the *
* two stack pointer bytes, causing a potential for *
* writing stack data to an unwanted area. *
************************************************************

Bytes Cycles Mode
1 1 register

Test and reset or set memory bits TRB TSB

TRB Test and reset memory bits with accumulator (M.or.A),M<M.and.-A
TSB Test and set memory bits with accumulator (M.or.A),M<M.or.A

Opcodes
Addressing Mode Abbrev. TRB TSB

base page BP 14 04
absolute ABS 1C OC

These instructions test and set or reset bits in memory, using
the accumulator for both a test mask, and a set or reset mask. First,
a logical AND is performed between memory and the accumulator. The "Z"
or "zero" flag is set if all bits of the result of the AND are zero.
Otherwise it is reset.

The TSB then performs a logical OR between the bits of the
accumulator and the bits in memory, storing the result back into
memory.

The TRB, instead, performs a logical AND between the inverted
bits of the accumulator and the bits in memory, storing the result
back into memory.

Bytes Cycles Mode
2 4 base page non-indexed
3 5 absolute non-indexed

Flags
N V E B D I Z C
- - - - - - Z -



