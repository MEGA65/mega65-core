#ifndef MF_UTILITY_H
#define MF_UTILITY_H 1

extern uint8_t mfu_slot_mb;
extern uint8_t mfu_slot_pagemask;
extern uint32_t mfu_slot_size;

extern uint8_t hw_model_id;
extern char hw_model_name[];

int8_t mfut_probe_hardware_version(void);

/*
 * mfut_reconfig_fpga(addr)
 *
 * parameters:
 *   addr: Flash address to reconfigure the FPGA to
 *
 * reconfigures the FPGA to start loading bitstream from addr
 *
 * does not return!
 *
 */
void mfut_reconfig_fpga(uint32_t addr);

#endif /* MF_UTILITY_H */
