#include <stdint.h>

// VERSION 1B: Test avec variable pré-tainted via tag memory
// La variable 'a' est pré-marquée comme tainted dans tmem.hex

int main(void) {
    volatile int a = 10;        // Store en RAM
                                // Mais tag_mem[addr_a] déjà = 1111 (pré-tainted!)

    volatile int b = 20;        // Store en RAM
                                // tag_mem[addr_b] = 0000 (trusted)

    volatile int sum;

    // Important: Re-load 'a' pour récupérer son tag!
    int temp_a = a;             // Load a → rdata_tag = 1111 (tainted!)
    int temp_b = b;             // Load b → rdata_tag = 0000 (trusted)

    sum = temp_a + temp_b;      // ADD → Tag(sum) = Tag(a) | Tag(b) = 1111
                                // Store sum avec tag = 1111 (tainted!)

    while(1);
}
