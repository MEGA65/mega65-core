VIC-IV Video Modes
==================

The VIC-IV supports all standard VIC-II video modes, as well as the
VIC-III's 640x200 bitmap and 80 column text modes.  All VIC-III
extended character attributes are supported.

No Abominable C65 bit-plane modes
---------------------------------

VIC-III bitplanar modes are NOT supported at this time, and are
unlikely to ever be.  This is because bitplanar modes are crazy on an
8-bit computer.  First, they are a pain to manipulate.  Second, they
require bucket loads of RAM for a large high-resolution display --
even if most of the image is empty or repetative.  For example, a 256
colour 1920x1200 (the native resolution of the C65GS) image would
require 2250KB of RAM.  But the C65 and C65GS only have 128KB of
chipram!

This is likely to be the most significant cause of incompatibility
with existing graphics related C65 software, all dozen or so examples
of it.

New VIC-IV video modes
----------------------

In place of bitplanar modes, the VIC-IV offers several new features:

First, "full colour mode" (FCM) complements the VIC-II's multi-colour
mode (MCM) and extended-background colour mode (ECM).  FCM is used
with text mode to change the character generator to use 64 bytes per
8x8 character. Each pixel is specified by a byte, hence the
designation of full colour mode, as the full palette is available to
each character.  To simplify the VIC-IV logic, the character addresses
are fixed at 64 bytes * character number.

The second feature is 16bit character set (16C) mode. In 16C mode two
bytes of screen RAM are used for each character. Only the bottom 14
bits of the character number are used, allowing for 4096 unique
glyphs, since 4096*64 = 256KB, which is double the chipram in the
machine, anyway.  This means that in practice only 2,048 characters
are available until I figure out a way to increase the size of the
chipram (probably not until the next FPGA generation).

The third feature is that if 16C mode is enabled with VIC-II bitmap
mode, the availability of 16 bits of screen ram information per card
is used to specify a full 8-bit colour for the foreground and
background of each card.  Thus bitmap images can now use all 256
colours, subject to some limitations. Most notably, MCM colours remain
shared over the whole image, although the MCM colour registers are
also 8-bit if written to with VIC-III/VIC-IV registers enabled via
$D02F.

Mode independent features
-------------------------

In addition to the above, there are some new mode-independent
features.  

The most notable is the ability to change the pixel scale
using $D042 and $D043.  The default scale value is $04 which means
($04+1) = 5 physical pixels per logical pixel in the X and Y
dimenstions.  Value values are $00 (for native 1920x1200) through to
$1F for all pixels to be scaled 32x.  X and Y can be set to different
values.

The position of the text field can be easily manipulated using two
16-bit vernier register pairs at $D04C - $D04F. Border positions can
be similarly manipulated with ease via 16bit register pairs located
$D044 through $D04B.

There also exist registers to set the logical line length in text and
bitmap modes, i.e., by changing the row length from 40 (or 80 in 640H
modes) to something else.  The screen memory and colour memory base
can also be set to any multiple of 8.  Together, these allow arbitrary
panning through large virtual screen maps.  This feature makes VSP and
other DMA-delay techniques obsolete, which is good, because neither
the C65 nor C65GS support VSP due to the significantly different
timing of the VIC-III and VIC-IV compared with the VIC-II (and each
other). 

Legacy mode emulation
---------------------

Because of the availability of precise vernier registers to set a wide
range of video parameters directly, $D011, $D016 and other VIC-II and
VIC-III video mode registers are implemented as virtual registers:
writing to any of these results in computed consistent values being
applied to all of the relevant vernier registers.  This means that
writing to any of these virtual registers will reset the video mode.
Thus some care has to be taken when using new VIC-IV features to not
touch any of the "hot" VIC-II and VIC-III registers.

The "hot" registers to be careful with are:

$D011, $D016, $D018, $D031 and the VIC-II bank bits of $DD00.