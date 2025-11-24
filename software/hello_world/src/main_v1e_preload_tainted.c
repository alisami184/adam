#include <stdint.h>

// VERSION 1E: Load depuis variable globale pré-tainted
// Cette approche permet au tag de se propager correctement:
// Mémoire → Registre → Opération → Registre → Mémoire

// Variable globale qui sera placée en .data section
// On pré-initialise son tag à 1 dans tmem_pretaint.hex
volatile int tainted_source = 100;

int main(void) {
    volatile int a, b, sum;

    // ✅ CORRECT: Load depuis mémoire pré-tainted
    // Assembleur: lw x15, [tainted_source]
    // Pipeline:
    //   MEM: data_rdata = 100, data_rdata_tag = 4'b1111
    //   WB:  regfile[x15] = 100, tag_regfile[x15] = 1 ✅
    a = tainted_source;

    // Constante normale (trusted)
    // Assembleur: li x16, 20
    // Pipeline:
    //   EX: tag = 0 (constante)
    //   WB: regfile[x16] = 20, tag_regfile[x16] = 0
    b = 20;

    // Addition avec propagation de tag
    // Assembleur: add x17, x15, x16
    // Pipeline:
    //   ID: tag(x15)=1, tag(x16)=0
    //   EX: tag_result = 1 | 0 = 1 ✅
    //   WB: tag_regfile[x17] = 1
    sum = a + b;

    // Store avec tag propagé
    // Assembleur: sw x17, [sum]
    // Pipeline:
    //   ID: tag(x17) = 1
    //   MEM: data_wdata = 120, data_wdata_tag = 4'b1111 ✅

    while(1);
}

/*
 * ATTENDU DANS LES WAVEFORMS:
 *
 * 1. Load tainted_source:
 *    [Time] DREAD: addr=0x00001000 (tainted_source)
 *    [Time] TAG_READ: tags[3:0]=1111 ← TAG RÉCUPÉRÉ!
 *
 * 2. Store a:
 *    [Time] DWRITE: addr=0x00001xxx data=100
 *    [Time] TAG_WRITE: tag[3:0]=1111 ← TAG PROPAGÉ!
 *
 * 3. Store sum:
 *    [Time] DWRITE: addr=0x00001yyy data=120
 *    [Time] TAG_WRITE: tag[3:0]=1111 ← TAG PROPAGÉ APRÈS ADD!
 *
 * SIGNAUX INTERNES À VÉRIFIER (si accessible):
 *    tag_regfile[x15] = 1 après load
 *    tag_regfile[x16] = 0 après li
 *    tag_regfile[x17] = 1 après add
 */
