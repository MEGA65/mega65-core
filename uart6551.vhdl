use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity uart6551 is
  port (
    cpuclock : in std_logic;
    phi0 : in std_logic;
    todclock : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';

    seg_led : out unsigned(31 downto 0);

    reg_isr_out : out unsigned(7 downto 0);
    imask_ta_out : out std_logic;
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    cs : in std_logic;
    fastio_address : in unsigned(7 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    porte_out : out std_logic_vector(1 downto 0);
    porte_in : in std_logic_vector(1 downto 0);
    
end uart6551;

architecture behavioural of uart6551 is

  signal reg_porte_out : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_ddr : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_read : unsigned(1 downto 0) := (others => '0');

begin  -- behavioural
  
  process(cpuclock,fastio_address,fastio_write
          ) is
    variable register_number : unsigned(7 downto 0);
  begin
    if cs='0' then
      -- Tri-state read lines if not selected
      fastio_rdata <= (others => 'Z');
    else
--      if rising_edge(cpuclock) then
        -- XXX For debugging have 32 registers, and map
        -- reg_porta_read and portain (and same for port b)
        -- to extra registers for debugging.
        register_number(7 downto 4) := (others => '0');
        register_number(3 downto 0) := fastio_address(3 downto 0);

        -- Reading of registers
        if fastio_write='1' then
          -- Tri-state read lines if writing
          fastio_rdata <= (others => 'Z');
        else
          -- See 2.3.3.3 in c65manual.txt for register assignments
          -- (in a real C65 these registers are in the 4510)
          case register_number is
            when x"07" =>
              fastio_rdata(7 downto 2) <= (others => 'Z');
              -- XXX we ignore the DDR here: we should honour it
              fastio_rdata(1 downto 0) <= porte_in;
            when x"08" =>
              fastio_rdata(7 downto 2) <= (others => 'Z');
              fastio_rdata(1 downto 0) <= porte_ddr;
            when others => fastio_rdata <= (others => 'Z');
          end case;
        end if;
      end if;
--    end if;
  end process;

  process(cpuclock) is
    -- purpose: use DDR to show either input or output bits
    function ddr_pick (
      ddr                            : in std_logic_vector(1 downto 0);
      i                              : in std_logic_vector(1 downto 0);
      o                              : in std_logic_vector(1 downto 0))
    return unsigned is
    variable result : unsigned(7 downto 0);     
  begin  -- ddr_pick
    --report "determining read value for CIA port." &
    --  "  DDR=$" & to_hstring(ddr) &
    --  ", out_value=$" & to_hstring(o) &
    --  ", in_value=$" & to_hstring(i) severity note;
    result := unsigned(i);
    for b in 0 to 1 loop
      if ddr(b)='1' and i(b)='1' then
        result(b) := std_ulogic(o(b));
      end if;
    end loop;  -- b
    return result;
  end ddr_pick;

  variable register_number : unsigned(3 downto 0);
  begin
    if rising_edge(cpuclock) then
      register_number := fastio_address(3 downto 0);

      -- Calculate read value for porta and portb
      reg_porte_read <= ddr_pick(reg_porte_ddr,porte_in,reg_porte_out);        

      porte_out <= reg_porte_out or (not reg_porte_ddr);
      
      -- Check for register writing
      if fastio_write='1' and cs='1' then
        register_number := fastio_address(3 downto 0);
        case register_number is
          when x"7" => reg_porte_out<=std_logic_vector(fastio_wdata(1 downto 0));
          when x"8" => reg_porte_ddr<=std_logic_vector(fastio_wdata(1 downto 0));
          when others => null;
        end case;
      end if;
    end if;
  end process;

end behavioural;
