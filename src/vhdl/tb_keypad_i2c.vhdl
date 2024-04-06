library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_keypad_i2c is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_keypad_i2c is

  signal clock41 : std_logic := '0';

  signal sda : std_logic;
  signal scl : std_logic;

  signal cs : std_logic := '0';
  signal fastio_read : std_logic := '0';
  signal fastio_write : std_logic := '0';
  signal fastio_rdata : unsigned(7 downto 0);
  signal fastio_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal fastio_addr : unsigned(19 downto 0) := x"00000";
  
  signal port0 : unsigned(7 downto 0) := x"00";
  signal port1 : unsigned(7 downto 0) := x"50";

  signal reset_high : std_logic;
  
begin

  pca0: entity work.pca9555
    generic map ( clock_frequency => 40_500_000,
                  address => b"0100000"
                  )
    port map ( clock => clock41,
               reset => reset_high,
               scl => scl,
               sda => sda,
               port0 => port0,
               port1 => port1);


  unit0: entity work.keypad_i2c
    generic map (clock_frequency => 40_500_000 )
    port map ( clock => clock41,
               sda => sda,
               scl => scl,

               cs => cs,
               fastio_read => fastio_read,
               fastio_write => fastio_write,
               fastio_rdata => fastio_rdata,
               fastio_wdata => fastio_wdata,
               fastio_addr => fastio_addr
               );

  sda <= 'H';
  scl <= 'H';
  
  main : process

    variable v : unsigned(15 downto 0);

    procedure clock_tick is
    begin
      clock41 <= not clock41;
      wait for 12 ns;

    end procedure;

    procedure POKE(a : unsigned(15 downto 0); v : unsigned(7 downto 0)) is
    begin
      cs <= '1';
      fastio_addr(7 downto 0) <= a(7 downto 0);
      fastio_wdata <= v;
      fastio_write <= '1';
      for i in 1 to 4 loop
        clock_tick;
      end loop;
      fastio_write <= '0';
      cs <= '0';
    end procedure;

    procedure PEEK(a : unsigned(15 downto 0)) is
    begin
      cs <= '1';
      fastio_addr(7 downto 0) <= a(7 downto 0);
      fastio_read <= '1';
      for i in 1 to 8 loop
        clock_tick;
      end loop;
      fastio_read <= '0';
      cs <= '0';
    end procedure;

    procedure wait_a_while(t : integer) is
    begin        
      -- Allow time for everything to happen
      for i in 1 to t loop
        clock_tick;
      end loop;
      report "Waited for " & integer'image(t) & " ticks.";
    end procedure;
    
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("I2C runs") then

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;
        
        for i in 1 to 100000 loop
          clock_tick;
        end loop;

      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
