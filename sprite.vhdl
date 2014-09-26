entity sprite is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;

    -- Pull sprite data in along the chain from the previous sprite (or VIC-IV)
    signal sprite_datavalid_in : in std_logic;
    signal sprite_bytenumber_in : in integer range 0 to 2;
    signal sprite_spritenumber_in : in integer range 0 to 7;
    signal sprite_data_in : in unsigned(7 downto 0);

    -- Pass sprite data out along the chain to the next sprite
    signal sprite_datavalid_out : out std_logic;
    signal sprite_bytenumber_out : out integer range 0 to 2;
    signal sprite_spritenumber_out : out integer range 0 to 7;
    signal sprite_data_out : out unsigned(7 downto 0);

    -- which base offset for the VIC-II sprite data are we showing this raster line?
    signal sprite_data_address : out integer range 0 to 63;    

    signal left_edge_x : in unsigned(8 downto 0);
    signal displayx_in : in unsigned(11 downto 0);
    signal displayy_in : in unsigned(11 downto 0);
    signal display_active_in : in std_logic;

    -- Is the pixel just passed in a foreground pixel?
    -- Similarly, is the pixel a sprite pixel from another sprite?
    signal is_foreground_in : in std_logic;
    signal is_sprite_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal pixel_in : in unsigned(7 downto 0);
    -- and of the sprite pixel?
    signal sprite_colour_in : in unsigned(7 downto 0);

    signal sprite_x : in unsigned(8 downto 0);
    signal sprite_y : in unsigned(7 downto 0);
    signal sprite_colour : in unsigned(7 downto 0);
    signal sprite_multi0_colour : in unsigned(7 downto 0);
    signal sprite_multi1_colour : in unsigned(7 downto 0);
    signal sprite_is_multicolour : in std_logic;
    signal sprite_stretch_x : in std_logic;
    signal sprite_stretch_y : in std_logic;

    -- Pass 
    signal pixel_out : out unsigned(7 downto 0);
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal is_sprite_out : out std_logic;
);

end sprite;

architecture behavioural of sprite is

begin  -- behavioural

  -- purpose: sprite drawing
  -- type   : sequential
  -- inputs : pixelclock, <reset>
  -- outputs: colour, is_sprite_out
  main: process (pixelclock, <reset name>)
  begin  -- process main
    if pixelclock'event and pixelclock = '1' then  -- rising clock edge
      
    end if;
  end process main;

end behavioural;
