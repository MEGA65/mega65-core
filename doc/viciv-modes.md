VIC-IV Video Modes
==================

The VIC-IV supports all standard VIC-II video modes, as well as the
VIC-III's 640x200 bitmap and 80 column text modes.  All VIC-III
extended character attributes are supported.

C65 Bitplanes
---------------------------------

The C65/VIC-III bitplane modes are now supported, although there is a bug causing
data in bitplane 7 to appear shifted 8 pixels to the right. There are other known
issues relating to placement of the bitplanes as whole, and also with H640 mode.

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

If you write to any of those, various VIC-IV registers will need to be re-written
with the values you wish to maintain.

Accessing VIC-III and VIC-IV registers
------------

The C65's VIC-III uses a special mechanism to protect the new VIC-III registers from accidental access.
To access the VIC-III registers, one must write $A5 and then $96 into register $D02F.  This makes the additional registers visible from $D030-$D07F, and the VIC-III palette registers at $D100-$D3FF, instead of repeating the VIC-II registers through those ranges.

The VIC-IV and MEGA65 follow this scheme, by adding a new sequence of values, $47 and $53 that must be written to $D02F, to enable not only the VIC-III additional registers, but also the VIC-IV enhanced registers.

Why the new VIC-IV modes are Character and Bitmap modes, not Bitplane modes
----------------------

The new VIC-IV video modes are derived from the VIC-II character and bitmap modes, rather than the VIC-III
bitplaner modes. This decision was based on several realities of programming a memory-constrained 8-bit home computer:

1. Bitplanes require that the same amount of memory is given to each area on screen, regardless of whether it 
is showing empty space, or complex graphics. There is no way with bitplanes to reuse content from within an image in
another part of the image.  However, most C64 games use highly repetitive displays, with common elements appearing in various
places on the screen, of which Boulder Dash and Super Giana Sisters would be good examples.  

2. Bitplanes also make it difficult to update a display, because every pixel is unique, in that there is no way to make a change,
for example to the animation in an onscreen element, and have it take effect in all places at the same time. The diamond
animations in Boulder Dash are a good example of this problem.  The requirement to modify multiple separate bytes in each
bitplane create an increased computational burden, which is why there were calls for the Amiga AAA chipset to include so-called
"chunky" modes, rather than just bitplanar modes.  While the Display Address Translator (DAT) and DMAgic of the C65 provide some
relief to this problem, the relief is only partial.

3. Scrolling using the C65 bitplanes requires copying the entire bitplane, as the hardware support for smooth scrolling does not
extend to changing the bitplane source address in a fine manner.  Even using the DMAgic to assist, scrolling a 320x200 256-colour
display requires 128,000 clock cycles in the best case (reading and writing 320x200 = 64000 bytes). At 3.5MHz on the C65 this 
would require about 36 milli-seconds, or about 2 complete video frames.  Thus for smooth scrolling of such a display, a double
buffered arrangement would be required, which would consume 128,000 of the 131,072 bytes of memory.  

In contrast, the well known character modes of the VIC-II are widely used in games, due to their ability to allow a small amount
of screen memory to select which 8x8 block of pixels to display, allowing very rapid scrolling, reduced memory consumption, and 
effective hardware acceleration of animation of common elements.  Thus the focus of improvements in the VIC-IV has been on
character mode.  As bitmap mode on the VIC-II is effectively a special case of character mode, with implied character numbers, it
comes along free for the ride on the VIC-IV, and will only be mentioned in the context of a very few bitmap-mode specific
improvements that were trivial to make, and it thus seemed foolish to not implement, in case they find use.

Displaying more than 256 unique characters via "16-bit Character Mode"
-------

The primary innovation is the addition of 16-bit character mode. The name is perhaps a little misleading, as in fact the character mode of the VIC-II is already 12 bit: Each 8x8 cell is defined by 12 bits of data: 8 bits of screen RAM data, by default from $0400-$07E7, indicating which characters to show, and 4 bits of colour data from the 1K nybl colour RAM at $D800-$DBFF. The VIC-III of the C65 uses 16 bits, as the colour RAM is now 8 bits, instead of 4, with the extra 4 bits of colour RAM being used to support attributes (blink, bold, underline and reverse video).  It is recommended to revise how this works, before reading the following. A good introduction to the VIC-II text mode can be found in many places, for example, http://dustlayer.com/vic-ii/2013/4/26/vic-ii-for-beginners-screen-modes-cheaper-by-the-dozen. 

The 16-bit character mode is enabled by setting bit 0 in $D054 (remember to enable VIC-IV mode, to make this register accessible). When this bit is set, two bytes are used for each of the screen memory and colour RAM for each character shown on the display. Thus, in contrast to the 12 bits of information that the C64 uses per character, and the 16 bits that the VIC-III uses, the VIC-IV has 32 bits of information.  How those 32 bits are used varies slightly among the particular modes.  The default is as follows:

| Bit | Function |
| --- | --- |
| Screen RAM byte 0 | Lower 8 bits of character number, the same as the VIC-II and VIC-III |
| Screen RAM byte 1, bits 0 - 3 | Upper 4 bits of character number, allowing addressing of 4096 unique characters |
| Colour RAM byte 0, bit 7 | Vertically flip the character |
| Colour RAM byte 0, bit 6 | Horizontally flip the character |
| Colour RAM byte 0, bit 5 | Alpha blend mode (leave 0, discussed later) |
| Colour RAM byte 0, bit 4 | Reserved (leave 0) |
| Colour RAM byte 0, bits 3 | Trim top or trim bottom of character (for variable height characters ) |
| Colour RAM byte 0, bits 0 - 2 | Number of pixels to trim from top or bottom of character |
| Colour RAM byte 1, bits 0 - 3 | Low 4 bits of colour of character |
| Colour RAM byte 1, bit 4 | Hardware blink of character (if VIC-III extended attributes are enabled) |
| Colour RAM byte 1, bit 5 | Hardware reverse video enable of character (if VIC-III extended attributes are enabled) |
| Colour RAM byte 1, bit 6 | Hardware bold attribute of character (if VIC-III extended attributes are enabled) |
| Colour RAM byte 1, bit 7 | Hardware underlining of character (if VIC-III extended attributes are enabled) |


