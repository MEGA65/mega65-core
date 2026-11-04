-- Testbench for ascon_aead128 (#965): runs an operation script from
-- src/tools/gen_ascon_vectors.py and checks every output byte and tag byte.
-- Bytes are offered every cycle the core is not busy, as fast as it takes
-- them, with idle cycles thrown in now and then.
--
--   python3 src/tools/gen_ascon_vectors.py ascon_vectors.txt
--   ghdl -a --std=08 src/vhdl/ascon_aead128.vhdl src/vhdl/tb_ascon_aead128.vhdl
--   ghdl -r --std=08 tb_ascon_aead128      (reads ascon_vectors.txt from the
--                                          current directory; -gG_VECTORS=)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_ascon_aead128 is
  generic (G_VECTORS : string := "ascon_vectors.txt");
end entity;

architecture sim of tb_ascon_aead128 is
  signal clk        : std_logic := '0';
  signal init       : std_logic := '0';
  signal key        : unsigned(127 downto 0) := (others => '0');
  signal nonce      : unsigned(127 downto 0) := (others => '0');
  signal byte_valid : std_logic := '0';
  signal mode       : unsigned(1 downto 0) := "00";
  signal byte_in    : unsigned(7 downto 0) := x"00";
  signal byte_out   : unsigned(7 downto 0);
  signal ad_end     : std_logic := '0';
  signal final      : std_logic := '0';
  signal tag_idx    : unsigned(3 downto 0) := x"0";
  signal tag_byte   : unsigned(7 downto 0);
  signal busy       : std_logic;
  signal done       : boolean := false;
begin

  clk <= not clk after 12 ns when not done;

  dut : entity work.ascon_aead128
    port map (clk => clk, init => init, key => key, nonce => nonce,
              byte_valid => byte_valid, mode => mode, byte_in => byte_in,
              byte_out => byte_out, ad_end => ad_end, final => final,
              tag_idx => tag_idx, tag_byte => tag_byte, busy => busy);

  process
    file f : text open read_mode is G_VECTORS;
    variable l : line;
    variable c : character;
    variable bytes_done, errors, msgs : integer := 0;
    variable lfsr : unsigned(7 downto 0) := x"5a";

    type bytes_t is array (0 to 1023) of unsigned(7 downto 0);
    variable a_bytes, b_bytes : bytes_t;
    variable a_len, b_len : integer;

    function hexval(ch : character) return integer is
    begin
      case ch is
        when '0' to '9' => return character'pos(ch) - character'pos('0');
        when 'a' to 'f' => return character'pos(ch) - character'pos('a') + 10;
        when others => report "bad hex" severity failure; return 0;
      end case;
    end function;

    procedure read_bytes(variable v : out bytes_t; variable n : out integer) is
      variable ch, cl : character;
      variable k : integer := 0;
    begin
      read(l, ch);                       -- the space
      read(l, ch);
      if ch = '-' then
        n := 0;
        return;
      end if;
      loop
        read(l, cl);
        v(k) := to_unsigned(hexval(ch) * 16 + hexval(cl), 8);
        k := k + 1;
        exit when l'length = 0 or l(l'left) = ' ';
        read(l, ch);
      end loop;
      n := k;
    end procedure;

    procedure idle_now_and_then is
    begin
      lfsr := lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));
      if lfsr(1 downto 0) = "00" then
        wait until rising_edge(clk);
      end if;
    end procedure;

    procedure pulse(signal p : out std_logic) is
    begin
      while busy = '1' loop
        wait until rising_edge(clk);
      end loop;
      p <= '1';
      wait until rising_edge(clk);
      p <= '0';
      wait for 1 ns;
    end procedure;

    -- push n bytes in mode m; check byte_out against want (if check)
    procedure stream(m : unsigned(1 downto 0); n : integer; check : boolean) is
    begin
      for i in 0 to n - 1 loop
        idle_now_and_then;
        while busy = '1' loop
          wait until rising_edge(clk);
        end loop;
        mode <= m;
        byte_in <= a_bytes(i);
        byte_valid <= '1';
        wait for 1 ns;
        if check and byte_out /= b_bytes(i) then
          report "message " & integer'image(msgs) & " byte " & integer'image(i) & ": got "
            & to_hstring(byte_out) & " want " & to_hstring(b_bytes(i)) severity error;
          errors := errors + 1;
        end if;
        wait until rising_edge(clk);
        byte_valid <= '0';
        wait for 1 ns;
        bytes_done := bytes_done + 1;
      end loop;
    end procedure;
  begin
    wait until rising_edge(clk);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      read(l, c);
      case c is
        when 'I' =>
          read_bytes(a_bytes, a_len);
          read_bytes(b_bytes, b_len);
          for i in 0 to 15 loop
            key(i * 8 + 7 downto i * 8) <= a_bytes(i);
            nonce(i * 8 + 7 downto i * 8) <= b_bytes(i);
          end loop;
          pulse(init);
        when 'A' =>
          read_bytes(a_bytes, a_len);
          stream("00", a_len, false);
          pulse(ad_end);
        when 'E' | 'D' =>
          read_bytes(a_bytes, a_len);
          read_bytes(b_bytes, b_len);
          if c = 'E' then
            stream("01", a_len, true);
          else
            stream("10", a_len, true);
          end if;
        when 'T' =>
          read_bytes(a_bytes, a_len);
          pulse(final);
          while busy = '1' loop
            wait until rising_edge(clk);
          end loop;
          for i in 0 to 15 loop
            tag_idx <= to_unsigned(i, 4);
            wait for 1 ns;
            if tag_byte /= a_bytes(i) then
              report "message " & integer'image(msgs) & " tag byte " & integer'image(i) & ": got "
                & to_hstring(tag_byte) & " want " & to_hstring(a_bytes(i)) severity error;
              errors := errors + 1;
            end if;
          end loop;
          msgs := msgs + 1;
        when others =>
          report "bad script line" severity failure;
      end case;
    end loop;
    report "ascon: " & integer'image(msgs) & " messages, " & integer'image(bytes_done)
      & " bytes, " & integer'image(errors) & " errors" severity note;
    assert errors = 0 report "FAILED" severity failure;
    report "PASS" severity note;
    done <= true;
    wait;
  end process;
end architecture;
