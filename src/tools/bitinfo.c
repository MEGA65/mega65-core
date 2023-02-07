#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

// 4M x 32 bit words = 16MB
unsigned int data[4 * 1024 * 1024];

unsigned int swap_bytes(unsigned int v, int swapP)
{
  if (!swapP)
    return v;
  return (v >> 24) | (((v >> 16) & 0xff) << 8) | (((v >> 8) & 0xff) << 16) | ((v & 0xff) << 24);
}

int main(int argc, char **argv)
{
  if (argc < 2) {
    fprintf(stderr, "usage: bitinfo <bitstream file>\n");
    exit(-1);
  }

  FILE *f = fopen(argv[1], "r");
  if (!f) {
    fprintf(stderr, "Could not read bitstream file '%s'\n", argv[1]);
    perror("fopen");
    exit(-1);
  }
  int size = fread(&data[1], 4, 4 * 1024 * 1024 * 4, f);

  printf("Bitstream file is %d words long.\n", size);

  int w = 0;
  int rev = 0;

  while (w < size) {
    if (data[w] == 0xAA995566)
      break;
    if (data[w] == 0x665599AA) {
      rev = 1;
      break;
    }
    w++;
  }
  if (w >= size) {
    fprintf(stderr, "ERROR: Could not find sync word in bitstream.\n");
    exit(-1);
  }
  if (rev)
    printf("CPU and bitstream have opposite endianness.\n");

  unsigned int count, reg, val;

  while (w < size) {
    // Skip Type 1 NOOPs
    if (swap_bytes(data[w], rev) == 0x20000000) {
      w++;
      continue;
    }

    printf("$%x:  word $%08x (was $%08x)\n", w, swap_bytes(data[w], rev), data[w]);
    if ((swap_bytes(data[w], rev) & 0xf0000000) == 0x30000000) {
      // Type 1 record: write or reserved operation.
      count = swap_bytes(data[w], rev) & 0x7ff;
      reg = (swap_bytes(data[w], rev) >> 13) & 0x1f;
      w++;
      while (count--) {
        val = swap_bytes(data[w++], rev);
        switch (reg) {
        case 0b00000:
          printf("Setting CRC value to $%08x\n", val);
          break;
        case 0b00100:
          printf("Command register action: ");
          switch (val) {
          case 0b00000:
            printf("NULL: Do nothing");
            break;
          case 0b00001:
            printf("WCFG: Writes Configuration Data: used prior to writing configuration data to the FDRI.");
            break;
          case 0b00010:
            printf("MFW: Multiple Frame Write: used to perform a write of a single frame data to multiple frame addresses.");
            break;
          case 0b00011:
            printf("DGHIGH/LFRM: Last Frame: Deasserts the GHIGH_B signal, activating all interconnects. The GHIGH_B signal "
                   "is asserted with the AGHIGH command.RCFG00100Reads Configuration Data: used prior to reading "
                   "configuration data from the FDRO.");
            break;
          case 0b00101:
            printf("START: Begins the Startup Sequence: The startup sequence begins after a successful CRC check and a "
                   "DESYNC command are performed.");
            break;
          case 0b00110:
            printf("RCAP: Resets the CAPTURE signal after performing readback-capture in single-shot mode.");
            break;
          case 0b00111:
            printf("RCRC: Resets CRC: Resets the CRC register.");
            break;
          case 0b01000:
            printf("AGHIGH: Asserts the GHIGH_B signal: places all interconnect in a High-Z state to prevent contention "
                   "when writing new configuration data. This command is only used in shutdown reconfiguration. "
                   "Interconnect is reactivated with the LFRM command.");
            break;
          case 0b01001:
            printf("SWITCH: Switches the CCLK frequency: updates the frequency of the master CCLK to the value specified by "
                   "the OSCFSEL bits in the COR0 register.");
            break;
          case 0b01010:
            printf("GRESTORE: Pulses the GRESTORE signal: sets/resets (depending on user configuration) IOB and CLB "
                   "flip-flops.");
            break;
          case 0b01011:
            printf(
                "SHUTDOWN: Begin Shutdown Sequence: Initiates the shutdown sequence, disabling the device when finished. "
                "Shutdown activates on the next successful CRC check or RCRC instruction (typically an RCRC instruction).");
            break;
          case 0b01100:
            printf("GCAPTURE: Pulses GCAPTURE: Loads the capture cells with the current register states.");
            break;
          case 0b01101:
            printf("DESYNC: Resets the DALIGN signal: Used at the end of configuration to desynchronize the device. After "
                   "desynchronization, all values on the configuration data pins are ignored.");
            break;
          case 0b01110:
            printf("Reserved: Reserved.");
            break;
          case 0b01111:
            printf("IPROG: Internal PROG for triggering a warm boot.");
            break;
          case 0b10000:
            printf("CRCC: When readback CRC is selected, the configuration logic recalculates the first readback CRC value "
                   "after reconfiguration. Toggling GHIGH has the same effect. This command can be used when GHIGH is not "
                   "toggled during the reconfiguration case.");
            break;
          case 0b10001:
            printf("LTIMER: Reload Watchdog timer.");
            break;
          case 0b10010:
            printf("BSPI_READ1: BPI/SPI re-initiate bitstream read");
            break;
          case 0b10011:
            printf("FALL_EDGE: Switch to negative-edge clocking (configuration data capture on falling edge)	    ");
            break;
          default:
            printf("Unknown COMMAND $%x", val);
            break;
          }
          printf("\n");
          break;
        case 0b01001:
          printf("Setting configuration register 0:\n");
          if ((val & 7) < 6)
            printf("  GWE deassert in Startup Phase %d\n", (val & 7) - 1);
          else if ((val & 7) == 6)
            printf("  GWE tracks DONE\n");
          else
            printf("  GWE set to keep (not recommended)\n");
          if (((val >> 3) & 7) < 6)
            printf("  GTS deassert in Startup Phase %d\n", ((val >> 3) & 7) - 1);
          else if (((val >> 3) & 7) == 6)
            printf("  GTS tracks DONE\n");
          else
            printf("  GTS set to keep (not recommended)\n");
          if (((val >> 6) & 7) == 7)
            printf("  LOCK_CYCLE stall for MMCM lock disabled.\n");
          else
            printf("  LOCK_CYCLE stall for MMCM lock set to stage %d\n", (val >> 6) & 7);
          if (((val >> 9) & 7) == 7)
            printf("  MATCH_CYCLE stall for DCI match disabled.\n");
          else
            printf("  MATCH_CYCLE stall for DCI match set to stage %d\n", (val >> 9) & 7);
          if (((val >> 12) & 7) < 6)
            printf("  DONE pin released in Startup Phase %d\n", ((val >> 12) & 7) - 1);
          else if (((val >> 12) & 7) == 6)
            printf("  DONE pin release in undefined state\n");
          else
            printf("  DONE pin set to keep (not recommended)\n");

          break;
        default:
          printf("Writing value $%08x to FPGA register $%x\n", val, reg);
        }
      }
    }
    else {
      // Unknown data
      w++;
    }
  }

  fclose(f);
}
