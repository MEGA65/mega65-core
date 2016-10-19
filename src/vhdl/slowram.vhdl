library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

--
entity slowram is
  port (address : in std_logic_vector(26 downto 0);
        datain : in std_logic_vector(7 downto 0);
        request_toggle : in std_logic;
        done_toggle : out std_logic := '0';
        cache_address : in std_logic_vector(8 downto 0);
        we : in std_logic;
        cache_read_data : out std_logic_vector(150 downto 0)
        );
end slowram;

architecture Behavioral of slowram is
  signal last_request_toggle : std_logic := '0';
  -- 128MB RAM
  -- 128*1MB-1 = 134217727
  -- But 128MB RAM here causes GHDL 0.31 to segfault, so just 1MB
  type ram_t is array (0 to 1048575) of std_logic_vector(7 downto 0);

  signal read_data : std_logic_vector(127 downto 0);
  signal cache_read_data_internal : std_logic_vector(150 downto 0);
begin
  --process for read and write operation.
  PROCESS(request_toggle)
    variable ddr_ram : ram_t; -- := (    
--    others => x"ee"
--    );
  BEGIN
    -- XXX : Slowram model does nothing but acknowledge requests
    -- report "DDR: request_toggle = " & std_logic'image(request_toggle);
    if request_toggle /= last_request_toggle then
      report "DDR: Saw request from CPU";
      done_toggle <= request_toggle;
      last_request_toggle <= request_toggle;

      if we='1' then
        report "DDR: write $" & to_hstring(unsigned(datain))
          & " to address " & integer'image(to_integer(unsigned(address)));
        ddr_ram(to_integer(unsigned(address(19 downto 0)))) := datain;
      end if;

      -- Simulate horrible DDR RAM latency

      
      
      -- Cache line read address
      cache_read_data_internal(150 downto 128) <= address(26 downto 4);

      -- Cache line read data
      for i in 0 to 15 loop
        cache_read_data_internal((i*8+7) downto (i*8))
          <= ddr_ram(to_integer(unsigned(address(19 downto 4)))*16+i);
        read_data((i*8+7) downto (i*8))
          <= ddr_ram(to_integer(unsigned(address(19 downto 4)))*16+i);
      end loop;
      report "DDR: cache data read for " &
        integer'image(to_integer(unsigned(address(19 downto 4)))*16)
        & " is: $"
        & to_hstring(unsigned(read_data(127 downto 0)));
    end if;
  END PROCESS;

  PROCESS
  begin
    while (true) loop
      wait for 200 ns;
      cache_read_data <= cache_read_data_internal;
      report "DDR: RAM output updated";
    end loop;
  end process;

  
end Behavioral;
