#!/bin/env python3

from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv(compile_builtins=False)
vu.add_vhdl_builtins()

# Create library 'lib'
lib = vu.add_library("lib")

lib.add_source_files("src/vhdl/tb_sdcard.vhdl");
lib.add_source_files("src/vhdl/debugtools.vhdl")
lib.add_source_files("src/vhdl/cputypes.vhdl")
lib.add_source_files("src/vhdl/victypes.vhdl")
lib.add_source_files("src/vhdl/sdcardio.vhdl")
lib.add_source_files("src/vhdl/ghdl_ram8x4096_sync.vhdl")
lib.add_source_files("src/vhdl/mfm_decoder.vhdl")
lib.add_source_files("src/vhdl/mfm_gaps.vhdl")
lib.add_source_files("src/vhdl/mfm_bits_to_bytes.vhdl")
lib.add_source_files("src/vhdl/mfm_bits_to_gaps.vhdl")
lib.add_source_files("src/vhdl/rll27_bits_to_gaps.vhdl")
lib.add_source_files("src/vhdl/raw_bits_to_gaps.vhdl")
lib.add_source_files("src/vhdl/mfm_gaps_to_bits.vhdl")
lib.add_source_files("src/vhdl/mfm_quantise_gaps.vhdl")
lib.add_source_files("src/vhdl/rll27_gaps_to_bits.vhdl")
lib.add_source_files("src/vhdl/rll27_quantise_gaps.vhdl")
lib.add_source_files("src/vhdl/crc1581.vhdl")

vu.set_compile_option("ghdl.a_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable"])

# Run vunit function
vu.main()
