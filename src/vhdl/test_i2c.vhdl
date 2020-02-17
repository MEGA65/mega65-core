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

  touch0: entity work.touch
    port map (
      clock50mhz => clock50mhz,
      sda => sda,
      scl => scl,
      touch_enabled => touch_enabled,

      x_invert => x_invert,
      y_invert => y_invert,
      x_mult => x_mult,
      y_mult => y_mult,

      touch1_active => touch1_active,
      touch1_status => touch1_status,
      x1 => x1,
      y1 => y1,

      touch2_active => touch2_active,
      touch2_status => touch2_status,
      x2 => x2,
      y2 => y2
      );
 
  i2cslave: entity work.i2c_slave
    generic map (
      SLAVE_ADDR => "0111000"
      )
    port map (
      scl => scl,
      sda => sda,
      clk => clock50mhz,
      rst => '0',
      read_req => read_req,
      data_to_master => data_to_master,
      data_valid => data_valid,
      data_from_master => data_from_master);

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
