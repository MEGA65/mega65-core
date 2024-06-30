#ifndef QSPIHWASSIST_H
#define QSPIHWASSIST_H

/*
 * Hardware-assisted 512 byte read operation.
 *
 * Parameters:
 *   address: Address in flash to read from.
 *   data: Pointer to a buffer that will receive the bytes read.
 *   num_latency_cycles: Number of latency cycles to observe.
 *
 * The number of latency cycles required depends on the specific flash device
 * used. The hardware QSPI flash controller supports from 3 up to 8 latency
 * cycles.
 *
 * Returns:
 *   char: 0 - success, 1 - read failed (an unsupported number of latency
 *     cycles was specified)
 */
char hw_assisted_read_512(unsigned long address, unsigned char * data, unsigned char num_latency_cycles);

/*
 * Hardware-assisted 512 byte verify operation.
 *
 * Parameters:
 *   address: Address in flash to verify.
 *   data: Expected data, to compare with flash contents.
 *   num_latency_cycles: Number of latency cycles to observe.
 *
 * The number of latency cycles required depends on the specific flash device
 * used. The hardware QSPI flash controller supports from 3 up to 8 latency
 * cycles.
 *
 * Returns:
 *   char: 0 - success, 1 - verify failed (data differs, or an unsupported
 *     number of latency cycles was specified)
 */
char hw_assisted_verify_512(unsigned long address, const unsigned char * data, unsigned char num_latency_cycles);

/*
 * Hardware-assisted parameter sector erase operation.
 *
 * Parameters:
 *   address: Address in flash of the sector to erase.
 *
 * The size of a parameter sector depends on the specific flash device used. The
 * specified address does not need to be aligned on a sector boundary.
 *
 * A hardware assisted erase operation finishes as soon as the corresponding
 * SPI command has been transmitted to the flash device. The caller of this
 * function is responsible for polling the status register to determine when
 * the flash device has finished the erase command, as well as to detect erase
 * errors.
 */
void hw_assisted_erase_parameter_sector(unsigned long address);

/*
 * Hardware-assisted sector erase operation.
 *
 * Parameters:
 *   address: Address in flash of the sector to erase.
 *
 * The size of a sector depends on the specific flash device used. The specified
 * address does not need to be aligned on a sector boundary.
 *
 * A hardware assisted erase operation finishes as soon as the corresponding
 * SPI command has been transmitted to the flash device. The caller of this
 * function is responsible for polling the status register to determine when
 * the flash device has finished the erase command, as well as to detect erase
 * errors.
 */
void hw_assisted_erase_sector(unsigned long address);

/*
 * Hardware-assisted 256 byte page program operation.
 *
 * Parameters:
 *   address: Address in flash of the page to program; should be aligned on a
 *     page boundary.
 *   data: Pointer to a buffer of data to write to flash.
 *
 * A hardware assisted program operation finishes as soon as the corresponding
 * SPI command has been transmitted to the flash device. The caller of this
 * function is responsible for polling the status register to determine when
 * the flash device has finished the program command, as well as to detect
 * programming errors.
 */
void hw_assisted_program_page_256(unsigned long address, const unsigned char * data);

/*
 * Hardware-assisted 512 byte page program operation.
 *
 * Parameters:
 *   address: Address in flash of the page to program; should be aligned on a
 *     page boundary.
 *   data: Pointer to a buffer of data to write to flash.
 *
 * A hardware assisted program operation finishes as soon as the corresponding
 * SPI command has been transmitted to the flash device. The caller of this
 * function is responsible for polling the status register to determine when
 * the flash device has finished the program command, as well as to detect
 * programming errors.
 */
void hw_assisted_program_page_512(unsigned long address, const unsigned char * data);

#endif /* QSPIHWASSIST_H */
