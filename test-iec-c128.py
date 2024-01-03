#!/bin/env python3

from vunit import VUnit

# Create VUnit instance by parsing command line arguments
vu = VUnit.from_argv(compile_builtins=False)
vu.add_vhdl_builtins()

# Create library 'lib'
lib = vu.add_library("lib")

lib.add_source_files("src/vhdl/tb_iec_serial_1581.vhdl");
lib.add_source_files("src/vhdl/iec_serial.vhdl");
lib.add_source_files("src/vhdl/debugtools.vhdl")
lib.add_source_files("src/vhdl/cputypes.vhdl")
lib.add_source_files("src/vhdl/victypes.vhdl")
lib.add_source_files("src/vhdl/ghdl_ram8x4096_sync.vhdl")
lib.add_source_files("src/vhdl/internal1581.vhdl")
lib.add_source_files("src/vhdl/dpram8x4096.vhdl")
lib.add_source_files("src/vhdl/driverom1581.vhdl")
lib.add_source_files("src/vhdl/simple_cpu6502.vhdl")
lib.add_source_files("src/vhdl/cia6526.vhdl")

vu.set_compile_option("ghdl.a_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed-rules","-fsynopsys"])
vu.set_sim_option("ghdl.sim_flags", ["--ieee-asserts=disable"])

# Run vunit function
vu.main()
