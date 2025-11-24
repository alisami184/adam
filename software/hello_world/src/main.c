#include <stdint.h>

// VERSION DIFT TEST: Pre-initialized Data + Tag Memory
// La valeur 100 est pré-chargée dans dmem.hex à l'adresse 0x1000
// Le tag est pré-chargé dans tmem_pretaint.hex (index 0 = TAINTED)

int main(void) {
    volatile int *tainted_source = (volatile int *)0x1000;  // Adresse pré-initialisée
    volatile int a, b, sum;

    // STEP 1: Load depuis adresse pré-tainted
    // La data memory (dmem) a: mem[0x1000] = 100
    // La tag memory (tmem) a: tag[0x1000] = 4'b1111
    // Assembleur: lw x15, 0x1000
    // Attendu: data_rdata=100, data_rdata_tag=4'b1111
    a = *tainted_source;

    // STEP 2: Constante normale (trusted)
    // Assembleur: li x16, 20
    // Attendu: tag_regfile[x16] = 0
    b = 20;

    // STEP 3: Addition avec propagation de tag
    // Assembleur: add x17, x15, x16
    // Attendu: tag_regfile[x17] = 1 | 0 = 1
    sum = a + b;

    // STEP 4: Store sum dans une autre adresse
    // Le tag devrait être propagé
    // Attendu: data_wdata=120, data_wdata_tag=4'b1111
    volatile int *result_addr = (volatile int *)0x1010;
    *result_addr = sum;

    while(1);  // Loop infini pour observer
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
