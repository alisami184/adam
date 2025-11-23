# Hello World - Instructions de Compilation

## Programme de Test

Ce programme teste les accès RAM avec des variables volatiles pour validation du test bench CV32E40P.

### Code principal (main.c)
```c
int main(void) {
    volatile int global_a = 10;
    volatile int global_b = 20;
    volatile int global_result = 0;

    // Lecture RAM
    volatile int x = global_a;
    volatile int y = global_b;

    // Calculs avec accès RAM
    global_result = x + y;           // = 30
    global_result = global_result * 2; // = 60
    global_a = global_result / 3;    // = 20

    // Boucle infinie avec accès RAM
    while(1) {
        global_b = global_b + 1;
    }
}
```

## Compilation

### Prérequis
- RISC-V GCC toolchain: `riscv32-unknown-elf-gcc`
- CMake 3.15+
- Python 3

### Méthode 1: Avec CMake (Recommandé)

```bash
# Depuis la racine du projet adam
cd /adam/software
mkdir -p build
cd build

# Configuration
cmake .. -DADAM_TARGET_NAME=default

# Compilation
make hello_world

# Résultat
# Le fichier .hex sera dans: build/hello_world/hello_world.hex
```

### Méthode 2: Compilation Manuelle (Debug)

```bash
cd /adam/software/hello_world

# Compilation
riscv32-unknown-elf-gcc \
    -march=rv32imc_zicsr \
    -mabi=ilp32 \
    -O2 \
    -g \
    -Wall \
    -mcmodel=medany \
    -static \
    -ffunction-sections \
    -fdata-sections \
    -T link.ld \
    -nostdlib \
    -o hello_world.elf \
    src/startup.s \
    src/main.c \
    -lc_nano \
    -lgcc \
    -lnosys

# Conversion en hex
riscv32-unknown-elf-objcopy \
    -O ihex \
    hello_world.elf \
    hello_world.hex

# Dump assembly (optionnel - pour debug)
riscv32-unknown-elf-objdump \
    -S -D hello_world.elf \
    > hello_world.dump
```

## Utilisation du .hex pour Simulation

### Copier le fichier compilé
```bash
# Après compilation
cp build/hello_world/hello_world.hex /adam/mem0.hex

# OU si compilation manuelle
cp software/hello_world/hello_world.hex /adam/mem0.hex
```

### Lancer la simulation Questa
```bash
cd /adam/bhv
vsim -do run_cv32e40p_tb.do
```

## Vérification du Binaire

### Examiner le contenu
```bash
# Voir les sections
riscv32-unknown-elf-size hello_world.elf

# Voir le disassembly
riscv32-unknown-elf-objdump -d hello_world.elf | less

# Vérifier les adresses
riscv32-unknown-elf-nm hello_world.elf | grep -E "(main|_start|_stack_end)"
```

### Attendu
```
Sections:
  .text    → ROM @ 0x00000000
  .data    → RAM @ 0x00001000
  .bss     → RAM @ 0x00001xxx
  .stack   → RAM @ 0x00001xxx
```

## Comportement Attendu en Simulation

### Accès Mémoire Visibles

1. **Démarrage** (startup.s):
   - Fetch instructions depuis 0x00000000
   - Copie .data de ROM vers RAM (0x1000+)
   - Clear .bss
   - Setup stack
   - Jump vers main

2. **Main** - Séquence d'accès RAM:
   ```
   [Store] 0x1000: global_a = 10
   [Store] 0x1004: global_b = 20
   [Store] 0x1008: global_result = 0
   [Load]  0x1000: x = global_a
   [Load]  0x1004: y = global_b
   [Store] 0x1008: global_result = 30
   [Load]  0x1008: lecture global_result
   [Store] 0x1008: global_result = 60
   [Load]  0x1008: lecture global_result
   [Store] 0x1000: global_a = 20

   # Boucle infinie:
   [Load]  0x1004: lecture global_b
   [Store] 0x1004: global_b++
   [Load]  0x1004: lecture global_b
   [Store] 0x1004: global_b++
   ...
   ```

### Dans les Waveforms Questa

Chercher ces signaux:
- `data_req = 1` : Requête d'accès data
- `data_we = 1` : Write (Store)
- `data_we = 0` : Read (Load)
- `data_addr` : Adresse (devrait être 0x1000+)
- `data_wdata` : Données écrites
- `data_rdata` : Données lues

## Dépannage

### Erreur: "undefined reference to `_start`"
→ Vérifier que startup.s est bien compilé

### Erreur: "section .text will not fit in region ROM"
→ Code trop gros pour 8KB, réduire ou augmenter ROM_SIZE

### Simulation: Pas d'accès RAM visible
→ Vérifier que les variables sont bien `volatile`
→ Compiler avec `-O2` (pas `-O0` qui peut supprimer les accès)

### Simulation: Core ne boot pas
→ Vérifier l'adresse de boot (0x00000000)
→ Vérifier que le .hex est bien chargé dans ROM
→ Vérifier la table de vecteurs dans startup.s

## Fichiers Générés

Après compilation, vous aurez:
- `hello_world.elf` : Fichier binaire RISC-V
- `hello_world.hex` : Format Intel HEX pour simulation
- `hello_world.bin` : Binaire brut
- `hello_world.dump` : Disassembly complet
- `hello_world.map` : Carte mémoire (linker map)

## Prochaines Étapes

1. ✅ Compiler le programme
2. ✅ Copier .hex vers /adam/mem0.hex
3. ⏳ Simuler avec Questa
4. ⏳ Vérifier accès RAM dans waveforms
5. ⏳ Valider séquence d'instructions
6. ⏳ Passer à l'intégration DIFT
