use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity tb_adder is
end tb_adder;

architecture behaviour of tb_adder is
  signal flag_n : std_logic := '0';
  signal flag_z : std_logic := '0';
  signal flag_v : std_logic := '0';
  signal flag_c : std_logic := '0';
  signal flag_d : std_logic := '0';
begin  -- behaviour

-- purpose: test adder
  -- type   : combinational
  -- inputs : 
  -- outputs: 
  test: process
    
    impure function with_nz (
      value : unsigned(7 downto 0)) return unsigned is
    begin
      -- report "calculating N & Z flags on result $" & to_hstring(value) severity note;
      flag_n <= value(7);
      if value(7 downto 0) = x"00" then
        flag_z <= '1';
      else
        flag_z <= '0';
      end if;
      return value;
    end with_nz;
    
    impure function alu_op_add (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      variable tmp : unsigned(8 downto 0);
    begin
      if flag_d='1' then
        tmp(8) := '0';
        tmp(7 downto 0) := (i1 and x"0f") + (i2 and x"0f") + ("0000000" & flag_c);

        report "flag_c=" & std_logic'image(flag_c) severity note;
        report "low nybl sum before fixing = $" & to_hstring(tmp(7 downto 0)) severity note;
        report "i1=$" & to_hstring(i1) severity note;
        report "i2=$" & to_hstring(i2) severity note;
        if tmp > x"09" then
          tmp := tmp + x"06";                                                                         
        end if;
        if tmp < x"10" then
          tmp := ("0"&(tmp(7 downto 0) and x"0f")) + ("0"&(i1 and x"f0")) + ("0"&(i2 and x"f0"));
        else
          tmp := ("0"&(tmp(7 downto 0) and x"0f")) + ("0"&(i1 and x"f0")) + ("0"&(i2 and x"f0")) + ("0"&x"10");
        end if;
        if (i1 + i2 + ( "0000000" & flag_c )) = x"00" then
          flag_z <= '1';
        else
          flag_z <= '0';
        end if;
        flag_n <= tmp(7);
        flag_v <= (i1(7) xor tmp(7)) and (not (i1(7) xor i2(7)));      
        report "before fix tmp=" & to_string(std_logic_vector(tmp)) severity note;
        if tmp(8 downto 4) > "01001" then
          tmp(7 downto 0) := tmp(7 downto 0) + x"60";
          tmp(8) := '1';
        end if;
        report "tmp=" & to_string(std_logic_vector(tmp)) severity note;
        flag_c <= tmp(8);
      else
        tmp := ("0"&i2)
               + ("0"&i1)
               + ("00000000"&flag_c);
        tmp(7 downto 0) := with_nz(tmp(7 downto 0));
        flag_v <= (not (i1(7) xor i2(7))) and (i1(7) xor tmp(7));
        flag_c <= tmp(8);
      end if;
      -- Return final value
      report "add result of "
        & "$" & to_hstring(std_logic_vector(i1)) 
        & " + "
        & "$" & to_hstring(std_logic_vector(i2)) 
        & " + "
        & "$" & std_logic'image(flag_c)
        & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(7 downto 0);
    end function alu_op_add;

    impure function alu_op_sub (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) return unsigned is
      variable tmp : unsigned(8 downto 0);
      variable tmpd : unsigned(8 downto 0);
    begin
      tmp := ("0"&i1) - ("0"&i2)
             - "000000001" + ("00000000"&flag_c);
      flag_c <= not tmp(8);
      flag_v <= (i1(7) xor tmp(7)) and (i1(7) xor i2(7));
      tmp(7 downto 0) := with_nz(tmp(7 downto 0));
      if flag_d='1' then
        tmpd := (("00000"&i1(3 downto 0)) - ("00000"&i2(3 downto 0)))
                - "000000001" + ("00000000" & flag_c);

        report "i1=$" & to_hstring(i1) severity note;
        report "i2=$" & to_hstring(i2) severity note;
        if tmpd(4)='1' then
          tmpd(3 downto 0) := tmpd(3 downto 0)-x"6";
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4)) - "00001";
        else
          tmpd(8 downto 4) := ("0"&i1(7 downto 4)) - ("0"&i2(7 downto 4));
        end if;
        if tmpd(8)='1' then
          tmpd := tmpd - ("0"&x"60");
        end if;
        tmp := tmpd;
      end if;
      -- Return final value
      report "add result of "
        & "$" & to_hstring(std_logic_vector(i1)) 
        & " - "
        & "$" & to_hstring(std_logic_vector(i2)) 
        & " - 1 + "
        & "$" & std_logic'image(flag_c)
        & " = " & to_hstring(std_logic_vector(tmp(7 downto 0))) severity note;
      return tmp(7 downto 0);
    end function alu_op_sub;

    procedure alu_op_cmp (
      i1 : in unsigned(7 downto 0);
      i2 : in unsigned(7 downto 0)) is
      variable result : unsigned(8 downto 0);
    begin
      result := ("0"&i1) - ("0"&i2);
      flag_z <= '0'; flag_c <= '0';
      if result(7 downto 0)=x"00" then
        flag_z <= '1';
      end if;
      if result(8)='0' then
        flag_c <= '1';
      end if;
      flag_n <= result(7);
    end alu_op_cmp;
    
    variable result : unsigned(7 downto 0);
  begin  -- process test
    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"00",x"88");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='0' report "v should be 0" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"11",x"77");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='1' report "v should be 1" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"11",x"88");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='0' report "v should be 0" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"11",x"99");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='0' report "v should be 0" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"22",x"66");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='1' report "v should be 1" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"33",x"55");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='1' report "v should be 1" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"44",x"44");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='1' report "v should be 1" severity failure;

    flag_c <= '0';
    wait for 1 ns;
    result := alu_op_add(x"44",x"88");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='0' report "v should be 0" severity failure;

    flag_c <= '1';
    wait for 1 ns;
    result := alu_op_add(x"11",x"77");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_v='1' report "v should be 1" severity failure;

    report "DECIMAL MODE TESTS" severity note;
    
    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_add(x"00",x"11");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"11" report "result should be $11" severity failure;

    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_add(x"24",x"56");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"80" report "result should be $80" severity failure;
    assert flag_v='1' report "v should be 1" severity failure;

    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_add(x"00",x"88");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"88" report "result should be $88" severity failure;
    assert flag_v='0' report "v should be 0" severity failure;

    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_add(x"AA",x"FF");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"0F" report "result should be $0F" severity failure;
    assert flag_v='0' report "v should be 0" severity failure;
    assert flag_c='1' report "c should be 1" severity failure;

    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_add(x"00",x"FF");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"65" report "result should be $65" severity failure;
    assert flag_v='0' report "v should be 0" severity failure;
    assert flag_c='1' report "c should be 1" severity failure;

    report "SUBTRACTION TESTS" severity note;

    flag_c <= '0';
    flag_d <= '1';
    wait for 1 ns;
    result := alu_op_sub(x"00",x"00");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"99" report "result should be $99" severity failure;
    assert flag_v='0' report "v should be 0" severity failure;
    assert flag_c='0' report "c should be 0" severity failure;

    flag_c <= '1';
    flag_d <= '0';
    wait for 1 ns;
    result := alu_op_sub(x"a0",x"08");
    report "result is $" & to_hstring(result) severity note;
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert result=x"98" report "result should be $98" severity failure;
    assert flag_v='0' report "v should be 0" severity failure;
    assert flag_c='1' report "c should be 1" severity failure;

    report "TESTING COMPARE" severity note;

    wait for 1 ns;
    alu_op_cmp(x"00",x"88");
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_n='0' report "n should be 0" severity failure;
    assert flag_c='0' report "c should be 0" severity failure;
    assert flag_z='0' report "z should be 0" severity failure;
    
    wait for 1 ns;
    alu_op_cmp(x"88",x"00");
    wait for 1 ns;
    report "v=" &std_logic'image(flag_v) & ", z=" &std_logic'image(flag_z) & ", c=" &std_logic'image(flag_c) & ", n=" &std_logic'image(flag_n) severity note;
    assert flag_n='1' report "n should be 1" severity failure;
    assert flag_c='1' report "c should be 1" severity failure;
    assert flag_z='0' report "z should be 0" severity failure;
    
    report "Simulation ended" severity failure;
  end process test;
end behaviour;
