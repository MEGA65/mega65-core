#!/usr/bin/env python3
import sys
sys.path.append("./vunit/")
from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Create library 'lib'
lib = vu.add_library("lib")

# Add all files ending in .vhd in current working directory to library
lib.add_source_files("hardware_divider.vhdl")
lib.add_source_files("../src/vhdl/fast_divide.vhdl")
lib.add_source_files("debugtools.vhdl")

# Run vunit function
vu.main()
