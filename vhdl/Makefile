ROUTEEFFORT=	std
#ROUTEEFFORT=	med
#ROUTEEFFORT=	high

# Unlikely anyone uses Windows 9x anymore
ifeq ($(OS),Windows_NT)
SOCKLIBS = -l ws2_32
else
SOCKLIBS =
endif

kickstart.vhdl:
	( cd ../src ; make ../vhdl/kickstart.vhdl )

charrom.vhdl:
	( cd ../src ; make ../vhdl/charrom.vhdl )

version.vhdl:
	( cd ../src ; make ../vhdl/version.vhdl )

SIMULATIONFILES=	viciv.vhdl bitplanes.vhdl bitplane.vhdl cputypes.vhdl sid_voice.vhd sid_coeffs.vhd sid_filters.vhd sid_components.vhd version.vhdl kickstart.vhdl iomapper.vhdl container.vhd cpu_test.vhdl gs4510.vhdl UART_TX_CTRL.vhd uart_rx.vhdl uart_monitor.vhdl machine.vhdl cia6526.vhdl c65uart.vhdl keymapper.vhdl ghdl_ram8x32k.vhdl charrom.vhdl ghdl_chipram8bit.vhdl ghdl_screen_ram_buffer.vhdl ghdl_ram9x4k.vhdl ghdl_ram18x2k.vhdl sdcardio.vhdl ghdl_ram8x512.vhdl ethernet.vhdl ramlatch64.vhdl shadowram.vhdl cputypes.vhdl version.vhdl sid_6581.vhd ghdl_ram128x1k.vhdl ghdl_ram8x4096.vhdl crc.vhdl slowram.vhdl framepacker.vhdl ghdl_videobuffer.vhdl vicii_sprites.vhdl sprite.vhdl ghdl_alpha_blend.vhdl ghdl_farstack.vhdl debugtools.vhdl
simulate:	$(SIMULATIONFILES)
	ghdl -i $(SIMULATIONFILES) 
	ghdl -m cpu_test

testcia:	tb_cia.vhdl cia6526.vhdl debugtools.vhdl
	ghdl -c tb_cia.vhdl cia6526.vhdl debugtools.vhdl -r tb_cia

testadder:	tb_adder.vhdl debugtools.vhdl
	ghdl -c tb_adder.vhdl debugtools.vhdl -r tb_adder

clean:
	rm -f *.gise *.bgn *.bld *.cmd_log *.drc *.lso *.ncd *.ngc *.ngd *.ngr *.pad *.par *.pcf *.ptwx *.stx *.syr *.twr *.twx *.unroutes *.ut *.xpi *.xst *.xwbt
	rm -f *.map *.mrp *.psr *.xrpt *.csv *.list *.log *.xml
	rm -f container_summary.* container_usage.* usage_statistics_webtalk.* par_usage_statistics.*
	rm -f ipcore_dir/*.asy ipcore_dir/*.gise ipcore_dir/*.ncf ipcore_dir/*.sym ipcore_dir/*.xdc
	rm -f ipcore_dir/*.cgp ipcore_dir/*.txt ipcore_dir/*.log

cleangen:
	rm version.vhdl kickstart.vhdl charrom.vhdl
