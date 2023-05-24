-- Audio cross-bar mixer for the MEGA65
-- There are a set of audio sources, each of which can have a separate
-- gain, and which are combined to produce the composited audio for a
-- given audio output channel.  Each output also has a master volume that
-- is applied at the end.  We allow 15 inputs + master volume and 16 outputs.
-- This requires (16 inputs x 2 bytes) x (8 outputs) x 16 bits = 512 bytes of volume registers.
-- The reason for having a full cross-bar mixer is so that it is possible to
-- do all sorts of unusual audio routings, such as patching a call between
-- the two cellular modems, and then also allowing the mixing in of the local
-- microphone, or even the audio from a running game etc.
--
-- The framework is purposely general, and doesn't really care what the
-- sources and outputs are.
--
-- Inputs: SIDL, SIDR, CEL1, CEL2, BTL, BTR, PHONES1, PHONES2
--         DIGL, DIGR, MIC1, MIC2, MIC3,  MIC4,  HEADMIC
-- Outputs: SPKRL, SPKRR, CELO1, CELO2, BTL, BTR, HEADL, HEADR

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity audio_mixer is
  port (    
    cpuclock : in std_logic;

    -- Interface for accessing mix table
    reg_num : in unsigned(7 downto 0) := x"FF";
    reg_write : in std_logic := '0';
    wdata : in unsigned(15 downto 0) := x"FFFF";
    rdata : out unsigned(15 downto 0) := x"FFFF";
    audio_loopback : out signed(15 downto 0) := x"FFFF";
    modem_is_pcm_master : out std_logic := '0';
    amplifier_enable : out std_logic := '0';

    -- Read in values from audio knobs
    volume_knob1 : in unsigned(15 downto 0) := x"FFFF";
    volume_knob2 : in unsigned(15 downto 0) := x"FFFF";
    volume_knob3 : in unsigned(15 downto 0) := x"FFFF";

    -- Which output do the knobs apply to?
    volume_knob1_target : in unsigned(3 downto 0) := "1111";
    volume_knob2_target : in unsigned(3 downto 0) := "1111";
    volume_knob3_target : in unsigned(3 downto 0) := "1111";
    
    -- Audio inputs
    sources : in sample_vector_t := (others => x"0000");
    -- Audio outputs
    outputs : buffer sample_vector_t := (others => x"0000")
    );

end entity;

architecture elizabethan of audio_mixer is
  signal srcs : sample_vector_t := (others => x"0000");
  signal source_num : integer range 0 to 15 := 0;

  signal state : integer := 0;
  signal output_offset : integer := 0;
  signal output_num : integer := 0;
  
  signal ram_raddr : integer := 0;
  signal ram_waddr : integer := 0;
  signal ram_wdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_rdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_we : std_logic := '0';

  signal source14_volume : unsigned(15 downto 0) := to_unsigned(0,16);
  
  signal set_output : std_logic := '0';
  signal output_channel : integer range 0 to 15 := 0;
  
  signal mixed_value : signed(15 downto 0) := x"0000";

  signal dummy : unsigned(15 downto 0) := x"0000";

  signal volume_knob1_last : unsigned(15 downto 0) := x"8000";
  signal volume_knob2_last : unsigned(15 downto 0) := x"8000";
  signal volume_knob3_last : unsigned(15 downto 0) := x"8000";
  
