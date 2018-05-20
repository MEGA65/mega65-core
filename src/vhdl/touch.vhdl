library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity touch is
  port (
    clock50mhz : in std_logic;
    sda : inout std_logic;
    scl : inout std_logic;
    touch_enabled : in std_logic := '1';

    -- Calibration settings
    -- XXX Doesn't cater for non-linearity, which we do see in
    -- the horizontal axis.
    x_invert : in std_logic := '0';
    y_invert : in std_logic := '0';
    x_mult : in unsigned(15 downto 0) := to_unsigned(2048,16);
    y_mult : in unsigned(15 downto 0) := to_unsigned(2048,16);
    x_delta : in unsigned(15 downto 0) := to_unsigned(0,16);
    y_delta : in unsigned(15 downto 0) := to_unsigned(0,16);
    
    -- The touch events we have received
    touch1_active : out std_logic := '0';
    touch1_status : out std_logic_vector(1 downto 0) := "11";
    x1 : out unsigned(9 downto 0) := to_unsigned(0,10);
    y1 : out unsigned(9 downto 0) := to_unsigned(0,10);

    touch2_active : out std_logic := '0';
    touch2_status : out std_logic_vector(1 downto 0) := "11";
    x2 : out unsigned(9 downto 0) := to_unsigned(0,10);
    y2 : out unsigned(9 downto 0) := to_unsigned(0,10)
    
    );
end entity;

architecture foo of touch is

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

  signal last_busy : std_logic := '1';
  signal busy_count : integer := 0;

  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 15) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal parse_touch : integer := 0;

  signal x1_int : integer := 0;
  signal x2_int : integer := 0;
  signal y1_int : integer := 0;
  signal y2_int : integer := 0;

  signal x1_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal x2_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal y1_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal y2_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  
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

  process (clock50mhz) is
    variable r : unsigned(15 downto 0) := to_unsigned(0,16);
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
            parse_touch <= 1;
        end case;
      end if;

      case parse_touch is
        when 0 =>
          -- No touch event to parse
          null;
        when 1 =>
          -- Begin parsing
          report "There are " & integer'image(to_integer(bytes(2))) & " touch events: $"
            & to_hstring(bytes(3+2)(7 downto 4)) & " & $"
            & to_hstring(bytes(9+2)(7 downto 4));
            
          if bytes(2) /= x"00" and bytes(3+2)(7 downto 4) /= x"f" then
            if bytes(3+2)(7 downto 4) = "0001" then
              touch1_status <= std_logic_vector(bytes(3+0)(7 downto 6));
              report "Setting x1_int to $" & to_hstring(bytes(3+2)(3 downto 0) & bytes(3+3));
              x1_int <= to_integer(bytes(3+2)(3 downto 0) & bytes(3+3));
              y1_int <= to_integer(bytes(3+0)(3 downto 0) & bytes(3+1));
            elsif bytes(3+2)(7 downto 4) = "0010" then
              touch2_status <= std_logic_vector(bytes(3+0)(7 downto 6));
              report "Setting x2_int to $" & to_hstring(bytes(3+2)(3 downto 0) & bytes(3+3));
              x2_int <= to_integer(bytes(3+2)(3 downto 0) & bytes(3+3));
              y2_int <= to_integer(bytes(3+0)(3 downto 0) & bytes(3+1));
            end if;
          end if;

          if bytes(2) > x"01" and bytes(9+2)(7 downto 4) /= x"f" then
            if bytes(9+2)(7 downto 4) = "0001" then
              report "Setting x1_int to $" & to_hstring(bytes(9+2)(3 downto 0) & bytes(9+3));
              touch1_status <= std_logic_vector(bytes(9+0)(7 downto 6));
              x1_int <= to_integer(bytes(9+2)(3 downto 0) & bytes(9+3));
              y1_int <= to_integer(bytes(9+0)(3 downto 0) & bytes(9+1));
            elsif bytes(9+2)(7 downto 4) = "0010" then
              report "Setting x2_int to $" & to_hstring(bytes(9+2)(3 downto 0) & bytes(9+3));
              touch2_status <= std_logic_vector(bytes(9+0)(7 downto 6));
              x2_int <= to_integer(bytes(9+2)(3 downto 0) & bytes(9+3));
              y2_int <= to_integer(bytes(9+0)(3 downto 0) & bytes(9+1));
            end if;
          end if;
          parse_touch <= 2;
        when 2 =>
          parse_touch <= 3;
        when 3 =>
          parse_touch <= 0;          
          
        when others =>
          parse_touch <= 0;
      end case;

      if parse_touch = 3 then
        -- We ignore the MSB, so that it is possible for the multiplier to
        -- both scale up and down versus the input from the panel
        report "touch point 1 ="
          & " " & to_hstring(bytes(3))
          & " " & to_hstring(bytes(4))
          & " " & to_hstring(bytes(5))
          & " " & to_hstring(bytes(6))
          & " " & to_hstring(bytes(7))
          & " " & to_hstring(bytes(8));
      end if;
      
      x1_mult <= to_unsigned(x1_int * to_integer(x_mult),12+16)(26 downto 11);
      x2_mult <= to_unsigned(x2_int * to_integer(x_mult),12+16)(26 downto 11);
      y1_mult <= to_unsigned(y1_int * to_integer(y_mult),12+16)(26 downto 11);
      y2_mult <= to_unsigned(y2_int * to_integer(y_mult),12+16)(26 downto 11);
      
      r := x1_mult + x_delta; x1 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled x1 = ( (" & integer'image(x1_int)
          & " * " & integer'image(to_integer(x_mult))
          & ") >> 11) + " & integer'image(to_integer(x_delta))
          & " = " & integer'image(to_integer(r));
      end if;
      r := y1_mult + y_delta; y1 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled y1 = ( (" & integer'image(y1_int)
          & " * " & integer'image(to_integer(y_mult))
          & ") >> 11) + " & integer'image(to_integer(y_delta))
          & " = " & integer'image(to_integer(r));
      end if;
      r := x2_mult + x_delta; x2 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled x2 = ( (" & integer'image(x2_int)
          & " * " & integer'image(to_integer(x_mult))
          & ") >> 11) + " & integer'image(to_integer(x_delta))
          & " = " & integer'image(to_integer(r));
      end if;
      r := y2_mult + y_delta; y2 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled y2 = ( (" & integer'image(y2_int)
          & " * " & integer'image(to_integer(y_mult))
          & ") >> 11) + " & integer'image(to_integer(y_delta))
          & " = " & integer'image(to_integer(r));
      end if;


      
    end if;
  end process;  
  
end foo;
