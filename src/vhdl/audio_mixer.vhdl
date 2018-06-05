-- Audio cross-bar mixer for the MEGA65
-- There are a set of audio sources, each of which can have a separate
-- gain, and which are combined to produce the composited audio for a
-- given audio output channel.  Each output also has a master volume that
-- is applied at the end.  We allow 15 inputs + master volume and 16 outputs.
-- This requires 256 x 16 bits = 512 bytes of volume registers.
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
    clock50mhz : in std_logic;

    -- Interface for accessing mix table
    reg_num : in unsigned(7 downto 0) := x"FF";
    reg_write : in std_logic := '0';
    wdata : in unsigned(15 downto 0) := x"FFFF";
    rdata : out unsigned(15 downto 0) := x"FFFF";
    audio_loopback : out unsigned(15 downto 0) := x"FFFF";
    modem_is_pcm_master : out std_logic := '0';
    amplifier_enable : out std_logic := '0';
    
    -- Audio inputs
    sources : in sample_vector_t := (others => x"8000");
    -- Audio outputs
    outputs : inout sample_vector_t := (others => x"8000")
    );

end entity;

architecture elizabethan of audio_mixer is
  signal srcs : sample_vector_t := (others => x"8000");
  signal source_num : integer range 0 to 15 := 0;

  signal state : integer := 0;
  signal output_offset : integer := 0;
  signal output_num : integer := 0;
  
  signal ram_raddr : integer := 0;
  signal ram_waddr : integer := 0;
  signal ram_wdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_rdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_we : std_logic := '0';

  signal set_output : std_logic := '0';
  signal output_channel : integer range 0 to 15 := 0;
  
  signal mixed_value : integer := 0;

  signal dummy : unsigned(15 downto 0) := x"0000";
  
begin

  coefmem0: entity work.ram32x1024_sync
    port map (
      clk => clock50mhz,

      cs => '1',
      address => ram_raddr,
      rdata => ram_rdata,

      w => ram_we,
      write_address => ram_waddr,
      wdata(31 downto 16) => wdata,
      wdata(15 downto 0) => dummy
      );
  
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then

      -- Allow CPU to read any audio input or mixed output
      if to_integer(reg_num) < 16 then
        audio_loopback <= sources(to_integer(reg_num));
      elsif to_integer(reg_num) < 24 then
        audio_loopback <= outputs(to_integer(reg_num)-16);
      else
        audio_loopback <= x"DEAD";
      end if;
      
      if reg_write='1' then
        report "Writing $" & to_hstring(wdata) & " to mixer coefficient $" & to_hstring(reg_num);
        ram_waddr <= to_integer(reg_num(7 downto 1));
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
          mixed_value <= 0;
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
            & " to current sum = $" & to_hstring(to_unsigned(mixed_value,32));
          mixed_value <= mixed_value + to_integer(ram_rdata(31 downto 16)) * to_integer(srcs(state - 1));
          -- Request next mix coefficient
          if state /= 15 then
            ram_raddr <= state + output_offset + 1;
          else
            -- Service one CPU request per iteration of an output
            report "Reading coefficient $" & to_hstring(reg_num) & " for the CPU";
            ram_raddr <= to_integer(reg_num(7 downto 1));
          end if;
          
        when 16 =>
          -- Apply master volume
          report "For output "
            & integer'image(output_num)
            & " applying master volume coefficient $" & to_hstring(ram_rdata(31 downto 16));
          mixed_value <= to_integer(to_unsigned(mixed_value,32)(31 downto 16)) * to_integer(ram_rdata(31 downto 16));
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
        outputs(output_channel) <= to_unsigned(mixed_value,32)(31 downto 16);
        report "Outputing channel " & integer'image(output_channel) & " mixed value as $"
          & to_hstring(to_unsigned(mixed_value,32)(31 downto 16));
      end if;
    end if;
  end process;
  
end elizabethan;
