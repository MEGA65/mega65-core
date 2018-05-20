library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_i2c is
end entity;

architecture foo of test_i2c is

  signal clock50mhz : std_logic := '1';

  signal i2c0_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c0_address_internal : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c0_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_busy : std_logic := '0';
  signal i2c0_busy_last : std_logic := '0';
  signal i2c0_rw : std_logic := '0';
  signal i2c0_rw_internal : std_logic := '0';
  signal i2c0_error : std_logic := '0';  
  signal i2c0_reset : std_logic := '1';
  signal i2c0_reset_internal : std_logic := '1';
  signal i2c0_command_en : std_logic := '0';  
  signal i2c0_command_en_internal : std_logic := '0';  

  signal sda : std_logic := '1';
  signal scl : std_logic := '1';
  signal sda_last : std_logic := '1';
  signal scl_last : std_logic := '1';

  signal last_busy : std_logic := '1';
  signal busy_count : integer := 0;

  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 15) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal touch_enabled : std_logic := '1';

  signal read_req : std_logic := '0';
  signal data_to_master : std_logic_vector(7 downto 0) := x"00";
  signal data_valid : std_logic := '0';
  signal data_from_master : std_logic_vector(7 downto 0) := x"00";
  signal next_value : integer := 0;
  
begin


  i2c0: entity work.i2c_master
    port map (
      clk => clock50mhz,
      reset_n => i2c0_reset,
      ena => i2c0_command_en,
      addr => std_logic_vector(i2c0_address),
      rw => i2c0_rw,
      data_wr => std_logic_vector(i2c0_wdata),
      busy => i2c0_busy,
      unsigned(data_rd) => i2c0_rdata,
      ack_error => i2c0_error,
      sda => sda,
      scl => scl
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

  -- Implement simulated I2C slave
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      if read_req = '1' then
        data_to_master <= std_logic_vector(to_unsigned(next_value,8));
        next_value <= next_value + 1;
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

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      if i2c0_busy /= 'U' then
        last_busy <= i2c0_busy;
      end if;
--      report "busy=" & std_logic'image(i2c0_busy) & "last_busy = " & std_logic'image(last_busy);
      if i2c0_busy='0' and last_busy='1' then
        report "busy de-asserted: dispatching next command";
        busy_count <= busy_count + 1;
        case busy_count is
          when 0 =>
            if touch_enabled='1' then
              report "Beginning touch panel scan";
              -- send initial command
              i2c0_command_en <= '1';
              i2c0_address <= "0111000";  -- 0x70 = I2C address of touch panel
              -- Write register zero to set starting point for read
              i2c0_wdata <= x"00";
              i2c0_rw <= '0';
            else
              busy_count <= 0;
            end if;
          when 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 =>
            if i2c0_error='1' then
              i2c0_command_en <= '0';
              busy_count <= 0;
              report "I2C error: Restarting job.";
            else
              i2c0_rw <= '1';
              i2c0_command_en <= '1';
            end if;
            if busy_count>3 then
              report "Setting byte(" & integer'image(busy_count - 4) & ") to $" & to_hstring(i2c0_rdata);
              bytes(busy_count - 4) <= i2c0_rdata;
            end if;
          when others =>
            report "Setting byte(" & integer'image(busy_count - 4) & ") to $" & to_hstring(i2c0_rdata);
            bytes(busy_count - 4) <= i2c0_rdata;
            i2c0_command_en <= '0';
            busy_count <= 0;
        end case;
      end if;
    end if;
  end process;  
  
end foo;
