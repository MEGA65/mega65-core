library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;

entity mfm_test is
  
end mfm_test;

architecture behavior of mfm_test is

  type CharFile is file of character;

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';

  signal ready_for_next : std_logic := '0';
  signal f_write : std_logic := '0';
  signal byte_valid : std_logic := '0';
  signal byte_in : unsigned(7 downto 0) := x"A1";
  signal clock_byte_in : unsigned(7 downto 0) := x"FB";

  signal f_rdata : std_logic;

  type byte_array_t is array (0 to 65536) of unsigned(15 downto 0);

  -- Disk data consists of bytes of data and clock data.
  -- Normal bytes have clock = $FF
  -- Sync bytes are $A1 with clock byte = $FB
  signal mfm_data : byte_array_t := (
    -- Following the C65 manual instructions for disk format

    -- 12 x gap 3* 
    x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",
    -- 3x A1/FB mark
    x"A1FB",x"A1FB",x"A1FB",
    -- Header mark
    x"FEFF",
    x"28FF", -- Track number
    x"01FF", -- Side number (inverted on 1581)
    x"01FF", -- Sector number
    x"02FF", -- Sectors = 512 bytes long
    -- CRC bytes
    x"00FF",x"00FF",
    -- Gap 2 (23 x $4E)
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    -- Gap 2 (12 x $00)
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    -- 3x A1/FB mark
    x"A1FB",x"A1FB",x"A1FB",
    -- Data mark
    x"FBFF",
    -- Sector data
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    -- CRC bytes
    x"00FF",x"00FF",
    
    -- Gap 3 (24 x $4E)
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    
    others => x"0000"
    );

  signal byte_counter : integer := 0;

  signal last_ready_for_next : std_logic := '0';
  
begin

  process is
    file trace : CharFile;
    variable c : character;
  begin
    while true loop
      file_open(trace,"assets/synthesised-60ns.dat",READ_MODE);
      while not endfile(trace) loop
        Read(trace,c);
        f_rdata <= std_logic(to_unsigned(character'pos(c),8)(4));
        wait for 6 ns;
      end loop;
      file_close(trace);
    end loop;
  end process;

  mfmenc0:
    entity work.mfm_bits_to_gaps port map (
      clock40mhz => cpuclock,
      cycles_per_interval => to_unsigned(80,8),
      write_precomp_enable => '0',
      ready_for_next => ready_for_next,
      f_write => f_write,
      byte_valid => byte_valid,
      byte_in => byte_in,
      clock_byte_in => clock_byte_in
    );

  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      last_ready_for_next <= ready_for_next;
      if ready_for_next = '1' and last_ready_for_next = '0' then
        byte_valid <= '1';
        byte_in <= mfm_data(byte_counter)(15 downto 8);
        clock_byte_in <= mfm_data(byte_counter)(7 downto 0);
        report "Feeding byte #" & integer'image(byte_counter) & " into MFM encoder: $" & to_hstring(mfm_data(byte_counter));
        if byte_counter < 1024 then
          byte_counter <= byte_counter + 1;
        else
          byte_counter <= 0;
        end if;
      else
        byte_valid <= '0';
      end if;
    end if;
  end process;
    
  process
  begin  -- process tb
    report "beginning simulation" severity note;

    wait for 3 ns;
    
    for i in 1 to 2000000 loop

      clock325 <= '0';
      pixelclock <= '0';
      cpuclock <= '0';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '0';
      cpuclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
    
end behavior;

