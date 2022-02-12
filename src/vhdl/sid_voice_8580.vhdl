--
-- Converted from sid_voice_8580.v by Paul Gardner-Stephen 20220212
--
-- * Fixed oscillatora,b calculations
--
--
--
--
--
--
--


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sid_voice_8580 is
  port (
    cpuclock : in std_logic;
    clock : in std_logic;
    ce_1m : in std_logic;
    reset : in std_logic;
    freq_lo : in unsigned(7 downto 0);
    freq_hi : in unsigned(7 downto 0);
    pw_lo : in unsigned(7 downto 0);
    pw_hi : in unsigned(7 downto 0);
    control : in unsigned(7 downto 0);
    att_dec : in unsigned(7 downto 0);
    sus_rel : in unsigned(7 downto 0);
    osc_msb_in : in std_logic;

    st_out : in unsigned(7 downto 0);
    p_t_out : in unsigned(7 downto 0);
    ps_out : in unsigned(7 downto 0);
    pst_out : in unsigned(7 downto 0);

    sawtooth : out unsigned(11 downto 0);
    supersawtooth : out unsigned(11 downto 0);
    triangle : out unsigned(11 downto 0);

    osc_msb_out : out std_logic;
    signal_out : out unsign(11 downto 0);
    osc_out : out unsigned(7 downto 0);
    env_out : out unsigned(7 downto 0)
    );
end sid_voice_8580;

architecture vhdl_conversion_from_verilog of sid_voice_8580 is
  signal oscillator : unsigned(23 downto 0);
  signal oscillatora : unsigned(23 downto 0);
  signal oscillatorb : unsigned(23 downto 0);
  signal freqa : unsigned(15 downto 0);
  signal freqb : unsigned(15 downto 0);
  signal osc_edge : std_logic;
  signal osc_msb_in_prv : std_logic;
  signal pulse : unsigned(11 downto 0);
  signal noise : unsigned(11 downto 0);
  signal lfsr_noise : unsigned(22 downto 0);

  signal envelope : unsigned(7 downto 0);
  signal wave_out : unsigned(11 downto 0);
  signal dca_out : unsigned(19 downto 0);
  signal pulsewidth : unsigned(15 downto 0);

  alias noise_ctrl : std_logic is control(7);
  alias pulse_ctrl : std_logic is control(6);
  alias saw_ctrl : std_logic is control(5);
  alias tri_ctrl : std_logic is control(4);
  alias test_ctrl : std_logic is control(3);
  alias ringmod_ctrl : std_logic is control(2);
  alias sync_ctrl : std_logic is control(1);

begin

  osc_msb_out <= oscillator(23);
  signal_out <= dca_out(19 downto 8);
  osc_out <= wave_out(11 downto 4);
  env_out <= envelope;
  pulse_width <= "0000"&pw_hi(3 downto 0)&pw_lo;

  freqa <= freq_hi&freq_lo + pw_lo;
  freqb <= freq_hi&freq_lo - pw_hi;
  
  adsr: entity work.sid_envelope port map (
    clock => clock,
    ce_1m => ce_1m,
    reset => reset,
    gate => control(0),
    att_dec => att_dec,
    sus_rel => sus_rel,
    envelope => envelope
    );
  
  process(clock) is
  begin
    if rising_edge(clock) then
      if ce_1m='1' then
        dca_out <= wave_out * envelope;

        osc_msb_in_prv <= osc_msb_in;

        if (reset='1' or test_ctrl='1' or (sync_ctrl='1' and osc_msb_in='0' and osc_msb_in /= osc_msb_in_prv)) then
          oscillator <= (others => '1');
          oscillatora <= (others => '1');
          oscillatorb <= (others => '1');
        else
          oscillator <= oscillator + freq_hi&freq_lo;
          oscillatora <= oscillatora + freqa;
          oscillatorb <= oscillatorb + freqb;
        end if;
      end if;
    end if;

    if reset='1' then
      triangle <= (others => '0');
      sawtooth <= (others => '0');
      supersawtooth <= (others => '0');
      pulse <= (others => '0');
      noise <= (others => '0');
      osc_edge <= '0';
      lfsr_noise <= to_unsigned(1,24);
    elsif ce_1m='1' then
      triangle(0) <= '0';
      if ringmod_ctrl='1' then
        for i in 1 to 11 loop
          triangle(i) <= osc_msb_in xor oscillator(23) xor oscillator(11+i);
        end loop;
      else
        for i in 1 to 11 loop
          triangle(i) <= oscillator(23) xor oscillator(11+i);
        end loop;
      end if;

      sawtooth <= oscillator(23 downto 12);
      supersawtooth <= '0'&oscillator(23 downto 13) + oscillatora(23 downto 12) + oscillatorb(23 downto 12);
      if test_ctrl='1' then
        pulse <= x"fff";
      elsif oscillator(23 downto 12) >= pulsewidth(11 downto 0) then
        pulse <= x"fff";
      else
        pulse <= x"000";
      end if;

      noise <= lfsr_noise(20)&lfsr_noise(18)&lfsr_noise(14)&lfsr_noise(11)&lfsr_noise(9)&lfsr_noise(5)&
               lfsr_noise(2)&lfsr_noise(0)&"0000";

      if oscillator(19)='1' and osc_edge='0' then
        lfsr_noise(23 downto 1) <= lfsr_noise(21)&wave_out(11)&lfsr_noise(19)&wave_out(10)&lfsr_noise(17 downto 15)
                                   &wave_out(9)&lfsr_noise(13 downto 12)&wave_out(8)&lfsr_noise(10)&wave_out(7)
                                   &lfsr_noise(8 downto 6)&wave_out(6)&lfsr_noise(4 downto 3)&wave_out(5)
                                   &lfsr_noise(1)&wave_out(4);
        lfsr_noise(0) <= lfsr_noise(17) xor lfsr_noise(22) xor reset xor test_ctrl;
      else
        lfsr_noise <= lfsr_noise;
      end if;
      
    end if;

    case control(7 downto 4) is
      when "0001" => wave_out <= triangle;
      when "0010" => wave_out <= sawtooth;
      when "1010" => wave_out <= supersawtooth;
      when "0011" => wave_out(15 downto 4) <= st_out; wave_out(3 downto 0) <= "1111";
      when "0100" => wave_out <= pulse;
      when "0101" => wave_out(15 downto 4) <= p_t_out; wave_out(3 downto 0) <= "1111";
      when "0110" => wave_out(15 downto 4) <= ps_out; wave_out(3 downto 0) <= "1111";
      when "0111" => wave_out(15 downto 4) <= pst_out; wave_out(3 downto 0) <= "1111";
      when "1000" => wave_out <= noise;
      when others => wave_out <= (others => '0');
    end case;
  end process;
  
end vhdl_conversion_from_verilog;
  
