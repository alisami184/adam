#include "system.h"

static void hw_init(void);

volatile int timer_interrupt_occurred = 0;
volatile int pin_state = 1;
volatile int aes_interrupt_occurred = 0;
volatile uint32_t aes_result[4];

void __attribute__((interrupt)) default_handler(void)
{
    if (aes_is_done()) {
        aes_read_result((uint32_t*)aes_result);
        //Clear the interrupt flag
        aes_clear_interrupt();
        aes_interrupt_occurred = 1;
        return;
    }

    // Check Timer
    if (RAL.LSPA.TIMER[0]->ER & 1) {
        RAL.LSPA.TIMER[0]->ER = ~0;
        timer_interrupt_occurred = 1;
        return;
    }
}

#define read_csr(csr) ({ \
    unsigned long __value; \
    asm volatile ("csrr %0, %1" : "=r"(__value) : "i"(csr)); \
    __value; \
})

#define write_csr(csr, value) ({ \
    asm volatile ("csrw %0, %1" :: "i"(csr), "r"(value)); \
})


int main() {

    volatile unsigned char c;
    uint32_t tpr, tcr;

    c = 0;
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
    
    hw_init();

    // TPR test
    tpr = read_csr(CSR_TPR);
    write_csr(CSR_TPR, 0xDEADBEEF); // write new value
    tpr = read_csr(CSR_TPR); // read back

    // TCR test
    tcr = read_csr(CSR_TCR);
    write_csr(CSR_TCR, 0xDEADBAAF);
    tcr = read_csr(CSR_TCR);


    uart_init(RAL.LSPA.UART[0], 115200);
    
    // Initialize AES
    aes_init();
    aes_config(AES_ENCRYPT, AES_KEYLEN_128);
    
    // Enable AES interrupt
    aes_enable_interrupt();
    
    // Write key and plaintext
    aes_write_key(key128,AES_KEYLEN_128);
    aes_write_block(plaintext);
    
    aes_start();

    gpio_write(RAL.LSPA.GPIO[0], 0, 1);
    
    while (1)
    {
      gpio_write(RAL.LSPA.GPIO[0], c, pin_state);
      timer0_delay(16250, 1);
      //delay_ms(RAL.LSPA.TIMER[0], 1000);
      if (c == 8) {
        c = 0;
        pin_state = !pin_state;
      }
      else c++;
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
