/* startup_adam_compat.s - Startup compatible avec linker scripts ADAM existants */

.section .text.reset_handler
.global _start

_start:
reset_handler:
    /* Setup stack pointer */
    la sp, _stack_end

    /* Copier .data de ROM vers RAM */
    /* ADAM utilise _text_end au lieu de _data_load_start */
    la t0, _text_end          /* Source: fin de .text en ROM */
    la t1, _data_start        /* Destination: début de .data en RAM */
    la t2, _data_end

    beq t1, t2, copy_done     /* Skip si .data vide */

copy_loop:
    lw a0, 0(t0)
    sw a0, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    blt t1, t2, copy_loop

copy_done:

    /* Clear .bss section */
    la t1, _bss_start
    la t2, _bss_end

    beq t1, t2, bss_done      /* Skip si .bss vide */

bss_loop:
    sw zero, 0(t1)
    addi t1, t1, 4
    blt t1, t2, bss_loop

bss_done:

    /* Call main() */
    call main

    /* Si main retourne, loop infini */
hang:
    j hang

/* -------------------------------------------------------------------------- */
/* Table de vecteurs minimale */

.section .vectors, "ax"
.option norvc
.align 2

vector_table:
    j reset_handler           /* 0x00: Reset */
    j default_handler         /* 0x04: Exception */
    j default_handler         /* 0x08: ... */
    j default_handler         /* 0x0C: ... */
    .rept 28                  /* Reste des vecteurs */
        j default_handler
    .endr

/* -------------------------------------------------------------------------- */
/* Handler par défaut */

.section .text
default_handler:
trap:
    j trap                    /* Loop infini */
