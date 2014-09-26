use work.cputypes.all;

entity vicii_sprites is
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
    signal sprite0_data_address : out integer range 0 to 63;    
    signal sprite1_data_address : out integer range 0 to 63;    
    signal sprite2_data_address : out integer range 0 to 63;    
    signal sprite3_data_address : out integer range 0 to 63;    
    signal sprite4_data_address : out integer range 0 to 63;    
    signal sprite5_data_address : out integer range 0 to 63;    
    signal sprite6_data_address : out integer range 0 to 63;    
    signal sprite7_data_address : out integer range 0 to 63;    

    signal sprite_x : in sprite_vector_8;
    signal vicii_sprite_xmsbs : in std_logic_vector(7 downto 0);
    signal sprite_y : in sprite_vector_8;
    signal sprite_colours : in sprite_vector_8;
    signal sprite_multi0_colour : in unsigned(7 downto 0);
    signal sprite_multi1_colour : in unsigned(7 downto 0);
    signal sprite_is_multicolour : in unsigned(7 downto 0);
    signal sprite_stretch_x : in unsigned(7 downto 0);
    signal sprite_stretch_y : in unsigned(7 downto 0);
    
    -- Is the pixel just passed in a foreground pixel?
    -- Similarly, is the pixel a sprite pixel from another sprite?
    signal is_foreground_in : in std_logic;
    signal is_sprite_in : in std_logic;
    -- and what is the colour of the bitmap pixel?
    signal pixel_in : in unsigned(7 downto 0);
    -- and of the sprite pixel?
    signal sprite_colour_in : in unsigned(7 downto 0);

     -- Pass 
    signal pixel_out : out unsigned(7 downto 0);
    signal sprite_colour_out : out unsigned(7 downto 0);
    signal is_sprite_out : out std_logic;

);
end vicii_sprites;
