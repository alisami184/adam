#include <stdint.h>

// Version simple sans périphériques ADAM pour test standalone

int main(void) {
  // forcer les accès RAM
    volatile int global_a = 10;
    volatile int global_b = 20;
    volatile int global_result = 0;

    // Lecture depuis RAM (.data)
    volatile int x = global_a;      // LECTURE RAM
    volatile int y = global_b;      // LECTURE RAM

    // Calculs avec accès RAM forcés
    global_result = x + y;           // = 30, ÉCRITURE RAM
    global_result = global_result * 2; // LECTURE + ÉCRITURE RAM = 60

    // Test d'écriture/lecture RAM
    global_a = global_result / 3;    // LECTURE + ÉCRITURE RAM = 20

    // Boucle avec accès mémoire visible
    while(1) {
        global_b = global_b + 1;     // LECTURE + ÉCRITURE RAM à chaque itération
    }
    return 0;
}
