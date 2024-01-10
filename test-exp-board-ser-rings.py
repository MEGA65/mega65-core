#!/bin/env python3

from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv(compile_builtins=False)
vu.add_vhdl_builtins()

# Create library 'lib'
lib = vu.add_library("lib")

lib.add_source_files("src/vhdl/tb_exp_board_serial_rings.vhdl");
lib.add_source_files("src/vhdl/debugtools.vhdl")
lib.add_source_files("src/vhdl/porttypes.vhdl")
lib.add_source_files("src/vhdl/cputypes.vhdl")
lib.add_source_files("src/vhdl/74LS595.vhdl")
lib.add_source_files("src/vhdl/74LS165.vhdl")
lib.add_source_files("src/vhdl/sim_exp_board_rings.vhdl")
lib.add_source_files("src/vhdl/exp_board_serial_rings.vhdl")

vu.set_compile_option("ghdl.a_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable"])

# Run vunit function
vu.main()
