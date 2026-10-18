Fetch physical memory with Python and pyserial, without waiting for a working
C64/C65 ROM or using `m65`'s mode detection:

```sh
python3 src/tools/monitor_memfetch.py 20000 40000 /tmp/mega65-rom.bin \
  --halt --log /tmp/mega65-rom-monitor.txt
```

The two addresses are hexadecimal and the end address is exclusive. This
example captures all 128 KiB at `$20000-$3FFFF` as raw binary. Unaligned ranges
and shorter reads also work. The monitor reads in units of 16 bytes, so avoid
unintentionally including I/O registers with read side effects.

The script selects a single FTDI serial device automatically. Use
`--port /dev/ttyUSB1` if several devices are connected. The default baud rate
is 2000000, with a three-second timeout for each command. Close `m65` or `cu`
before running it. Existing output and log files are never overwritten.

Without `--halt`, the CPU continues running. `--halt` pauses it for a consistent
capture and resumes it afterwards, including on transfer failure. This also
resumes a CPU that was already paused; use `--leave-halted` when it should stay
paused. Interrupting the script once also attempts to resume it. Neither mode
writes memory or issues SD commands. The transcript includes CPU registers and
all memory replies. A successful capture reports its byte count and SHA256;
after a failure, the output may be partial.

Protocol checks can be run without hardware or pyserial:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_monitor_memfetch.py -v
```
