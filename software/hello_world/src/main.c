#include <stdint.h>

// VERSION DIFT TEST: Load depuis variable globale pré-tainted
// Cette variable sera placée en .data section
// On pré-initialise son tag à 1 dans tmem_pretaint.hex

volatile int tainted_input = 100;  // Global variable to be pre-tainted

int main(void) {
    volatile int a, b, sum;

    // STEP 1: Load depuis mémoire pré-tainted
    // Assembleur: lw x15, [tainted_input]
    // Attendu: tag_regfile[x15] = 1 (récupéré depuis tag_mem)
    a = tainted_input;

    // STEP 2: Constante normale (trusted)
    // Assembleur: li x16, 20
    // Attendu: tag_regfile[x16] = 0 (constante immediate)
    b = 20;

    // STEP 3: Addition avec propagation de tag
    // Assembleur: add x17, x15, x16
    // Attendu: tag_regfile[x17] = tag(x15) | tag(x16) = 1 | 0 = 1
    sum = a + b;

    // STEP 4: Store avec tag propagé
    // Assembleur: sw x17, [sum]
    // Attendu: tag_mem[sum] = 4'b1111 (tainted)

    while(1);  // Infinite loop to observe results
}

/*
 * ATTENDU DANS LES WAVEFORMS:
 *
 * 1. Load tainted_input:
 *    - data_req=1, data_addr=<addr_tainted_input>
 *    - data_rdata=100, data_rdata_tag=4'b1111 ✅ TAG RÉCUPÉRÉ!
 *
 * 2. Store a:
 *    - data_req=1, data_we=1, data_wdata=100
 *    - data_wdata_tag=4'b1111 ✅ TAG PROPAGÉ!
 *
 * 3. Store sum:
 *    - data_req=1, data_we=1, data_wdata=120
 *    - data_wdata_tag=4'b1111 ✅ TAG PROPAGÉ APRÈS ADD!
 */
