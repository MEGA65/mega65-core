use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Dual-BRAM sector buffer shared between bulk IO devices (SD card, F011 FDC, QSPI flash).
--
-- Two identical 4096 x 8-bit BRAMs are kept in sync via a shared write port:
--   sb_memorymapped  exposes a CPU-side read port (for memory-mapped fastio access)
--   sb_workcopy      exposes a device-side read port (for bulk IO devices reading
--                    sector data back, e.g. when writing to SD card or floppy)
--
-- Address layout within the 4096-byte space:
--   $A00-$BFF  QSPI flash sector buffer  ("101" & offset[8:0])
--   $C00-$DFF  F011 FDC sector buffer    ("110" & offset[8:0])
--   $E00-$FFF  SD card sector buffer     ("111" & offset[8:0])
--   $000-$9FF  unused

entity sector_buffer is
  port (
    clock             : in  std_logic;

    -- CPU read port: driven by fastio address decode in bulk_io_device
    cpu_read_address  : in  unsigned(11 downto 0);
    cpu_rdata         : out unsigned(7 downto 0);

    -- Shared write port: driven by whichever bulk IO device is active,
    -- or by bulk_io_device when handling a CPU write via sectorbuffercs
    dev_write         : in  std_logic;
    dev_write_address : in  unsigned(11 downto 0);
    dev_wdata         : in  unsigned(7 downto 0);

    -- Device read port: used by bulk IO devices to read sector data back
    -- (e.g. when sending a sector to the SD card or floppy)
    dev_read_address  : in  unsigned(11 downto 0);
    dev_rdata         : out unsigned(7 downto 0)
  );
end entity sector_buffer;

architecture behavioural of sector_buffer is
begin

  -- CPU-side read port. Always enabled; address decode in bulk_io_device
  -- ensures only valid ranges are exposed to the CPU.
  sb_memorymapped : entity work.ram8x4096_sync
    generic map (
      unit => x"0"
    )
    port map (
      clkr          => clock,
      clkw          => clock,
      cs            => '1',
      address       => to_integer(cpu_read_address),
      rdata         => cpu_rdata,
      w             => dev_write,
      write_address => to_integer(dev_write_address),
      wdata         => dev_wdata
    );

  -- Device-side read port. Bulk IO devices use this to read back sector
  -- data, for example when writing a sector out to SD card or floppy.
  sb_workcopy : entity work.ram8x4096_sync
    generic map (
      unit => x"1"
    )
    port map (
      clkr          => clock,
      clkw          => clock,
      cs            => '1',
      address       => to_integer(dev_read_address),
      rdata         => dev_rdata,
      w             => dev_write,
      write_address => to_integer(dev_write_address),
      wdata         => dev_wdata
    );

end behavioural;
