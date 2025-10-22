#include "aes.h"

void aes_init(void) {
    // Enable peripheral (bit 1 of CTRL register)
    RAL.AES->CTRL = (1 << AES_CTRL_ENABLE_BIT);
    
    // Clear any pending events
    RAL.AES->ER = ~0;
    
    // Disable interrupts by default (software can enable if needed)
    RAL.AES->IER = 0;
}

/**
 * @brief Configure l'AES : mode et longueur de clé
 * @param encrypt: AES_ENCRYPT (1) ou AES_DECRYPT (0)  
 * @param keylen: AES_KEYLEN_128, ou AES_KEYLEN_256
 */
void aes_config(uint8_t encrypt, uint8_t keylen) {
    uint32_t config = 0;
    
    // Bit 0: encrypt/decrypt
    if (encrypt) {
        config |= (1 << 0);
    }
    
    // Bit 1: key length (0 = 128-bit, 1 = 256-bit)
    if (keylen == AES_KEYLEN_256) {
        config |= (1 << 1);
    }
    // Pour AES_KEYLEN_128, le bit reste à 0
    
    RAL.AES->CONFIG = config;
}

/**
 * @brief Configure la clé
 * @param key: tableau contenant la clé sous 128bit ou 256bit
 * @param words: 4 ou 8 selon la taille de la clé
 */

void aes_write_key(uint32_t *key, uint8_t keylen)
{
    uint8_t words = (keylen == AES_KEYLEN_256) ? 8 : 4;

    for (uint8_t i = 0; i < words; i++) {
        RAL.AES->KEY = key[i];
    }
}


void aes_write_block(uint32_t *block) {   
    for (int i = 0; i < 4; i++) {
        RAL.AES->BLOCK = block[i];
    }
}

void aes_start(void) {
    // Clear any previous completion event before starting
    RAL.AES->ER = (1 << AES_ER_DONE_BIT);
    
    // Trigger start (bit 0 of CTRL, with peripheral enabled on bit 1)
    RAL.AES->CTRL = (1 << AES_CTRL_START_BIT) | (1 << AES_CTRL_ENABLE_BIT);
}

/**
 * @brief Enable AES completion interrupt
 */
void aes_enable_interrupt(void) {
    RAL.AES->IER = (1 << AES_IER_DONEIE_BIT);
}

/**
 * @brief Disable AES completion interrupt
 */
void aes_disable_interrupt(void) {
    RAL.AES->IER = 0;
}

/**
 * @brief Clear AES interrupt flag (MUST be called in ISR)
 * This is critical! Writing 1 to the event bit clears it
 */
void aes_clear_interrupt(void) {
    RAL.AES->ER = (1 << AES_ER_DONE_BIT);  // Write 1 to clear
}

/**
 * @brief Check if AES operation is complete
 * @return true if done event flag is set
 */
bool aes_is_done(void) {
    return (RAL.AES->ER & (1 << AES_ER_DONE_BIT)) != 0;
}

/**
 * @brief Read status register
 */
uint32_t aes_read_status(void) {
    return RAL.AES->STATUS; 
}

/**
 * @brief Read event register
 */
uint32_t aes_read_events(void) {
    return RAL.AES->ER;
}

/**
 * @brief Read result (blocking - waits for completion)
 * @param result: 4-word array to store the result
 */
void aes_read_result(uint32_t *result) {
    for (uint8_t i = 0; i < 4; i++) {
        result[i] = RAL.AES->RESULT;
        // Barrière mémoire FORTE : force chaque lecture séparée
        __asm__ __volatile__ ("fence rw, rw" : : : "memory");
    }
}
