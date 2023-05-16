library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity touch is
  generic ( clock_frequency : integer );
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


    scan_count : inout unsigned(7 downto 0) := x"00";
    b0 : out unsigned(7 downto 0) := x"00";
    b1 : out unsigned(7 downto 0) := x"00";
    b2 : out unsigned(7 downto 0) := x"00";
    b3 : out unsigned(7 downto 0) := x"00";
    b4 : out unsigned(7 downto 0) := x"00";
    b5 : out unsigned(7 downto 0) := x"00";
    touch_byte : out unsigned(7 downto 0) := x"BD";
    touch_byte_num : in unsigned(7 downto 0);

    gesture_event_id : out unsigned(3 downto 0) := x"0";
    gesture_event : out unsigned(3 downto 0) := x"0";
    gesture_timeout_out : out unsigned(7 downto 0) := x"00";
    
    -- The touch events we have received
    touch1_active : buffer std_logic := '0';
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

  signal x1_inv : integer := 0;
  signal x2_inv : integer := 0;
  signal y1_inv : integer := 0;
  signal y2_inv : integer := 0;

  signal x1_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal x2_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal y1_mult : unsigned(15 downto 0) := to_unsigned(0,16);
  signal y2_mult : unsigned(15 downto 0) := to_unsigned(0,16);

  signal touch1_active_internal : std_logic := '0';
  signal touch2_active_internal : std_logic := '0';

  signal gesture_directions : std_logic_vector(3 downto 0) := "0000";
  signal gesture_timeout : integer range 0 to 50000000 := 0;
  signal gesture_start_x : integer := 0;
  signal gesture_start_y : integer := 0;
  signal gesture_last_x : integer := 0;
  signal gesture_last_y : integer := 0;
  signal gesture_next_event_id : integer range 0 to 15 := 1;
  
begin


  i2c0: entity work.i2c_master
    generic map ( input_clk => clock_frequency )
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

      if i2c0_error = '0' and touch_enabled='1' then
        last_busy <= i2c0_busy;
      else
        last_busy <= '1';
      end if;
      
--      report "busy=" & std_logic'image(i2c0_busy) & "last_busy = " & std_logic'image(last_busy);

      touch1_active <= touch1_active_internal;
      touch2_active <= touch2_active_internal;

      if touch1_active = '1' and touch1_active_internal='0' then
        -- Start of touch.
        -- We want to keep track of direction of travel and magnitude
        -- so that we can detect various gestures

        if x1_int < 55 and y1_int >= 500 then
          -- Touch in bottom left corner, indicate event
          gesture_event_id <= to_unsigned(gesture_next_event_id,4);
          gesture_event <= "0011";  -- bottom left touch
          if gesture_next_event_id /= 15 then
            gesture_next_event_id <= gesture_next_event_id + 1;
          else
            gesture_next_event_id <= 0;
          end if;          
        end if;
        
        gesture_directions <= "1111";
        gesture_start_x <= x1_int;
        gesture_start_y <= y1_int;
        gesture_last_x <= x1_int;
        gesture_last_y <= y1_int;        
        -- Gesture must complete in <0.5 seconds
        gesture_timeout <= 25000000;
      elsif touch1_active_internal='1' then
        -- Touch being held, so track gesture
        if x1_int < gesture_last_x then
          gesture_directions(1) <= '0';
        end if;
        if x1_int > gesture_last_x then
          gesture_directions(0) <= '0';
        end if;
        if y1_int < gesture_last_y then
          gesture_directions(3) <= '0';
        end if;
        if y1_int > gesture_last_y then
          gesture_directions(2) <= '0';
        end if;        
        gesture_last_x <= x1_int;
        gesture_last_y <= y1_int;
      elsif touch1_active_internal='1' and touch1_active = '0'  and gesture_timeout /= 0 then
        -- Touch release within gesture timeout
        gesture_event_id <= to_unsigned(gesture_next_event_id,4);
        if gesture_next_event_id /= 15 then
          gesture_next_event_id <= gesture_next_event_id + 1;
        else
          gesture_next_event_id <= 0;
        end if;
        if gesture_directions(0)='1' and (gesture_start_x - gesture_last_x ) > 100 then
          gesture_event(0) <= '1';
        else
          gesture_event(0) <= '0';
        end if;
        if gesture_directions(1)='1' and (gesture_last_x - gesture_start_x ) > 100 then
          gesture_event(1) <= '1';
        else
          gesture_event(1) <= '0';
        end if;
        if gesture_directions(2)='1' and (gesture_start_y - gesture_last_y ) > 100 then
          gesture_event(2) <= '1';
        else
          gesture_event(2) <= '0';
        end if;
        if gesture_directions(3)='1' and (gesture_last_y - gesture_start_y ) > 100 then
          gesture_event(3) <= '1';
        else
          gesture_event(3) <= '0';
        end if;
      end if;

      if gesture_timeout /= 0 then
        gesture_timeout <= gesture_timeout - 1;
      end if;
      gesture_timeout_out <= to_unsigned(gesture_timeout,8);      
      
      -- Cycle through reading the touch digitiser registers
      if touch_enabled = '0' then
        busy_count <= 0;
      end if;
      if i2c0_busy='0' and last_busy='1' then
