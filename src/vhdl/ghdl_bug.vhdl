library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;

entity ghdl_bug is
  
end ghdl_bug;

architecture behavior of ghdl_bug is
  
  signal pixelclock : std_logic := '1';
  signal cpuclock : std_logic := '1';
  signal clock27 : std_logic := '1';
  signal clock100 : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';
  signal reset : std_logic := '0';

  signal audio_dma_0 : audio_dma_channel;
  
begin

  process
  begin  -- process tb
    report "beginning simulation" severity note;

    wait for 3 ns;
    
    for i in 1 to 2000000 loop

    clock325 <= '0';
    pixelclock <= '0';
    cpuclock <= '0';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '0';
    cpuclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;
      
      if i = 10 then
        reset <= '1';
        report "Releasing reset";
      end if;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then
      report "Audio DMA channel_0 : "
        & "base=$" & to_hstring(audio_dma_0.base_addr)
        & ", top_addr=$" & to_hstring(audio_dma_0.top_addr)
        & ", timebase=$" & to_hstring(audio_dma_0.time_base)
        & ", current_addr=$" & to_hstring(audio_dma_0.current_addr)
        & ", timing_counter=$" & to_hstring(audio_dma_0.timing_counter)
        ;
      audio_dma_0.base_addr(15 downto 8) <= audio_dma_0.base_addr(15 downto 8) + 1;
      audio_dma_0.base_addr(23 downto 16) <= x"42";
      
--      report "PCM digital audio out = " & std_logic'image(pcm_modem1_data_out);
    end if;
  end process;  
  
end behavior;

