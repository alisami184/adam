#include <stdint.h>

// VERSION 3: Trois opérations - Addition, Multiplication, Soustraction
// Pour voir différents types d'opérations

int main(void) {
    volatile int a = 10;
    volatile int b = 20;
    volatile int c = 5;
    volatile int result;

    result = a + b;             // Load a, b → ADD → Store (30)
    result = result * 2;        // Load result → MUL → Store (60)
    result = result - c;        // Load result, c → SUB → Store (55)

    while(1);
}
