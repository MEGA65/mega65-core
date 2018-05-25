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
-- Inputs: SIDL, SIDR, DIGL, DIGR, CEL1, CEL2, BTL, BTR, MIC1, MIC2, MIC3,
-- MIC4, HEADMIC
-- Outputs: SPKRL, SPKRR, CELO1, CELO2, BTL, BTR, HEADL, HEADR

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity audio_mixer is
  port (    
    clock50mhz : in std_logic;

    -- Interface for accessing mix table
    reg_num : in unsigned(7 downto 0) := x"FF";
    reg_write : in std_logic := '0';
    wdata : in unsigned(15 downto 0) := x"FFFF";
    rdata : out unsigned(15 downto 0) := x"FFFF";

    -- Audio inputs
    sources : in sample_vector_t := (others => x"8000");
    -- Audio outputs
    outputs : out sample_vector_t := (others => x"8000")
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

begin

  coefmem0: entity work.ram32x1024_sync
    port map (
      clk => clock,

      cs => '1'
      address => ram_raddr,
      rdata => ram_rdata,

      w => ram_we,
      write_address => ram_waddr
      wdata => wdata
      );
  
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then

      if reg_write='1' then
        ram_waddr <= to_integer(reg_num(7 downto 1));
        ram_we <= '1';
      else
        ram_we <= '0';
      end if;
      
      -- State machine for mixing audio sources
      case state is
        when 0 =>
          -- Stop outputting sample
          set_output <= '0';          
          -- Latch input samples
          srcs <= sources;
          -- Reset output value
          mixed_value <= 0;
          -- Request first mix coefficient
          ram_raddr <= 0 + output_offset;
          -- Store fetched coefficient based on CPU request
          -- Service CPU initiated reading of mix coefficient
          rdata <= ram_rdata(31 downto 16);                   
        when 1|2|3|4|5|6|7|8|9|10|11|12|13|14|15 =>
          -- Add this input using the read coefficient
          mixed_value <= mixed_value + to_integer(ram_rdata(31 downto 16)) * to_integer(srcs(0));
          -- Request next mix coefficient
          ram_addr <= state + output_offset;
          
        when 16 =>
          -- Apply master volume
          mixed_value <= to_integer(to_unsigned(mixed_value,32)(31 downto 16)) * to_integer(ram_rdata(31 downto 16));
          set_output <= '1';
          output_channel <= output_num;
          
          -- Advance to next output
          if output_num /= 7 then
            output_num <= output_num + 1;
            output_offset <= output_offset + 16;
          else
            output_num <= 0;
            output_offset <= 0;
          end if;

          -- While we are idle, read any requested coefficient
          ram_addr <= to_integer(req_num(7 downto 1));
          
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
      end if;
    end if;
  end process;
  
end elizabethan;
