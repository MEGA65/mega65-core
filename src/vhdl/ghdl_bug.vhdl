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

  signal audio_dma_0 : audio_dma_channel
    :=  (base_addr => to_unsigned(1234567,24),
         time_base => to_unsigned(0,24),
         top_addr => to_unsigned(0,16),
         volume => to_unsigned(0,8),
         enable => '0',
         repeat => '0',
         stop => '0',
         sample_width => "00",
         pending => '0',
         pending_msb => '0',
         current_addr => to_unsigned(0,24),
         current_addr_set => to_unsigned(0,24),
         current_addr_set_flag => '0',
         last_current_addr_set_flag => '0',
         timing_counter => to_unsigned(0,25),
         timing_counter_set => to_unsigned(0,25),
         timing_counter_set_flag => '0',
         last_timing_counter_set_flag => '0',
         
         sample_valid => '0',
         current_value => to_signed(0,16),
         multed => to_signed(0,25)
         );
    

  signal base_addr : unsigned(23 downto 0) := x"000000";

  
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
      report ""
        & "bare type=$" & to_hstring(base_addr)
        & ", embedded value=$" & to_hstring(audio_dma_0.base_addr)
        ;
      report ""
        & "bare type=%" & to_string(std_logic_vector(base_addr))
        & ", embedded value=%" & to_string(std_logic_vector(audio_dma_0.base_addr))
        ;
      report "The bare bits are "
        & std_logic'image(std_logic(base_addr(15)))
        & std_logic'image(std_logic(base_addr(14)))
        & std_logic'image(std_logic(base_addr(13)))
        & std_logic'image(std_logic(base_addr(12)))
        & std_logic'image(std_logic(base_addr(11)))
        & std_logic'image(std_logic(base_addr(10)))
        & std_logic'image(std_logic(base_addr(9)))
        & std_logic'image(std_logic(base_addr(8)))
        ;
      
      report "The wrapped bits are "
        & std_logic'image(std_logic(audio_dma_0.base_addr(15)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(14)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(13)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(12)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(11)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(10)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(9)))
        & std_logic'image(std_logic(audio_dma_0.base_addr(8)))
        ;
      


      -- Writing fixed values works
      audio_dma_0.base_addr(23 downto 16) <= x"42";
      -- Performing calculations on similar bare data types
--      base_addr <= 
      base_addr(15 downto 8) <= base_addr(15 downto 8) + 1;
      -- But if we try to do the same thing with an element in this type,
      -- it doesn't work.
      audio_dma_0.base_addr(15 downto 8) <= audio_dma_0.base_addr(15 downto 8) + 1;
      report "The calculated value is $" & to_hstring(audio_dma_0.base_addr(15 downto 8) + 1);
      
    end if;
  end process;  
  
end behavior;

