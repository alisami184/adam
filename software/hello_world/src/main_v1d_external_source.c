#include <stdint.h>

// VERSION 1D: Simuler une source externe tainted
// Utiliser une zone mémoire "spéciale" pré-tainted

// Adresse spéciale pré-marquée comme tainted dans tmem.hex
#define TAINTED_SOURCE_ADDR 0x2000

int main(void) {
    volatile int *tainted_source = (volatile int*)TAINTED_SOURCE_ADDR;
    volatile int a, b, sum;

    // Load depuis source externe (pré-tainted)
    a = *tainted_source;      // Load → rdata_tag = 1111 (tainted)
                              // a hérite du tag

    // Variable normale (trusted)
    b = 20;                   // Store avec tag = 0000

    // Addition
    sum = a + b;              // Tag(sum) = Tag(a) | Tag(b) = 1111

    while(1);
}

// Note: Il faut initialiser tmem.hex pour que l'adresse 0x2000 ait tag=1111