begin

  coefmem0: entity work.ram32x1024_sync
    port map (
      clk => cpuclock,

      cs => '1',
      address => ram_raddr,
      rdata => ram_rdata,

      w => ram_we,
      write_address => ram_waddr,
      wdata(31 downto 16) => wdata,
      wdata(15 downto 0) => dummy
      );
  
  process (cpuclock) is
    variable src_temp : unsigned(15 downto 0);
    variable mix_temp : integer;

    function multiply_by_volume_coefficient( value : signed(15 downto 0);
                                             volume : unsigned(15 downto 0))
      return signed is
      variable value_unsigned : unsigned(15 downto 0);
      variable result_unsigned : unsigned(31 downto 0);
      variable result : signed(31 downto 0);
    begin
      if (value(15)='0') then
        value_unsigned(14 downto 0) := unsigned(value(14 downto 0));
      else
        value_unsigned(14 downto 0) := (not unsigned(value(14 downto 0)) + 1);
      end if;
      value_unsigned(15) := '0';

      result_unsigned := value_unsigned * volume;

      if value(15)='1' then
        result_unsigned := (not result_unsigned) + 1;
      end if;

      result := signed(result_unsigned);

      return result(31 downto 16);
      
    end function;   
    
  begin
    if rising_edge(cpuclock) then

      -- Allow CPU to read any audio input or mixed output
      if safe_to_integer(reg_num) < 16 then
        audio_loopback <= sources(safe_to_integer(reg_num));
      elsif to_integer(reg_num) < 24 then
        audio_loopback <= outputs(safe_to_integer(reg_num)-16);
      else
        audio_loopback <= x"DEAD";
      end if;
      
      if reg_write='1' then
        report "Writing $" & to_hstring(wdata) & " to mixer coefficient $" & to_hstring(reg_num);
        ram_waddr <= safe_to_integer(reg_num(7 downto 1));
        ram_wdata(31 downto 16) <= wdata;
        if reg_num = x"5E" then
          -- Bit 0 of coefficient register $5E controls PCM slave/master mode selection
          modem_is_pcm_master <= wdata(0);
        end if;
        if reg_num = x"FE" then
          -- Bit 0 of coefficient register $FE controls audio amplifier
          amplifier_enable <= wdata(0);
        end if;
        ram_we <= '1';
      elsif volume_knob1_target(3)='0' and volume_knob1 /= volume_knob1_last then
        ram_waddr <= safe_to_integer(volume_knob1_target)*16+15;
        ram_wdata(31 downto 17) <= volume_knob1(14 downto 0);
        ram_wdata(16) <= volume_knob1(0);
        volume_knob1_last <= volume_knob1;
      elsif volume_knob2_target(3)='0' and volume_knob2 /= volume_knob2_last then
        ram_waddr <= safe_to_integer(volume_knob2_target)*16+15;
        ram_wdata(31 downto 17) <= volume_knob2(14 downto 0);
        ram_wdata(16) <= volume_knob2(0);
        volume_knob2_last <= volume_knob2;
      elsif volume_knob3_target(3)='0' and volume_knob3 /= volume_knob3_last then
        ram_waddr <= safe_to_integer(volume_knob3_target)*16+15;
        ram_wdata(31 downto 17) <= volume_knob3(14 downto 0);
        ram_wdata(16) <= volume_knob3(0);
        volume_knob3_last <= volume_knob3;
      else
        ram_we <= '0';
      end if;

      report "Read data = $" & to_hstring(ram_rdata(31 downto 16)) & " in state " & integer'image(state);
      -- State machine for mixing audio sources
      case state is
        when 0 =>
          -- Stop outputting sample
          set_output <= '0';          
          -- Latch input samples
          srcs <= sources;
          -- Reset output value
          -- XXX A bit of a hack to allow 16 inputs: Inputs #14 and #15 have
          -- the same volume level, taken from source 14
          -- (This is used for the OPL2 FM synthesiser)
          mixed_value <= multiply_by_volume_coefficient(sources(15),source14_volume);
          report "Zeroing mixed_value";
          -- Request second mix coefficient (first was already scheduled last cycle)
          -- (this is to handle the wait state on read).
          ram_raddr <= 1 + output_offset;
          -- Store fetched coefficient based on CPU request
          -- Service CPU initiated reading of mix coefficient
          rdata <= ram_rdata(31 downto 16);                   
          report "Read coefficient for the CPU as $" & to_hstring(ram_rdata(31 downto 16));
        when 1|2|3|4|5|6|7|8|9|10|11|12|13|14|15 =>
          -- Add this input using the read coefficient
          report "For output "
            & integer'image(output_num)
            & ": adding input " & integer'image(state-1)
            & " (= $" & to_hstring(srcs(state - 1)) & ")"
            & " via coefficient $" & to_hstring(ram_rdata(31 downto 16))
            & " to current sum = $" & to_hstring(mixed_value);
--          mix_temp := ram_rdata(31 downto 16) * srcs(state - 1);
          if state = 15 then
            source14_volume <= ram_rdata(31 downto 16);
          end if;
          mixed_value <= mixed_value + multiply_by_volume_coefficient(srcs(state - 1),ram_rdata(31 downto 16));
          -- Request next mix coefficient
          if state /= 15 then
            ram_raddr <= state + output_offset + 1;
          else
            -- Service one CPU request per iteration of an output
            report "Reading coefficient $" & to_hstring(reg_num) & " for the CPU";
            ram_raddr <= safe_to_integer(reg_num(7 downto 1));
          end if;
          
        when 16 =>
          -- Apply master volume
          report "For output "
            & integer'image(output_num)
            & " applying master volume coefficient $" & to_hstring(ram_rdata(31 downto 16));
          mixed_value <= multiply_by_volume_coefficient(mixed_value,ram_rdata(31 downto 16));
          set_output <= '1';
          output_channel <= output_num;
          
          -- Advance to next output
          if output_num /= 7 then
            output_num <= output_num + 1;
            output_offset <= output_offset + 16;
            -- Schedule reading of first byte ready (RAM has a wait-state on read)
            ram_raddr <= output_offset + 16;
          else
            output_num <= 0;
            output_offset <= 0;
            -- Schedule reading of first byte ready (RAM has a wait-state on read)
            ram_raddr <= 0;
          end if;


        when others =>
          null;
      end case;
      
      -- Advance through all inputs
      if state /= 16 then
        state <= state + 1;
      else
        state <= 0;
      end if;
      -- Push mixed output value
      if set_output='1' then
        outputs(output_channel) <= mixed_value;
        report "Outputing channel " & integer'image(output_channel) & " mixed value as $"
          & to_hstring(mixed_value);
      end if;
    end if;
  end process;
  
end elizabethan;
