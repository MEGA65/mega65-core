library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_i2c is
end entity;

architecture foo of test_i2c is

  signal clock50mhz : std_logic := '1';

  signal hdmi_cs : std_logic := '0';
  signal hdmi_int : std_logic := '1';
  signal fastio_addr : unsigned(19 downto 0) := (others => '0');
  signal fastio_rdata : unsigned(7 downto 0) := (others => '0');
  signal fastio_wdata : unsigned(7 downto 0) := (others => '0');
  signal fastio_read : std_logic :='0';
  signal fastio_write : std_logic :='0';
  
  signal sda : std_logic := '1';
  signal scl : std_logic := '1';
  signal sda_last : std_logic := '1';
  signal scl_last : std_logic := '1';

  signal read_req : std_logic := '0';
  signal data_to_master : std_logic_vector(7 downto 0) := x"00";
  signal data_valid : std_logic := '0';
  signal data_from_master : std_logic_vector(7 downto 0) := x"00";
  signal next_value : integer := 0;

  signal touch_enabled : std_logic := '1';
  signal x_invert : std_logic := '1';
  signal y_invert : std_logic := '1';
  signal x_mult : unsigned(15 downto 0) := to_unsigned(2048,16);
  signal y_mult : unsigned(15 downto 0) := to_unsigned(2048,16);
  signal x_delta : unsigned(15 downto 0) := to_unsigned(0,16);
  signal y_delta : unsigned(15 downto 0) := to_unsigned(0,16);
    
    -- The touch events we have received
  signal touch1_active : std_logic := '0';
  signal touch1_status : std_logic_vector(1 downto 0) := "11";
  signal x1 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal y1 : unsigned(9 downto 0) := to_unsigned(0,10);

  signal touch2_active : std_logic := '0';
  signal touch2_status : std_logic_vector(1 downto 0) := "11";
  signal x2 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal y2 : unsigned(9 downto 0) := to_unsigned(0,10);
  
  constant dummy_x1 : integer := 678;
  constant dummy_y1 : integer := 432;
  constant dummy_x2 : integer := 321;
  constant dummy_y2 : integer := 123;

  signal cycle_counter : integer := 0;
  
  type dummy_data_t is array(0 to 15) of unsigned(7 downto 0);

  -- This is silly data for the HDMI I2C test, but it doesn't really matter.
  -- What is important is that we see whether we can read the registers or not.
  signal dummy_touch_event : dummy_data_t
    := ( x"12",x"34",x"56",x"78",x"04",x"05",x"06",x"07",
         x"08",x"09",x"0a",x"0b",x"0c",x"0d",x"0e",x"0f"      
      );
  
begin

  i2c2: entity work.hdmi_i2c port map (
    clock => clock50mhz,
    cs => hdmi_cs,

    hdmi_int => hdmi_int,
    
    sda => sda,
    scl => scl,
    
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata
    
    );
  
 
  i2cslave: entity work.i2c_slave
    generic map (
      SLAVE_ADDR => "0111101" -- $7A/2 for ADV7511
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

    cycle_counter <= cycle_counter + 1;
    
  end process;

  -- Implement simulated I2C slave
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then

      case cycle_counter is
        when 2000000 =>
          report "@CYCLE " & integer'image(cycle_counter) & ": " &
            "Power up";
          hdmi_int <= '1';
          hdmi_cs <= '0';
          fastio_read <= '0';
          fastio_write <= '0';
        when 2000100 =>
          report "@CYCLE " & integer'image(cycle_counter) & ": " &
            "HDMI interrupt";
          hdmi_int <= '0';
          hdmi_cs <= '0';
          fastio_read <= '0';
          fastio_write <= '0';
        when 101 =>
          report "@CYCLE " & integer'image(cycle_counter) & ": " &
            "HDMI interrupt end";
          hdmi_int <= '1';
          hdmi_cs <= '0';
          fastio_read <= '0';
          fastio_write <= '0';
        when 1000000 =>
          report "@CYCLE " & integer'image(cycle_counter) & ": " &
            "Write request";
          fastio_write <= '1';
          hdmi_cs <= '1';
          fastio_addr <= x"00099";
          fastio_wdata <= x"86";
        when 1000001 =>
          report "@CYCLE " & integer'image(cycle_counter) & ": " &
            "Write done";
          hdmi_cs <= '0';
          fastio_write <= '0';
        when others =>
          null;
      end case;
      
      if read_req = '1' then
        -- data_to_master <= std_logic_vector(to_unsigned(next_value,8));
        if next_value < 16 then
          report "Providing dummy value $" & to_hstring(dummy_touch_event(next_value)) & " for value of reg $"
            & to_hstring(to_unsigned(next_value,8));
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
--        report "SDA=" & std_logic'image(sda) &
--          ", SCL=" & std_logic'image(scl);
      end if;  
    end if;
  end process;

end foo;
