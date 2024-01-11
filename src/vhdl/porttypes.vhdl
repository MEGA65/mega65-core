library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package porttypes is

  type user_port_out is record
    d : std_logic_vector(7 downto 0);
    d_en_n : std_logic_vector(7 downto 0);
    pa2 : std_logic;
    sp1 : std_logic;
    cnt2 : std_logic;
    sp2 : std_logic;
    pc2 : std_logic;
    cnt1 : std_logic;
    reset_n : std_logic;
    atn_en_n : std_logic;
  end record;

  type user_port_in is record
    d : std_logic_vector(7 downto 0);
    pa2 : std_logic;
    sp1 : std_logic;
    cnt2 : std_logic;
    sp2 : std_logic;
    pc2 : std_logic;
    flag2 : std_logic;
    cnt1 : std_logic;
    reset_n : std_logic;
  end record;

  type c1565_port_out is record
    serio : std_logic;
    serio_en_n : std_logic;
    clk : std_logic;
    ld : std_logic;
    rst : std_logic;
  end record;

  type c1565_port_in is record
    serio : std_logic;
  end record;

  type tape_port_out is record
    wdata : std_logic;
    motor_en : std_logic;
  end record;

  type tape_port_in is record
    rdata : std_logic;
    sense : std_logic;
  end record;

end package;

package body porttypes is
  

end porttypes;