--        report "busy de-asserted: dispatching next command";
         case busy_count is
          when 0 =>
            if touch_enabled='1' then
--              report "Beginning touch panel scan";
              -- send initial command
              i2c0_command_en <= '1';
              i2c0_address <= "0111000";  -- 0x70 = I2C address of touch panel
              -- Write register zero to set starting point for read
              i2c0_wdata <= x"00";
              i2c0_rw <= '0';
              busy_count <= busy_count + 1;
            else
              busy_count <= 0;
            end if;
          when 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 =>
            busy_count <= busy_count + 1;
            i2c0_rw <= '1';
            i2c0_command_en <= '1';
            if busy_count > 2 and busy_count < 18 then
--              report "Setting byte(" & integer'image(busy_count - 2) & ") to $" & to_hstring(i2c0_rdata);
              bytes(busy_count - 2) <= i2c0_rdata;
            end if;
          when others =>
            if busy_count > 2 and busy_count < 18 then
--              report "Setting byte(" & integer'image(busy_count - 2) & ") to $" & to_hstring(i2c0_rdata);
              bytes(busy_count - 2) <= i2c0_rdata;
            end if;
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
          report "There are " & integer'image(safe_to_integer(bytes(2))) & " touch events: $"
            & to_hstring(bytes(3+2)(7 downto 4)) & " & $"
            & to_hstring(bytes(9+2)(7 downto 4));

          if scan_count /= x"ff" then
            scan_count <= scan_count + 1;
          else
            scan_count <= x"00";
          end if;

          touch1_active_internal <= '0';
          touch2_active_internal <= '0';
          
          if safe_to_integer(bytes(2)) /= 0 and safe_to_integer(bytes(3+2)(7 downto 4)) /= 15 then
            if bytes(3+2)(7 downto 4) = "0000" then
              touch1_active_internal <= not std_logic(bytes(3+0)(6));
              touch1_status <= std_logic_vector(bytes(3+0)(7 downto 6));
              report "Setting x1_int to $" & to_hstring(bytes(3+2)(3 downto 0) & bytes(3+3));
              x1_int <= safe_to_integer(bytes(3+2)(3 downto 0) & bytes(3+3));
              y1_int <= safe_to_integer(bytes(3+0)(3 downto 0) & bytes(3+1));
            elsif bytes(3+2)(7 downto 4) = "0001" then
              touch2_active_internal <= not std_logic(bytes(3+0)(6));
              touch2_status <= std_logic_vector(bytes(3+0)(7 downto 6));
              report "Setting x2_int to $" & to_hstring(bytes(3+2)(3 downto 0) & bytes(3+3));
              x2_int <= safe_to_integer(bytes(3+2)(3 downto 0) & bytes(3+3));
              y2_int <= safe_to_integer(bytes(3+0)(3 downto 0) & bytes(3+1));
            end if;
          end if;

          if safe_to_integer(bytes(2)) > 1 and safe_to_integer(bytes(9+2)(7 downto 4)) /= 15 then
            if bytes(9+2)(7 downto 4) = "0000" then
              report "Setting x1_int to $" & to_hstring(bytes(9+2)(3 downto 0) & bytes(9+3));
              touch1_active_internal <= not std_logic(bytes(9+0)(6));
              touch1_status <= std_logic_vector(bytes(9+0)(7 downto 6));
              x1_int <= safe_to_integer(bytes(9+2)(3 downto 0) & bytes(9+3));
              y1_int <= safe_to_integer(bytes(9+0)(3 downto 0) & bytes(9+1));
            elsif bytes(9+2)(7 downto 4) = "0001" then
              report "Setting x2_int to $" & to_hstring(bytes(9+2)(3 downto 0) & bytes(9+3));
              touch2_active_internal <= not std_logic(bytes(9+0)(6));
              touch2_status <= std_logic_vector(bytes(9+0)(7 downto 6));
              x2_int <= safe_to_integer(bytes(9+2)(3 downto 0) & bytes(9+3));
              y2_int <= safe_to_integer(bytes(9+0)(3 downto 0) & bytes(9+1));
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

      if x_invert = '1' then
        x1_inv <= 800 - x1_int;
        x2_inv <= 800 - x2_int;
      else
        x1_inv <= x1_int;
        x2_inv <= x2_int;
      end if;
      
      if y_invert = '1' then
        y1_inv <= 500 - y1_int;
        y2_inv <= 500 - y2_int;
      else
        y1_inv <= y1_int;
        y2_inv <= y2_int;
      end if;

      if safe_to_integer(touch_byte_num) < 15 then
        touch_byte <= bytes(safe_to_integer(touch_byte_num));
      else
        touch_byte <= x"EE";
      end if;
      b0 <= bytes(0);
      b1 <= bytes(1);
      b2 <= bytes(2);
      b3 <= bytes(3);
      b4 <= bytes(4);
      b5 <= bytes(5);
      
      x1_mult <= to_unsigned(x1_inv * safe_to_integer(x_mult),12+16)(19 downto 4);
      x2_mult <= to_unsigned(x2_inv * safe_to_integer(x_mult),12+16)(19 downto 4);
      y1_mult <= to_unsigned(y1_inv * safe_to_integer(y_mult),12+16)(19 downto 4);
      y2_mult <= to_unsigned(y2_inv * safe_to_integer(y_mult),12+16)(19 downto 4);
      
      r := x1_mult + x_delta; x1 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled x1 = ( (" & integer'image(x1_int)
          & " * " & integer'image(safe_to_integer(x_mult))
          & ") >> 11) + " & integer'image(safe_to_integer(x_delta))
          & " = " & integer'image(safe_to_integer(r));
      end if;
      r := y1_mult + y_delta; y1 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled y1 = ( (" & integer'image(y1_int)
          & " * " & integer'image(safe_to_integer(y_mult))
          & ") >> 11) + " & integer'image(safe_to_integer(y_delta))
          & " = " & integer'image(safe_to_integer(r));
      end if;
      r := x2_mult + x_delta; x2 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled x2 = ( (" & integer'image(x2_int)
          & " * " & integer'image(safe_to_integer(x_mult))
          & ") >> 11) + " & integer'image(safe_to_integer(x_delta))
          & " = " & integer'image(safe_to_integer(r));
      end if;
      r := y2_mult + y_delta; y2 <= r(15 downto 6);
      if parse_touch = 3 then
        report "scaled y2 = ( (" & integer'image(y2_int)
          & " * " & integer'image(safe_to_integer(y_mult))
          & ") >> 11) + " & integer'image(safe_to_integer(y_delta))
          & " = " & integer'image(safe_to_integer(r));
      end if;


      
    end if;
  end process;  
  
end foo;
