#!/bin/env python3

from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv()

# Create library 'lib'
lib = vu.add_library("lib")

# Add all files ending in .vhd in current working directory to library
lib.add_source_files("src/vhdl/tb_pixel_driver.vhdl")
lib.add_source_files("src/vhdl/kb_matrix_ram.vhdl")
lib.add_source_files("src/vhdl/debugtools.vhdl")
lib.add_source_files("src/vhdl/mega65kbd_to_matrix.vhdl")
lib.add_source_files("i2c_slave/rtl/vhdl/*.vhdl")
lib.add_source_files("src/vhdl/pixel_driver.vhdl")
lib.add_source_files("src/vhdl/frame_generator.vhdl")
lib.add_source_files("src/vhdl/ghdl_ram32x1024_sync.vhdl")

vu.set_compile_option("ghdl.a_flags", ["-frelaxed-rules"])
vu.set_compile_option("ghdl.flags", ["-frelaxed-rules"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed-rules"])
vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable"])

# Run vunit function
vu.main()
