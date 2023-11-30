#!/bin/env python3

from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Create library 'lib'
lib = vu.add_library("lib")

lib.add_source_files("src/vhdl/tb_r5_i2c.vhdl");
lib.add_source_files("src/vhdl/i2c_master.vhdl");
lib.add_source_files("src/vhdl/i2c_slave_frank_buss.vhdl");
lib.add_source_files("src/vhdl/pca9555.vhdl");
lib.add_source_files("src/vhdl/debounce.vhdl");
lib.add_source_files("src/vhdl/mega65r5_board_i2c.vhdl");
lib.add_source_files("src/vhdl/debugtools.vhdl")
lib.add_source_files("src/vhdl/cputypes.vhdl")

vu.set_compile_option("ghdl.a_flags", ["-frelaxed-rules"])
vu.set_compile_option("ghdl.flags", ["-frelaxed-rules"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed-rules"])
vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable"])

# Run vunit function
vu.main()
