-- MultiSID, combined I/O for all four SIDs and the filter coefficient table.
-- Includes pre-mixer to allow for panning any of the four SIDs to either
-- audio mixer channel.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity multisid is
  
  port (
    cpuclock, phi0_1mhz, reset_high, w : in std_logic;
    leftsid_cs, rightsid_cs, frontsid_cs, backsid_cs, filter_cs : in std_logic;
    leftsid_out, rightsid_out, frontsid_out, backsid_out : out signed(17 downto 0);
    supersid_w1_cs, supersid_w2_cs, supersid_w3_cs, supersid_w4_cs : in std_logic;
    reg_loopback_cs : in std_logic;
    data_i : in std_logic_vector(7 downto 0);
    data_o : out std_logic_vector(7 downto 0);
    sid_mode : in unsigned(4 downto 0);
    address : in unsigned(11 downto 0);
    potl_x, potr_x, potl_y, potr_y : in unsigned(7 downto 0);
    leftsid_combined, rightsid_combined : out signed(17 downto 0)
    );

end entity multisid;

architecture rtl of multisid is
  signal filter_table_addr0 : integer range 0 to 2047 := 0;
  signal filter_table_addr1 : integer range 0 to 2047 := 0;
  signal filter_table_addr2 : integer range 0 to 2047 := 0;
  signal filter_table_addr3 : integer range 0 to 2047 := 0;
  signal filter_table_val0 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val1 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val2 : unsigned(15 downto 0) := (others => '0');
  signal filter_table_val3 : unsigned(15 downto 0) := (others => '0');
  signal leftsid_audio, rightsid_audio, frontsid_audio, backsid_audio : signed(17 downto 0) := (others => '0');
  signal leftsid_panl, leftsid_panr : unsigned(7 downto 0) := (others => '0');
  signal rightsid_panl, rightsid_panr : unsigned(7 downto 0) := (others => '0');
  signal frontsid_panl, frontsid_panr : unsigned(7 downto 0) := (others => '0');
  signal backsid_panl, backsid_panr : unsigned(7 downto 0) := (others => '0');
  signal mux_di : unsigned(7 downto 0);
  signal mux_addr : unsigned(11 downto 0);
  signal filt_data_o : std_logic_vector(7 downto 0);
  signal data_buf : std_logic_vector(7 downto 0);
  signal reset_buffer, reset_stage1 : std_logic := '1';
  
  ----------------------------------------------------------------------------------------------------------------------
  -- Functions
  ----------------------------------------------------------------------------------------------------------------------

  -- add two signed integers, peak if overflow, used to try and fix the SIDs
  -- hardcoding this to 16 bits because i'm lazy ngl
  subtype signed18 is signed(17 downto 0);
  subtype unsigned8 is unsigned(7 downto 0);

  function multiply_by_volume_coefficient( value : signed(17 downto 0);
                                           volume : unsigned(7 downto 0))
    return signed18 is
    variable value_unsigned : unsigned(17 downto 0);
    variable result_unsigned : unsigned(26 downto 0);
    variable actual_result_unsigned : unsigned(25 downto 0);
    variable result : signed(17 downto 0);
  begin

    if volume = x"00" then
      return o"000000";
    end if;
    
    if value(17) = '1' then
      value_unsigned := unsigned((not value) + 1);
    else
      value_unsigned := unsigned(value);
    end if;
    -- fix for peak values being $8001 and $7FFE, ignore the wacky size fix
    result_unsigned := value_unsigned * (('0' & volume) + 1);
    actual_result_unsigned := result_unsigned(25 downto 0);

    if value(17) = '1' then
      result_unsigned(25 downto 8) := (not result_unsigned(25 downto 8)) + 1;
    end if;
    result := signed(result_unsigned(25 downto 8));
    return result;
  end function;   

  function add_with_ovf (
    a : signed(18 downto 0);
    b : signed(18 downto 0))
    return signed18 is
    variable add_result : signed(18 downto 0) := (others => '0');
  begin  -- function add_with_ovf
    add_result := a + b;
    if add_result(18) /= add_result(17) then
      if add_result(18) = '1' then
        add_result(17 downto 0) := o"400000";
      else
        add_result(17 downto 0) := o"377777";
      end if;
    end if;
    return add_result(17 downto 0);
  end function add_with_ovf;
  
  function mix_outputs(
    a : signed18;
    b : signed18;
    c : signed18;
    d : signed18;
    coeffa : unsigned8;
    coeffb : unsigned8;
    coeffc : unsigned8;
    coeffd : unsigned8
    ) return signed18 is
    variable resized_a, resized_b : signed(18 downto 0) := (others => '0');
    variable resized_c, resized_d : signed(18 downto 0) := (others => '0'); -- vars with more bits for overflow check
    variable add_result : signed(17 downto 0) := (others => '0');
  begin
    resized_a := resize(multiply_by_volume_coefficient(a, coeffa), 19);
    resized_b := resize(multiply_by_volume_coefficient(b, coeffb), 19);
    resized_c := resize(multiply_by_volume_coefficient(c, coeffc), 19);
    resized_d := resize(multiply_by_volume_coefficient(d, coeffd), 19);

    add_result := add_with_ovf(resized_a, resized_b);
    add_result := add_with_ovf(resize(add_result, 19), resized_c);
    add_result := add_with_ovf(resize(add_result, 19), resized_d);
    
    return add_result;
  end function; 
