#include <stdint.h>

// VERSION 2: Deux opérations - Addition puis multiplication
// Pour voir la propagation en chaîne

int main(void) {
    volatile int a = 10;        // Store: a en RAM
    volatile int b = 20;        // Store: b en RAM
    volatile int result;

    result = a + b;             // Load a, b → ADD → Store (result=30)
                                // Tag(result) = Tag(a) | Tag(b)

    result = result * 2;        // Load result → MUL → Store (result=60)
                                // Tag(result) = Tag(result)

    while(1);
}
