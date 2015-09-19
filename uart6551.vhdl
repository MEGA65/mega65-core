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
    reset : in std_logic;
    irq : out std_logic := 'Z';
    
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

    portf : inout std_logic_vector(7 downto 0)
    
    );
end uart6551;

architecture behavioural of uart6551 is

  signal reg_porte_out : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_ddr : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_read : unsigned(1 downto 0) := (others => '0');
  signal reg_portf_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_read : unsigned(7 downto 0) := (others => '0');

begin  -- behavioural
  
  process(cpuclock,fastio_address,fastio_write
          ) is
    variable register_number : unsigned(7 downto 0);
  begin
    if cs='0' then
      -- Tri-state read lines if not selected
      fastio_rdata <= (others => 'Z');
    else
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
              fastio_rdata(1 downto 0) <= reg_porte_read;
            when x"08" =>
              fastio_rdata(7 downto 2) <= (others => 'Z');
              fastio_rdata(1 downto 0) <= unsigned(reg_porte_ddr);
            when x"0e" =>
              -- @IO:65 $D60E PMOD port A on FPGA board (data bits)
              fastio_rdata(7 downto 0) <= reg_portf_read;
            when x"0f" =>
              -- @IO:65 $D60F PMOD port A on FPGA board (DDR)
              fastio_rdata(7 downto 0) <= unsigned(reg_portf_ddr);
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
    variable result : unsigned(1 downto 0);     
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
      reg_portf_read(7 downto 6) <= ddr_pick(reg_portf_ddr(7 downto 6),
                                             portf(7 downto 6),
                                             reg_portf_out(7 downto 6));
      reg_portf_read(5 downto 4) <= ddr_pick(reg_portf_ddr(5 downto 4),
                                             portf(5 downto 4),
                                             reg_portf_out(5 downto 4));
      reg_portf_read(3 downto 2) <= ddr_pick(reg_portf_ddr(3 downto 2),
                                             portf(3 downto 2),
                                             reg_portf_out(3 downto 2));
      reg_portf_read(1 downto 0) <= ddr_pick(reg_portf_ddr(1 downto 0),
                                             portf(1 downto 0),
                                             reg_portf_out(1 downto 0));

      porte_out <= reg_porte_out or (not reg_porte_ddr);
      -- Support proper tri-stating on port F which connects to FPGA board PMOD
      -- connector.
      for bit in 0 to 7 loop
        if reg_portf_ddr(bit)='1' then
          portf(bit) <= reg_portf_out(bit) or (not reg_portf_ddr(bit));
        else
          portf(bit) <= 'Z';
        end if;
      end loop;
      
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
