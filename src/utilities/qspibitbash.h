#ifndef QSPIBITBASH_H
#define QSPIBITBASH_H

void spi_transaction(const unsigned char *tx_bytes, unsigned char num_tx,
                     unsigned char *rx_bytes, unsigned char num_rx);
void spi_transaction_tx8(unsigned char tx_byte);
unsigned char spi_transaction_tx8rx8(unsigned char tx_byte);
unsigned char spi_rx_byte(void);
void spi_tx_byte(unsigned char byte);
void spi_idle_clocks(unsigned char count);
void spi_output_enable(void);
void spi_output_disable(void);
void spi_cs_low(void);
void spi_cs_high(void);
void spi_clock_low(void);
void spi_clock_high(void);

unsigned char qspi_rx_byte(void);
void qspi_tx_byte(unsigned char byte);

#endif /* QSPIBITBASH_H */
