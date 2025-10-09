#include "aes.h"

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

void aes_write_key(uint32_t *key,uint8_t words) {   
    for (uint8_t i=0; i < words; i++) {
        RAL.AES->KEY[i] = key[i];
    }
}

void aes_write_block(uint32_t *block) {   
    for (uint8_t i=0; i < 4; i++) {
        RAL.AES->BLOCK[i] = block[i];
    }
}

void aes_start(void) {
    RAL.AES->CTRL = (1 << CTRL_START_BIT);  // Set bit 0
}

uint32_t aes_read_status(void) {
    return RAL.AES->STATUS; 
}

bool aes_is_done(void) {
    return (RAL.AES->STATUS & (1 << 1)) != 0;  // bit1 = 1 → opération terminée
}

void aes_read_result(uint32_t *result) {
    for (uint8_t i = 0; i < 4; i++) {
        result[i] = RAL.AES->RESULT[i];
    }
}

void aes_wait_for_result(void) {
    while (!aes_is_done()) {
    }
}

/* ISR appelé automatiquement par l’IRQ 11 (via startup.s) */
void __attribute__((interrupt("machine"))) aes_irq_handler(void) {
    /* 1) (optionnel) vérifier le DONE si besoin */
    uint32_t ciphertext[4];

    aes_read_result(ciphertext);

}
