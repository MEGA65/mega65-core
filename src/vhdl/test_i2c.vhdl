library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_i2c is
end entity;

architecture foo of test_i2c is

  signal clock50mhz : std_logic := '1';

  signal sda : std_logic := '1';
  signal scl : std_logic := '1';
  signal sda_last : std_logic := '1';
  signal scl_last : std_logic := '1';

  type dummy_data_t is array(0 to 15) of unsigned(7 downto 0);
  
  signal dummy_touch_event : dummy_data_t
    := (
      0 => x"00", -- Not factory test mode
      1 => x"00", -- recognised gesture (always 0 it seems)
      2 => x"02", -- number of touch events

      -- Touch event 1:
      3 => "00" & "00" & to_unsigned(dummy_y1/256,4), -- touch is being held,
                                                      -- 2 unused bits,
                                                      -- MSB of Y position
      4 => to_unsigned(dummy_y1 mod 256,8),           -- LSB of Y position
      5 => to_unsigned(1,4) & to_unsigned(dummy_x1/256,4), -- touch ID
                                                      -- MSB of X position
      6 => to_unsigned(dummy_x1 mod 256,8),           -- LSB of X position
      7 => x"00", -- touch pressure (unused?)
      8 => x"00", -- touch area (unused?)

      -- Touch event 2:
      9 => "00" & "00" & to_unsigned(dummy_y2/256,4), -- touch is being held,
                                                      -- 2 unused bits,
                                                      -- MSB of Y position
     10 => to_unsigned(dummy_y2 mod 256,8),           -- LSB of Y position
     11 => to_unsigned(2,4) & to_unsigned(dummy_x2/256,4), -- touch ID
                                                      -- MSB of X position
     12 => to_unsigned(dummy_x2 mod 256,8),           -- LSB of X position
     13 => x"00", -- touch pressure (unused?)
      14 => x"00", -- touch area (unused?)

      -- Extra item so we don't overrun
    15 => x"FF"
      );
  
begin

  i2c1: entity work.mega65r2_i2c port map (
    clock => clock50mhz,
    cs => '1',
    
    sda => sda,
    scl => scl,
    
    fastio_addr => to_unsigned(16+16,20),
    fastio_write => '1',
    fastio_read => '0',
    fastio_wdata => x"42"
--    std_logic_vector(fastio_rdata) => data_o
    
    );
  
  
  process is
  begin
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;
      
    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;
      
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      if read_req = '1' then
        -- data_to_master <= std_logic_vector(to_unsigned(next_value,8));
        if next_value < 16 then
          data_to_master <= std_logic_vector(dummy_touch_event(next_value));
        else
          data_to_master <= x"bd";
        end if;
        next_value <= next_value + 1;
      elsif data_valid='1' then
        -- write address to read from
        next_value <= to_integer(unsigned(data_from_master));
      end if;
    end if;
  end process;
  
  
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      sda_last <= sda;
      scl_last <= scl;
      if sda /= sda_last or scl /= scl_last then
        report "SDA=" & std_logic'image(sda) &
          ", SCL=" & std_logic'image(scl);
      end if;  
    end if;
  end process;

end foo;
