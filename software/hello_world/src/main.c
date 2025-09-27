#include "system.h"

static void hw_init(void);
static void print_hex(void);

volatile int timer_interrupt_occurred = 0;
volatile int pin_state = 1;

void __attribute__((interrupt)) default_handler(void)
{
    // Clear timer interrupt
    RAL.LSPA.TIMER[0]->ER = ~0;
    // Flag the interrupt
    timer_interrupt_occurred = 1;
}

// Ajoutez après vos déclarations existantes
void print_hex(uint32_t value) {
    // Simple implementation
    char hex[] = "0123456789abcdef";
    char buffer[9];
    for(int i = 7; i >= 0; i--) {
        buffer[7-i] = hex[(value >> (i*4)) & 0xF];
    }
    buffer[8] = '\0';
    
    // Envoi via UART (remplacez par votre fonction UART)
    for(int i = 0; i < 8; i++) {
        // uart_send_char(buffer[i]); // À adapter selon votre HAL
    }
}

int main() {
    uint32_t key128[4]={
      0x2b7e1516,
      0x28aed2a6,
      0xabf71588,
      0x09cf4f3c
    };

    uint32_t plaintext[4]={
      0x6bc1bee2,
      0x2e409f96,
      0xe93d7e11,
      0x7393172a
    };

    uint32_t ciphertext[4];

    hw_init();
    uart_init(RAL.LSPA.UART[0], 115200);
    
    // Configuration
    aes_config(AES_ENCRYPT, AES_KEYLEN_128);

    aes_write_key(key128,4);
    aes_write_block(plaintext);
    aes_start();

    aes_wait_for_result();

    aes_read_result(ciphertext);

    while(1) {
        timer0_delay(16250, 1);
    }
}

void hw_init(void) {
  // Resume UART0
  RAL.SYSCFG->LSPA.UART[0].MR = 1;
  while (RAL.SYSCFG->LSPA.UART[0].MR);

  // Resume TIMER0
  RAL.SYSCFG->LSPA.TIMER[0].MR = 1;
  while (RAL.SYSCFG->LSPA.TIMER[0].MR);

  // Resume GPIO0
  RAL.SYSCFG->LSPA.GPIO[0].MR = 1;
  while (RAL.SYSCFG->LSPA.GPIO[0].MR);

  // Enable CPU Interrupt
  RAL.SYSCFG->CPU[0].IER = ~0;
}
