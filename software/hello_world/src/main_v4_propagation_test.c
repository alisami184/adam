#include <stdint.h>

// VERSION 4: Test de propagation avec variables séparées
// Pour voir quelles variables sont tainted et lesquelles ne le sont pas

int main(void) {
    volatile int clean_a = 10;      // Clean (untainted)
    volatile int clean_b = 20;      // Clean (untainted)
    volatile int tainted_x = 100;   // Tainted (si CPU marque)
    volatile int result1, result2;

    // Opération 1: clean + clean → result1 devrait être clean
    result1 = clean_a + clean_b;

    // Opération 2: result1 + tainted → result2 devrait être tainted
    result2 = result1 + tainted_x;

    while(1);
}
