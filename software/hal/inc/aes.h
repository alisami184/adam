#ifndef __AES_H__
#define __AES_H__

#include "adam_ral.h"
#include "types.h"

// Key length values
#define AES_KEYLEN_128   0x0
#define AES_KEYLEN_256   0x1

// Mode values
#define AES_DECRYPT      0
#define AES_ENCRYPT      1

#define AES_CTRL_START_BIT     0
#define AES_CTRL_ENABLE_BIT    1

// Status Register bits  
#define AES_STATUS_READY_BIT   0
#define AES_STATUS_VALID_BIT   1

// Event Register bits
#define AES_ER_DONE_BIT        0

// Interrupt Enable Register bits
#define AES_IER_DONEIE_BIT     0

// Function prototype
void aes_init(void);
void aes_config(uint8_t encrypt, uint8_t keylen);
void aes_write_key(uint32_t *key, uint8_t keylen);
void aes_write_block(uint32_t *block);
void aes_enable_interrupt(void);
void aes_disable_interrupt(void);
void aes_clear_interrupt(void);
void aes_start(void);
void aes_wait_for_result(void);
void aes_read_result(uint32_t *result);
uint32_t aes_read_status(void);
bool aes_is_done(void);
uint32_t aes_read_events(void);

#endif // __AES_H__