library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ssnail_output_buffer is
end tb_ssnail_output_buffer;

architecture test of tb_ssnail_output_buffer is
  signal clk : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal wr_base : unsigned(6 downto 0) := (others => '0');
  signal wr_mask : std_logic_vector(3 downto 0) := (others => '0');
  signal wr_data : unsigned(63 downto 0) := (others => '0');
  signal rd_addr : unsigned(6 downto 0) := (others => '0');
  signal rd_data : unsigned(15 downto 0);
begin
  dut : entity work.ssnail_output_buffer
    port map(clk=>clk,wr_en=>wr_en,wr_base=>wr_base,wr_mask=>wr_mask,
             wr_data=>wr_data,rd_addr=>rd_addr,rd_data=>rd_data);
  stim : process
    type model_t is array(0 to 127) of unsigned(15 downto 0);
    variable expected : model_t := (others => (others => '0'));
    variable base : integer;
    variable mask : integer;
    variable word_value : unsigned(15 downto 0);
    variable next_data : unsigned(63 downto 0);
  begin
    for trial in 0 to 2047 loop
      base := (trial * 53) mod 128;
      mask := (trial * 7 + (trial / 16)) mod 16;
      wr_base <= to_unsigned(base, 7);
      wr_mask <= std_logic_vector(to_unsigned(mask, 4));
      wr_en <= '1';
      next_data := (others => '0');
      for k in 0 to 3 loop
        word_value := to_unsigned((trial * 109 + k * 781) mod 65536, 16);
        next_data(k*16+15 downto k*16) := word_value;
      end loop;
      wr_data <= next_data;
      wait for 2 ns;
      clk <= '1';
      for k in 0 to 3 loop
        if ((mask / (2 ** k)) mod 2) = 1 then
          expected((base + k) mod 128) := next_data(k*16+15 downto k*16);
        end if;
      end loop;
      wait for 2 ns;
      clk <= '0';
      -- Look up every word, including the bank/row boundary wraps.
      for a in 0 to 127 loop
        rd_addr <= to_unsigned(a, 7);
        wait for 1 ns;
        assert rd_data = expected(a)
          report "Mismatch trial=" & integer'image(trial) &
                 " address=" & integer'image(a) severity failure;
      end loop;
    end loop;
    report "PASS: 2048 write packets x 128 address reads" severity note;
    wait;
  end process;
end test;
