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

  signal debug_write_count : integer;
  signal debug_write_pending_count : integer;
  
  signal port0 : unsigned(7 downto 0) := x"00";
  signal port1 : unsigned(7 downto 0) := x"50";

  signal debug_reg0: unsigned(7 downto 0);
  signal debug_reg1: unsigned(7 downto 0);
  signal debug_reg2: unsigned(7 downto 0);
  signal debug_reg3: unsigned(7 downto 0);
  signal debug_reg4: unsigned(7 downto 0);
  signal debug_reg5: unsigned(7 downto 0);
  signal debug_reg6: unsigned(7 downto 0);
  signal debug_reg7: unsigned(7 downto 0);
  
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

               debug_reg0 => debug_reg0,
               debug_reg1 => debug_reg1,
               debug_reg2 => debug_reg2,
               debug_reg3 => debug_reg3,
               debug_reg4 => debug_reg4,
               debug_reg5 => debug_reg5,
               debug_reg6 => debug_reg6,
               debug_reg7 => debug_reg7,
               
               port0 => port0,
               port1 => port1);


  unit0: entity work.keypad_i2c
    generic map (clock_frequency => 40_500_000 )
    port map ( clock => clock41,
               sda => sda,
               scl => scl,

               debug_write_pending_count => debug_write_pending_count,
               debug_write_count => debug_write_count,
               
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

      elsif run("Writing to I2C expander triggers write_job_pending") then

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;

        POKE(x"7506",x"91");

        for i in 1 to 1000000 loop
          clock_tick;
          if debug_write_pending_count /= 0 then
            exit;
          end if;
        end loop;

        if debug_write_pending_count = 0 then
          assert false report "write job was never marked pending";
        end if;
        
      elsif run("Writing to I2C causes write to occur") then

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;

        POKE(x"7506",x"91");

        for i in 1 to 1000000 loop
          clock_tick;
          if debug_write_count /= 0 then
            exit;
          end if;
          if debug_write_pending_count > 1 then
            assert false report "debug_write_pending_count should only get to 1, but it got to " & integer'image(debug_write_pending_count);
          end if;
        end loop;

        -- Give time for register update to propagate
        wait_a_while(10);       
        
        if debug_write_pending_count = 0 then
          assert false report "write job was never marked pending";
        end if;
        if debug_write_count = 0 then
          assert false report "write job was never completed";
        end if;

        if debug_reg6 /= x"91" then
          assert false report "PCA9555 register had $91 written to it, but contained $" & to_hexstring(debug_reg6) & " after the write.";
        end if;
        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
