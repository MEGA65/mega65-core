#!/usr/bin/env python3
import sys
sys.path.append("./vunit/")
from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Create library 'lib'
lib = vu.add_library("lib")

lib.add_source_files("dc_offset.vhdl")
lib.add_source_files("../src/vhdl/audio_mixer.vhdl")
lib.add_source_files("../src/vhdl/cputypes.vhdl")
lib.add_source_files("../src/vhdl/ghdl_ram32x1024_sync.vhdl")
lib.add_source_files("debugtools.vhdl")

# Run vunit function
vu.main()
