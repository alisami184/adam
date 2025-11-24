#include <stdint.h>

// CSR addresses (from your DIFT implementation)
#define CSR_TPR 0x7C0  // Tag Propagation Register
#define CSR_TCR 0x7C1  // Tag Check Register

#define read_csr(csr) ({ \
    unsigned long __value; \
    asm volatile ("csrr %0, %1" : "=r"(__value) : "i"(csr)); \
    __value; \
})

#define write_csr(csr, value) ({ \
    asm volatile ("csrw %0, %1" :: "i"(csr), "r"(value)); \
})

// VERSION 1C: Utiliser CSR pour marquer des registres comme tainted
// Nécessite que le core supporte TPR/TCR

int main(void) {
    volatile int a, b, sum;
    int reg_a, reg_b;

    // Méthode 1: Utiliser TPR pour forcer le tag des prochaines opérations
    write_csr(CSR_TPR, 0xFFFFFFFF);  // Activer tainting
    reg_a = 10;                       // reg_a devrait être tainted
    a = reg_a;                        // Store avec tag=1

    write_csr(CSR_TPR, 0x00000000);  // Désactiver tainting
    reg_b = 20;                       // reg_b trusted
    b = reg_b;                        // Store avec tag=0

    // Load et addition
    reg_a = a;                        // Load → récupère tag=1
    reg_b = b;                        // Load → récupère tag=0
    sum = reg_a + reg_b;              // ADD → tag(sum) = 1

    while(1);
}
