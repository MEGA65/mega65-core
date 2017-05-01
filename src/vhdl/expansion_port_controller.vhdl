-- XXX - Currently supports only accessing first 64KB of expansion port address
-- space, and does not set select lines based on address.

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY expansion_port_controller IS
  generic (
    pixelclock_frequency : in integer
    );
  PORT (
    ------------------------------------------------------------------------
    -- CPU side interface
    ------------------------------------------------------------------------
    pixelclock : in std_logic;
    cpuclock : in std_logic;

    ------------------------------------------------------------------------
    -- Access request from CPU
    ------------------------------------------------------------------------
    -- CPU asserts cart_access_request with _read flag, and _address and
    -- _wdata set as appropriate.  Interface indicates acceptance of job by
    -- asserting _accept_strobe for one pixelclock tick only.
    cart_access_request : in std_logic;
    cart_access_read : in std_logic;
    cart_access_address : in unsigned(31 downto 0);
    cart_access_wdata : in unsigned(7 downto 0);
    cart_access_accept_strobe : out std_logic;
    cart_access_read_toggle: out std_logic;
    
    ------------------------------------------------------------------------
    -- Strobe indicates when we have read data in response to a request
    ------------------------------------------------------------------------
    -- Strobe lasts one pixelclock tick only.
    cart_access_read_strobe : out std_logic := '0';
    cart_access_rdata : out unsigned(7 downto 0) := x"FF";

    ------------------------------------------------------------------------
    -- Expansion port pins
    ------------------------------------------------------------------------
    cart_ctrl_dir : out std_logic := '1';
    cart_haddr_dir : out std_logic := '1';
    cart_laddr_dir : out std_logic := '1';
    cart_data_dir : out std_logic := '0';

    cart_phi2 : out std_logic;
    cart_dotclock : out std_logic;
    cart_reset : out std_logic := '1';

    cart_nmi : in std_logic;
    cart_irq : in std_logic;
    cart_dma : in std_logic;
    
    cart_exrom : inout std_logic := 'Z';
    cart_ba : inout std_logic := 'Z';
    cart_rw : inout std_logic := 'Z';
    cart_roml : inout std_logic := 'Z';
    cart_romh : inout std_logic := 'Z';
    cart_io1 : inout std_logic := 'Z';
    cart_game : inout std_logic := 'Z';
    cart_io2 : inout std_logic := 'Z';
    
    cart_d : inout unsigned(7 downto 0);
    cart_a : inout unsigned(15 downto 0)
);
end expansion_port_controller;

architecture behavioural of expansion_port_controller is
  -- Ticks is per half clock
  -- XXX - Allow varying the bus speed if we know we have a fast
  -- peripheral
  constant ticks_8mhz_half : integer := pixelclock_frequency / (8 * 2);
  signal ticker : unsigned(7 downto 0) := to_unsigned(0,8);
  signal phi2_ticker : unsigned(7 downto 0) := to_unsigned(0,8);

  -- Are we already servicing a read?
  signal read_in_progress : std_logic := '0';
  signal cart_access_read_toggle_internal : std_logic := '0';
  
  -- Internal state
  signal cart_dotclock_internal : std_logic := '0';
  signal cart_phi2_internal : std_logic := '0';
  
begin

  process (pixelclock)
  begin
    if rising_edge(pixelclock) then
      -- Generate phi2 and dotclock signals at 1Mhz and 8MHz respectively.
      -- We approximate these based on the pixel clock
      if to_integer(ticker) /= ticks_8mhz_half then
        ticker <= ticker + 1;
        cart_access_read_strobe <= '0';
        cart_access_accept_strobe <= '0';
      else
        ticker <= (others => '0');
        -- Tick dot clock
        report "dotclock tick";
        cart_dotclock <= not cart_dotclock_internal;
        cart_dotclock_internal <= not cart_dotclock_internal;
        if phi2_ticker /= 4 then
          phi2_ticker <= phi2_ticker + 1;
          cart_access_read_strobe <= '0';
          cart_access_accept_strobe <= '0';
        else
          -- Tick phi2
          report "phi2 tick";
          phi2_ticker <= (others => '0');
          cart_phi2 <= not cart_phi2_internal;
          cart_phi2_internal <= not cart_phi2_internal;

          -- Record data from bus if we are waiting on it
          if read_in_progress='1' then
            cart_access_rdata <= unsigned(cart_d);
            cart_access_read_strobe <= '1';
            cart_access_read_toggle <= not cart_access_read_toggle_internal;
            cart_access_read_toggle_internal <= not cart_access_read_toggle_internal;
            report "Read data from expansion port data pins = $" & to_hstring(cart_d);
          else
            cart_access_read_strobe <= '0';
          end if;         
          -- Present next bus request if we have one
          if cart_access_request='1' then
            report "Presenting legacy C64 expansion port access request to port, address=$"
              & to_hstring(cart_access_address)
              & " rw=" & std_logic'image(cart_access_read)
              & " wdata=$" & to_hstring(cart_access_wdata);
            cart_access_accept_strobe <= '1';
            cart_a <= cart_access_address(15 downto 0);
            cart_rw <= cart_access_read;
            cart_data_dir <= not cart_access_read;
            if cart_access_address(15 downto 8) = x"DE" then
              cart_io1 <= '0';
            else
              cart_io1 <= '1';
            end if;
            if cart_access_address(15 downto 8) = x"DF" then
              cart_io2 <= '0';
            else
              cart_io2 <= '1';
            end if;

            -- Drive ROML and ROMH
            -- (Note here we are operating after the CPU has decided if something
            -- is mapped, therefore we assert /ROML and /ROMH based on address
            -- requested).
            if (cart_access_address(15 downto 12) = x"8")
              or (cart_access_address(15 downto 12) = x"9")
              or (cart_access_address(15 downto 12) = x"A")
              or (cart_access_address(15 downto 12) = x"B") then
              cart_roml <= '0';
            else
              cart_roml <= '1';
            end if;
            if (cart_access_address(15 downto 12) = x"E")
              or (cart_access_address(15 downto 12) = x"F") then
              cart_romh <= '0';
            else
              cart_romh <= '1';
            end if;

            if cart_access_read='1' then
              read_in_progress <= '1';
              -- Tri-state with pull-up
              report "Tristating cartridge port data lines.";
              cart_d <= (others => 'H');
            else
              read_in_progress <= '0';
              cart_d <= cart_access_wdata;
              report "Write data is $" & to_hstring(cart_access_wdata);
            end if;
          else
            cart_access_accept_strobe <= '0';
            cart_a <= (others => 'H');
            cart_rw <= '1';
            read_in_progress <= '0';
          end if;      
        end if;
      end if;
    end if;
    
  end process;

  
end behavioural;
