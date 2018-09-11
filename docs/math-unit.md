Math Unit aka Formula Plumbing Unit
===================================

Math-coprocessors have existed for several decades, reflecting the
utility that they provide in complementing general purpose processors
for a variety of workloads.

The question is how to interface such
a co-processor to a 6502-derived processor. In particular, the 6502
has very few and very narrow registers, which makes transferring
significant amounts of information to a co-processor rather slow.
Even transferring a 32-bit value requires multiple instructions to
achieve.  Some historical math co-processors use stack-based
approaches, or allow the math unit to take over the instruction stream
processing from the primary processor. However, the 8-bit memory bus
of a 6502 processor is a significant challenge, in that it adds
considerable delay to each operation.

To relieve these problems, the math co-processor of the MEGA65 uses a
somewhat different approach, designed to alleviate these problems.
Rather than being issued a single math operation and data to be
performed, it is configured to implement a complete (or partial)
formula in parallel. Perhaps the best way to think about this is to
compare it with a spreadsheet: You have a number of cells
(representing math
registers), each of which can be defined as a calculation dependent on
other cells in the spreadshets (with each calculation corresponding to
a math functional unit in the co-processor).

This approach has a number of advantages: (1) Once configured to calculate
the result of a formula, the intermediate values do not need to be
manipulated by the 6502 processor, but are instead internally
transported by the co-processor. (2) Cells can refer to one another,
so that outputs can be fed back into inputs, to allow for iterative
functions to be calculated without any further processor
intervention. (3) Where many calculations of the same formula, but
using (partially or completely) different input data, the CPU need
only update the data inputs that change between each calculation,
allowing for more efficient operation. (4) While the math unit is
calculating, the CPU is completely free to do other productive
work. (5) Multiple calculations can occur in parallel, depending on
the type of calculation defined.

