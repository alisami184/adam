#include <stdint.h>

// VERSION 1: Ultra-simple - Une seule addition
// Parfait pour voir la propagation des tags sur une opération

int main(void) {
    volatile int a = 10;        // Store: a en RAM
    volatile int b = 20;        // Store: b en RAM
    volatile int sum;           // Déclaration

    sum = a + b;                // Load a, Load b, ADD, Store sum
                                // Tag(sum) = Tag(a) | Tag(b)

    while(1);                   // Loop infini
}
