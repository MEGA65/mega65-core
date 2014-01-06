
 
 
 



 

window new WaveWindow  -name  "Waves for BMG Example Design"
waveform  using  "Waves for BMG Example Design"


      waveform add -signals /ram64x16k_tb/status
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/CLKA
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/ADDRA
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/DINA
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/WEA
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/DOUTA
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/CLKB
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/ADDRB
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/DINB
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/WEB
      waveform add -signals /ram64x16k_tb/ram64x16k_synth_inst/bmg_port/DOUTB
console submit -using simulator -wait no "run"