This is all a bit theoretical, so lets make this concrete with an
example that is particularly well suited to this approach: Calculating
Mandelbrot pixels.  The simplest way to calculate pixels of the
Mandelbrot fractal is something like the following (from
https://en.wikipedia.org/wiki/Mandelbrot_set): 

```
For each pixel (Px, Py) on the screen, do:
{
  x0 = scaled x coordinate of pixel (scaled to lie in the Mandelbrot X scale (-2.5, 1))
  y0 = scaled y coordinate of pixel (scaled to lie in the Mandelbrot Y scale (-1, 1))
  x = 0.0
  y = 0.0
  iteration = 0
  max_iteration = 1000
  while (x*x + y*y < 2*2  AND  iteration < max_iteration) {
    xtemp = x*x - y*y + x0
    y = 2*x*y + y0
    x = xtemp
    iteration = iteration + 1
  }
  color = palette[iteration]
  plot(Px, Py, color)
}
```

The main idea is to perform the same calculation repeatedly, with the
output of the calculation being fed back into the input.  When the
result of this calculation either exceeds the value of four, or if it
looks like never doing so, then it is stopped.

If we break the calculation for each iteration of the `<while>` loop,
we can see that it consists of squaring x and y, as well as
calculating `<2*x*y>`, and then performing a few additions.  We could
implement a single iteration of this in a little spreadsheet as
follows:

|   | A | B | C | D |
| === | === | === | === | === |
| 1 | x | y | x0 | y0 |
| 2 | =A1*A1 | =B1*B1 | =A1*B1 | =A2*D3 |
| 3 | =A2-B2 | | | 2 |
| 4 | =A3+C1 | =D2+D1 | | |

The size of this spreadsheet is not accidental: It corresponds to the
16 math unit registers of the MEGA65 math unit.  Similarly, each cell
contains either a simple value, or only a single simple calculation
referencing exactly two other cells,
corresponding to the 16 math functional units of the MEGA65 math
unit. In principle, any such spreadsheet that uses only
multiplication, addition and subtraction (division is coming soon) can
be implemented in the MEGA65 math unit.

Going through the spreadsheet above, cells A1 through D1 contain the
inputs of the calculation.  Cell A1 
calculates x*x, B2 calculates y*y, B3 x*y, and B4 2*x*y, taking the
result of the calculation of x*y from B3 as input.  A3 then calculates
x*x-y*y using the result of the calculations of A2 and B2, i.e., x*x
and y*y, as inputs.  Finally, cells A4 and B4 add x0 and y0 to these
results to produce the final result. A total of seven simple
calculations have been performed, using 11 cells.  However, although
there are seven calculations, several of these can occur in parallel.
In particular x*x and y*y can occur at the same time, as can the
difference between squares and 2*x*y, and the final
additions.  Thus while there are seven calculations, the math unit can
do all of these in only three steps:

1. x*x, y*y, x*y
2. 2*x*y, x*x - y*y
3. 2*x*y + y0, x*x - y*y + x0

That is, it will be performing more than two operations in parallel in
this case. A nice feature of this spreadsheet-like approach is that,
just as for a regular spreadsheet, you don't need to work out what can
happen in parallel, instead it just happens automatically.  This is
important, because writing parallel programs is not very easy to do.

Another benefit we can see from the spreadsheet approach is that we
don't need to fiddle about with the intermediate values of the
calculations. This is important for a 6502-like CPU, where we can move
only 8-bits at a time.  Thus manipulating many calculations tends to
be very slow on a 6502, even ignoring the lack of built-in multiply or
divide operations.  In contrast, on the MEGA65 math unit, all we have
to do is to setup the "plumbing" of the spreadsheet, and then provide
the input values.  In the case of the above, this would require the
following steps:

1. Set math register 0 to 0 (this is the initial value of X)
2. Set math register 1 to 0 (this is the initial value of Y)
3. Set math register 2 to x0
4. Set math register 3 to y0
5. Set math register 11 to 2
6. Configure a multiplier to use math register 0 as both its inputs (to
calculate x*x), and write its output into math register 4.
7. Configure a multiplier to use math register 1 as both its inputs (to
calculate y*y), and write its output into math register 5.
8. Configure a multiplier to use math registers 0 and 1 as its inputs
(to calculate x*y), and write its output into math register 6.
9. Configure a multiplier to use math registers 6 and 11 as its inputs
(to calculate 2*x*y), and write its output into math register 7.
10. Configure a subtractor to use math registers 4 and 5 as its inputs
(to calculate x*x - y*y), and write its output into math register 9.
11. Configure an adder to use math registers 9 and 2 as its inputs (to
calculate x*x - y*y + x0), and write its output into math register 12.
12. Configure an adder to use math registers 10 and 3 as its inputs (to
calculate 2*x*y + y0), and write its output into math register 13.

While that sounds like a lot of work, it is quite a bit simpler than
it sounds, and much, much simpler than trying to calculate these
directly.  Setting the math registers simply consists of writing the
32-bit value into four consecutive bytes between $D780 and $D7BF (but
make sure you have MEGA65/VIC-IV IO mode enabled first), and
configuring the math functional units (the multipliers, adders and
subtractors) requires writing two bytes at $D7C0+n and $D7D0+n, where
n is the number of the functional unit. The bytes at $D7Cx specify
the two inputs, with the low and high nybl of each byte selecting one
of the 16 math registers as input.  The bytes at $D7Dx specify the
operation to be performed, and where to write the output: The low nybl
specifies which math register the output should be written to, while
bits 4 and 5 indicate if, respectively, the low-half and high-half of
the result should be stored (multiplying two 32-bit values produces a
64-bit result, so we end up with enough data to fill two math
registers), bit 7 whether the unit performs addition/subtraction, or a
different function, and bit 6, whether the output value is latched
(more about this later).  Each of the 16 units can act as either an
adder (even units) or subtracter (odd units), or perform a
unit-specific calculation.  For example, function units 0 to 7 can
perform a multiplication.  The complete list of functions are:

| Unit | Function |
| === | === |
| 0 - 7 | Multiply |
| 8 | To be announced |
| 9 | To be announced |
| 10 | To be announced |
| 11 | To be announced |
| 12 | Barrel shifter |
| 13 | Barrel shifter |
| 14 | Divide |
| 15 | Divide |

Each math function typically takes just a few clock cycles to
complete, so that it is probable that by the time the last input value
has been provided, and the program begins to read the final results
out, they will already be ready.  (Precise timing data will be provided
when the design is finalised).

Returning to our Mandelbrot example, configuring to calculate a single
iteration thus requires writing 20 bytes into the math registers and
7*2 = 14 bytes into the configuration registers, for a total of 34
bytes.  Were additions and subtractions the only functions, this would
still compare favourably with implementing the code directly in
6502. With the presence of the multiplications, the advantage of the
math unit is tremendous.

Also, because each successive iteration of the
Mandelbrot calculation for a given pixel uses the same equation, and
the same x0 and y0 values, all we have to do is to copy the final
results back into math registers 0 and 1 (after temporarily stopping
the changing of those outputs, so that we don't have the new
half-updated inputs causing the results to change while they are being
copied). This requires setting two of the $D7Dx registers to clear the
output flags, then copying the 2*4 = 8 bytes of the math registers 12
and 13 into math registerse 0 and 1, and finally reactivating the
output of the calculation by updating those two $D7Dx registers
again.  Thus each successive iteration requires only 2 (stop output) +
2*4 (read outputs) + 2*4 (write them back into the inputs) + 2
(restart output) = 20 memory accesses, representing a nice
improvement.  However, we can do much better than this, for the
typical case where many iterations of the Mandelbrot calculation are
required per pixel.

To greatly speed up the calculation, we want to automate the copying
of the output results back into the input values.  Represented as a
spreadsheet, this simply means setting the inputs to the outputs of
the final calculation.  That is, we move the contents of cells A4 and
B4 into A1 and B1, so that the final output of the calculation is used
as its input:

|   | A | B | C | D |
| === | === | === | === | === |
| 1 | =A3+C1 | =D2+D1 | x0 | y0 |
| 2 | =A1*A1 | =B1*B1 | =A1*B1 | =A2*D3 |
| 3 | =A2-B2 | | | 2 |
| 4 | | | | |

If you try that in a regular spreadsheet program, you will get a
self-reference or cyclic-dependency error, because the result of the
system can no longer be statically calculated.  However, that is
exactly what we want here! All we have to do is to have a mechanism to
allow each iteration of the calculation to stabilise, before advancing
to the next. This is the purpose of the latch bit in the $D7Dx
configuration registers. When set, the output value of that math
functional unit is only updated periodically.  Exactly how often is
set by $D7E0, where a value of $00 means it is updated continuously,
and $FF means it is updated only every 255 math update cycles, each of
which take a few CPU cycles (exact timing will be provided when the
design is complete, but will be no more than 32 cycles in most cases,
and will quite likely be around 4 -- 8 cycles in the final design).  For
our Mandelbrot example, the calculation has three steps, so we would
need to set $D7E0 to a value of at least 3. A higher value won't hurt,
but will just slow things unnecessarily, but a lowe value will mean
that the calculation doesn't have time to complete all the steps, and
you will get incorrect outputs as a result.  If in doubt, set $D7E0 to
16, since that allows enough time for every math unit to depend on the
other 15.

With this arrangement, all we have to do is to have a loop that
watches the outputs to see if they go outside the maximum range
allowed for a mandelbrot pixel, and if so, to stop the
calculation. Because the colour of the pixel depends on the number of
iterations, we should keep track of the number of iterations, which we
can easily do by using an adder to implement a simple counter.  We can
also simplify the result checking by calculating the result of the
comparison (x*x + y*y < 2*2 ).  We already have x*x and y*y, so we
just need to add those together and subtract 4, i.e., 2*2. If the
result is positive, i.e., the most significant bit is clear, then the
calculation should stop. Thus our final spreadsheet should look like:

|   | A | B | C | D |
| === | === | === | === | === |
| 1 | =A3+C1 | =D2+D1 | x0 | y0 |
| 2 | =A1*A1 | =B1*B1 | =A1*B1 | =A2*D3 |
| 3 | =A2-B2 | =A2+B2 | 4 | 2 |
| 4 | =A4+B4 | 1 | =B3-C3 | |

Cell A4 implements the counter, by adding 1 to itself, and cell C3
will contain the result of the comparison. Note that because of
parallelism, this still takes only three steps, even though there are
now 10 calculations being performed.
(We could rearrange the layout of the spreadsheet
somewhat to make it more efficient to reload 
between successive pixels, however, we leave this as an exercise for
the reader.)

Calculating a Mandelbrot pixel now consists simply of initialising the
math unit, which requires a worse-case of 16 regiters * 32-bits + 16
math units * 2 bytes = 16*4 + 16*2 = 96 memory accesses.  Each
iteration will then proceed in three math cycles (currently 32 CPU
cycles each).  Thus it will be possible to perform approximately 1
million Mandelbrot iterations per second. That is, using the math
unit, the MEGA65 would be performing 4 32-bit multiplications in the
time of a single clock cycle on a C64, or a single typical instruction
on a C65!  (And don't forget that the final math unit architecture is
expected to be around four times faster than this).  Your challenge is
to find the most exciting ways to make use of this power.

XXX - Add example mandelbrot program listing.

XXX - Add more specific timing info.

XXX - Implement and document math interrupts, to allow the CPU to be
notified when a calculation is complete, and to halt the math unit.

XXX - Implement and document the remaining math function units.

XXX - Use flags to indicate internally changed values to speed up
cycles.

XXX - Use flags to indicate when convergence is complete, e.g., for
taylors series for common trig functions, where this makes sense.

XXX - Speed up math unit clock

XXX - Implement and add divider