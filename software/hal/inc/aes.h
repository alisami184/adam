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

#define CTRL_START_BIT 0

// Function prototype
void aes_config(uint8_t encrypt, uint8_t keylen);
void aes_write_key(uint32_t *key,uint8_t words);
void aes_write_block(uint32_t *block);
void aes_start(void);
void aes_wait_for_result(void);
void aes_read_result(uint32_t *result);
uint32_t aes_read_status(void);
bool aes_is_done(void);
void __attribute__((interrupt("machine"))) aes_irq_handler(void);

#endif // __AES_H__