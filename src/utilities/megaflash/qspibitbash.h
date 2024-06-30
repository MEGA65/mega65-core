#ifndef QSPIBITBASH_H
#define QSPIBITBASH_H

/*
 * Perform a generic SPI transaction.
 *
 * Parameters:
 *   tx_bytes: Pointer to a buffer of data to transmit.
 *   num_tx: Number of bytes to transmit.
 *   rx_bytes: Pointer to a buffer to store received data.
 *   num_tx: Number of bytes to receive.
 *
 * The clock line is set high (idle). The chip select line is set low,
 * enabling communication with the flash device. Then the specified data is
 * transmitted, and subsequently the specified number of bytes are received.
 * Finally, the chip select line is set high, disabling communication with
 * the flash device, and the clock line is set high (idle).
 */
void spi_transaction(const unsigned char *tx_bytes, unsigned char num_tx,
                     unsigned char *rx_bytes, unsigned char num_rx);

/*
 * Perform a 1-byte, transmit only, SPI transaction.
 *
 * Parameters:
 *   tx_byte: The byte to transmit.
 */
void spi_transaction_tx8(unsigned char tx_byte);

/*
 * Perform a 1-byte SPI transaction.
 *
 * Parameters:
 *   tx_byte: The byte to transmit.
 *
 * Returns:
 *     unsigned char: The byte received.
 */
unsigned char spi_transaction_tx8rx8(unsigned char tx_byte);

/*
 * Receive a single byte, receiving a single bit each clock cycle (SPI).
 *
 * Returns:
 *     unsigned char: The byte received.
 */
unsigned char spi_rx_byte(void);

/*
 * Transmit a single byte, sending a single bit each clock cycle (SPI).
 *
 * Parameters:
 *   byte: The byte to transmit.
 */
void spi_tx_byte(unsigned char byte);

/*
 * Receive a single byte, receiving four bits each clock cycle (QSPI).
 *
 * Returns:
 *     unsigned char: The byte received.
 */
unsigned char qspi_rx_byte(void);

/*
 * Transmit a single byte, sending four bits each clock cycle (QSPI).
 *
 * Parameters:
 *   byte: The byte to transmit.
 */
void qspi_tx_byte(unsigned char byte);

/*
 * Output clock pulses on the clock line. Each clock pulse consists of setting
 * the clock line low, then setting it high.
 *
 * Parameters:
 *   count: The number of clock pulses to output.
 */
void spi_idle_clocks(unsigned char count);

/*
 * Configure the SPI data lines as outputs.
 */
void spi_output_enable(void);

/*
 * Configure the SPI data lines as inputs.
 */
void spi_output_disable(void);

/*
 * Set the SPI chip select line low.
 */
void spi_cs_low(void);

/*
 * Set the SPI chip select line high.
 */
void spi_cs_high(void);

/*
 * Set the SPI clock line low.
 */
void spi_clock_low(void);

/*
 * Set the SPI clock line high.
 */
void spi_clock_high(void);

#endif /* QSPIBITBASH_H */