begin  -- architecture rtl

  -- msid_ram_test : entity work.multisid_ram(rtl)
  --   port map (
  --     clka  => cpuclock,
  --     ena   => filter_cs,
  --     dia   => unsigned(data_i),
  --     std_logic_vector(douta) => data_o,
  --     wea   => w,
  --     addra => address(11 downto 0),
  --     web   => '0',
  --     enb   => '0',
  --     doutb => open,
  --     dib   => (others => '0'),
  --     clkb  => '0',
  --     addrb => (others => '0'));
  coefblock: block
  begin
    coeffs: entity work.sid_coeffs(beh) port map (
      clka   => cpuclock,
      clkb   => cpuclock,
      addra  => address,
      addrb  => mux_addr,
      dia    => unsigned(data_i),
      dib    => (others => '0'),
      std_logic_vector(douta)  => filt_data_o,
      doutb  => mux_di,
      wea    => w,
      web    => '0',
      ena    => filter_cs,
      enb    => '1'
      );
  end block;
  sidcblock: block
  begin
    sidc: entity work.sid_coeffs_mux(mayan) port map (
      clk => cpuclock,
      addr0 => filter_table_addr0,
      val0 => filter_table_val0,             
      addr1 => filter_table_addr1,
      val1 => filter_table_val1,             
      addr2 => filter_table_addr2,
      val2 => filter_table_val2,             
      addr3 => filter_table_addr3,
      val3 => filter_table_val3,
      addr => mux_addr,
      di => mux_di
      );
  end block;

  block6: block
  begin
    leftsid: entity work.sid6581
      generic map (
        RESET_PAN_LEFT  => x"FF",
        RESET_PAN_RIGHT => x"00")
      port map (
        clk_1MHz => phi0_1mhz,
        cpuclock => cpuclock,
        reset => reset_buffer,
        cs => leftsid_cs,
        loopback => reg_loopback_cs,
        mode => sid_mode(0),
        supersid => sid_mode(4),
        we => w,
        addr => unsigned(address(4 downto 0)),
        di => unsigned(data_i),
        std_logic_vector(do) => data_o,
        pot_x => potl_x,
        pot_y => potl_y,
        signed_audio => leftsid_audio,
        filter_table_addr => filter_table_addr0,
        filter_table_val => filter_table_val0,
        pan_left => leftsid_panl,
        pan_right => leftsid_panr
        );
  end block;

  block7: block
  begin
    rightsid: entity work.sid6581
      generic map (
        RESET_PAN_LEFT  => x"00",
        RESET_PAN_RIGHT => x"FF")
      port map (
        clk_1MHz => phi0_1mhz,
        cpuclock => cpuclock,
        reset => reset_buffer,
        cs => rightsid_cs,
        loopback => reg_loopback_cs,
        mode => sid_mode(1),
        supersid => sid_mode(4),
        we => w,
        addr => unsigned(address(4 downto 0)),
        di => unsigned(data_i),
        std_logic_vector(do) => data_o,
        pot_x => potr_x,
        pot_y => potr_y,
        signed_audio => rightsid_audio,
        filter_table_addr => filter_table_addr1,
        filter_table_val => filter_table_val1,
        pan_left => rightsid_panl,
        pan_right => rightsid_panr
        );
  end block;

  block6b: block
  begin
    frontsid: entity work.sid6581
      generic map (
        RESET_PAN_LEFT  => x"FF",
        RESET_PAN_RIGHT => x"00")
      port map (
        clk_1MHz => phi0_1mhz,
        cpuclock => cpuclock,
        reset => reset_buffer,
        cs => frontsid_cs,
        loopback => reg_loopback_cs,
        mode => sid_mode(2),
        supersid => sid_mode(4),
        we => w,
        addr => unsigned(address(4 downto 0)),
        di => unsigned(data_i),
        std_logic_vector(do) => data_o,
        pot_x => potl_x,
        pot_y => potl_y,
        signed_audio => frontsid_audio,
        filter_table_addr => filter_table_addr2,
        filter_table_val => filter_table_val2,
        pan_left => frontsid_panl,
        pan_right => frontsid_panr
        );
  end block;

  block7b: block
  begin
    backsid: entity work.sid6581
      generic map (
        RESET_PAN_LEFT  => x"00",
        RESET_PAN_RIGHT => x"FF")
      port map (
        clk_1MHz => phi0_1mhz,
        cpuclock => cpuclock,
        reset => reset_buffer,
        cs => backsid_cs,
        loopback => reg_loopback_cs,
        mode => sid_mode(3),
        supersid => sid_mode(4),
        we => w,
        addr => unsigned(address(4 downto 0)),
        di => unsigned(data_i),
        std_logic_vector(do) => data_o,
        pot_x => potr_x,
        pot_y => potr_y,
        signed_audio => backsid_audio,
        filter_table_addr => filter_table_addr3,
        filter_table_val => filter_table_val3,
        pan_left => backsid_panl,
        pan_right => backsid_panr
        );
  end block;

  main: process (cpuclock, filt_data_o) is
  begin  -- process main
    if rising_edge(cpuclock) then
      -- Need to buffer the filter data output or the bus gets clobbered
      -- This requires 3 waitstates for filter table access
      if filter_cs = '1' then
        data_buf <= filt_data_o;
      else
        data_buf <= (others => 'Z');
      end if;
      leftsid_combined <= mix_outputs(
        leftsid_audio,
        frontsid_audio,
        rightsid_audio,
        backsid_audio,
        leftsid_panl,
        frontsid_panl,
        rightsid_panl,
        backsid_panl
        );
      rightsid_combined <= mix_outputs(
        leftsid_audio,
        frontsid_audio,
        rightsid_audio,
        backsid_audio,
        leftsid_panr,
        frontsid_panr,
        rightsid_panr,
        backsid_panr
        );
      -- reset_stage1 <= reset_high;
      -- reset_buffer <= reset_stage1;
      reset_buffer <= reset_high;
    end if;
  end process main;
  data_o <= data_buf;
  leftsid_out <= leftsid_audio;
  rightsid_out <= rightsid_audio;
  frontsid_out <= frontsid_audio;
  backsid_out <= backsid_audio;
end architecture rtl;
