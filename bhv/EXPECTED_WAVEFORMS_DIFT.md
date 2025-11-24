# Guide: Résultats Attendus dans les Waveforms DIFT

## Programme de Test

Le programme `main.c` exécute cette séquence:

```c
volatile int tainted_input = 100;  // Global @ 0x1000 (pré-tainted)

int main(void) {
    volatile int a, b, sum;

    a = tainted_input;  // Load tainted → tag récupéré
    b = 20;             // Constante trusted
    sum = a + b;        // Addition avec propagation

    while(1);
}
```

## Adresses Mémoire Typiques

Basé sur le linker script (ROM @ 0x0, RAM @ 0x1000):

| Variable | Section | Adresse Typique | tag_mem Index |
|----------|---------|-----------------|---------------|
| `tainted_input` | .data | 0x00001000 | 0 |
| `a` | .bss | 0x00001004 | 1 |
| `b` | .bss | 0x00001008 | 2 |
| `sum` | .bss | 0x0000100C | 3 |

**Note:** Les adresses exactes dépendent de la compilation. Utilisez:
```bash
riscv32-unknown-elf-nm hello_world.elf | grep -E "(tainted_input|a|b|sum)"
```

## Séquence d'Exécution Attendue

### ÉTAPE 1: Load `tainted_input` → `a`

**Instruction assembleur:** `lw x15, 0(gp)` où gp pointe vers tainted_input

**Signaux OBI - Load depuis mémoire:**
```
Cycle N:
  data_req      = 1
  data_we       = 0              ← READ
  data_addr     = 0x00001000     ← Adresse de tainted_input
  data_be       = 4'b1111        ← Load word (4 bytes)
  data_gnt      = 1

Cycle N+1:
  data_rvalid   = 1
  data_rdata    = 0x00000064     ← Valeur 100 (0x64)
  data_rdata_tag = 4'b1111       ← ✅ TAG TAINTED RÉCUPÉRÉ!
```

**Effet interne du core:**
- `regfile[x15] ← 0x00000064`
- `tag_regfile[x15] ← 1` (calculé depuis data_rdata_tag par OR: |4'b1111 = 1)

**Signaux OBI - Store dans `a`:**
```
Cycle N+2:
  data_req      = 1
  data_we       = 1              ← WRITE
  data_addr     = 0x00001004     ← Adresse de 'a'
  data_be       = 4'b1111
  data_wdata    = 0x00000064     ← Valeur 100
  data_wdata_tag = 4'b1111       ← ✅ TAG PROPAGÉ!
  data_we_tag   = 1
  data_gnt      = 1
```

**Effet sur tag_mem:**
- `tag_mem[1] ← 4'b1111` (index 1 = adresse 0x1004)

---

### ÉTAPE 2: Load immediate `20` → `b`

**Instruction assembleur:** `li x16, 20` (ou `addi x16, x0, 20`)

**Effet interne du core:**
- `regfile[x16] ← 0x00000014` (20 en décimal)
- `tag_regfile[x16] ← 0` ← Les immédiats sont TRUSTED

**Signaux OBI - Store dans `b`:**
```
Cycle N+3:
  data_req      = 1
  data_we       = 1              ← WRITE
  data_addr     = 0x00001008     ← Adresse de 'b'
  data_be       = 4'b1111
  data_wdata    = 0x00000014     ← Valeur 20
  data_wdata_tag = 4'b0000       ← ✅ TAG TRUSTED (immédiat)
  data_we_tag   = 1
  data_gnt      = 1
```

**Effet sur tag_mem:**
- `tag_mem[2] ← 4'b0000` (index 2 = adresse 0x1008)

---

### ÉTAPE 3: Load `a`

**Instruction assembleur:** `lw x17, [a]`

**Signaux OBI:**
```
Cycle N+4:
  data_req      = 1
  data_we       = 0              ← READ
  data_addr     = 0x00001004     ← Adresse de 'a'
  data_be       = 4'b1111
  data_gnt      = 1

Cycle N+5:
  data_rvalid   = 1
  data_rdata    = 0x00000064     ← Valeur 100
  data_rdata_tag = 4'b1111       ← ✅ TAG TAINTED (récupéré depuis tag_mem[1])
```

**Effet interne:**
- `regfile[x17] ← 0x00000064`
- `tag_regfile[x17] ← 1`

---

### ÉTAPE 4: Load `b`

**Instruction assembleur:** `lw x18, [b]`

**Signaux OBI:**
```
Cycle N+6:
  data_req      = 1
  data_we       = 0              ← READ
  data_addr     = 0x00001008     ← Adresse de 'b'
  data_be       = 4'b1111
  data_gnt      = 1

Cycle N+7:
  data_rvalid   = 1
  data_rdata    = 0x00000014     ← Valeur 20
  data_rdata_tag = 4'b0000       ← ✅ TAG TRUSTED
```

**Effet interne:**
- `regfile[x18] ← 0x00000014`
- `tag_regfile[x18] ← 0`

---

### ÉTAPE 5: Addition `a + b` → registre

**Instruction assembleur:** `add x19, x17, x18`

**Pas de signaux OBI** (opération purement dans le core)

**Effet interne - Pipeline EX stage:**
- `result = x17 + x18 = 100 + 20 = 120`
- `tag_result = tag_regfile[x17] | tag_regfile[x18]`
- `tag_result = 1 | 0 = 1` ← ✅ PROPAGATION!

**Effet interne - Pipeline WB stage:**
- `regfile[x19] ← 0x00000078` (120 en hex)
- `tag_regfile[x19] ← 1` ← ✅ RÉSULTAT TAINTED

---

### ÉTAPE 6: Store `sum`

**Instruction assembleur:** `sw x19, [sum]`

**Signaux OBI:**
```
Cycle N+8:
  data_req      = 1
  data_we       = 1              ← WRITE
  data_addr     = 0x0000100C     ← Adresse de 'sum'
  data_be       = 4'b1111
  data_wdata    = 0x00000078     ← Valeur 120
  data_wdata_tag = 4'b1111       ← ✅ TAG TAINTED PROPAGÉ!
  data_we_tag   = 1
  data_gnt      = 1
```

**Effet sur tag_mem:**
- `tag_mem[3] ← 4'b1111` (index 3 = adresse 0x100C)

---

## Résumé de la Propagation

```
┌──────────────────┬──────────┬──────────┬────────────────┐
│ Opération        │ Valeur   │ Tag      │ Source Tag     │
├──────────────────┼──────────┼──────────┼────────────────┤
│ tainted_input    │ 100      │ TAINTED  │ Pré-init       │
│ Load → reg x15   │ 100      │ TAINTED  │ tag_mem[0]     │
│ Store → a        │ 100      │ TAINTED  │ tag_reg[x15]   │
│                  │          │          │                │
│ li x16, 20       │ 20       │ TRUSTED  │ Immédiat       │
│ Store → b        │ 20       │ TRUSTED  │ tag_reg[x16]   │
│                  │          │          │                │
│ Load a → x17     │ 100      │ TAINTED  │ tag_mem[1]     │
│ Load b → x18     │ 20       │ TRUSTED  │ tag_mem[2]     │
│                  │          │          │                │
│ ADD x19,x17,x18  │ 120      │ TAINTED  │ 1 | 0 = 1      │
│ Store → sum      │ 120      │ TAINTED  │ tag_reg[x19]   │
└──────────────────┴──────────┴──────────┴────────────────┘
```

## Signaux Clés à Observer dans Questa

### Groupe 1: Data Memory OBI Bus
```
/cv32e40p_tb/data_req
/cv32e40p_tb/data_gnt
/cv32e40p_tb/data_rvalid
/cv32e40p_tb/data_addr       ← Chercher 0x1000, 0x1004, 0x1008, 0x100C
/cv32e40p_tb/data_we         ← 0=READ, 1=WRITE
/cv32e40p_tb/data_be
/cv32e40p_tb/data_wdata
/cv32e40p_tb/data_rdata
```

### Groupe 2: Tag Memory Signals (DIFT)
```
/cv32e40p_tb/data_wdata_tag  ← Vérifier 4'b1111 vs 4'b0000
/cv32e40p_tb/data_rdata_tag  ← Vérifier 4'b1111 vs 4'b0000
/cv32e40p_tb/data_we_tag     ← Tag write enable
/cv32e40p_tb/data_gnt_tag
/cv32e40p_tb/data_rvalid_tag
```

### Groupe 3: Tag Memory Internal (si accessible)
```
/cv32e40p_tb/tmem/tag_mem[0]  ← Devrait être 4'b1111 (tainted_input)
/cv32e40p_tb/tmem/tag_mem[1]  ← Devrait devenir 4'b1111 après store a
/cv32e40p_tb/tmem/tag_mem[2]  ← Devrait être 4'b0000 après store b
/cv32e40p_tb/tmem/tag_mem[3]  ← Devrait devenir 4'b1111 après store sum
```

### Groupe 4: Core Tag Register File (si accessible dans RTL modifié)
```
/cv32e40p_tb/dut/tag_regfile[15]  ← Après load tainted_input: devrait être 1
/cv32e40p_tb/dut/tag_regfile[16]  ← Après li 20: devrait être 0
/cv32e40p_tb/dut/tag_regfile[19]  ← Après add: devrait être 1
```

## Checklist de Validation

- [ ] ✅ **tag_mem[0] initialisé à F** avant le début du programme
- [ ] ✅ **Premier load récupère data_rdata_tag = 4'b1111** (tainted_input)
- [ ] ✅ **Store de 'a' écrit data_wdata_tag = 4'b1111** (propagation)
- [ ] ✅ **Store de 'b' écrit data_wdata_tag = 4'b0000** (immédiat trusted)
- [ ] ✅ **Load de 'a' renvoie data_rdata_tag = 4'b1111** (relecture)
- [ ] ✅ **Load de 'b' renvoie data_rdata_tag = 4'b0000** (relecture)
- [ ] ✅ **Store de 'sum' écrit data_wdata_tag = 4'b1111** (propagation après ADD)
- [ ] ✅ **tag_mem[3] contient 4'b1111** après store sum

## Debugging

### Si data_rdata_tag est toujours 0000:

1. **Vérifier tag_mem.sv:**
   - Le fichier `tmem_pretaint.hex` est-il bien chargé?
   - La logique de lecture est-elle correcte?

2. **Vérifier cv32e40p_tb.sv:**
   - L'interface tag_mem est-elle bien connectée?
   - `INIT_FILE` pointe-t-il vers `tmem_pretaint.hex`?

3. **Vérifier tmem_pretaint.hex:**
   - Index 0 contient-il bien `F`?
   - Le fichier existe-t-il dans `/adam/bhv/`?

### Si data_wdata_tag est toujours 0000:

1. **Vérifier le core CV32E40P:**
   - Les modifications DIFT sont-elles bien intégrées?
   - Le signal `data_wdata_tag` est-il bien connecté depuis le core?

2. **Vérifier tag_regfile dans le core:**
   - Les registres de tags sont-ils mis à jour lors des loads?
   - La propagation des tags fonctionne-t-elle dans l'ALU?

### Si sum a le mauvais tag:

1. **Vérifier la propagation ALU:**
   - L'opération ADD propage-t-elle bien: `tag_result = tag_rs1 | tag_rs2`?
   - Le tag_result est-il bien écrit dans tag_regfile[rd]?

## Commandes Utiles

### Compiler et générer le hex
```bash
cd /home/user/adam/software/hello_world
riscv32-unknown-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -O2 -T link.ld -nostdlib -o hello_world.elf src/startup.s src/main.c
riscv32-unknown-elf-objcopy -O ihex hello_world.elf hello_world.hex
cp hello_world.hex ../../mem0.hex
```

### Vérifier les adresses
```bash
riscv32-unknown-elf-nm hello_world.elf | grep -E "(tainted_input|main|_start)"
riscv32-unknown-elf-objdump -d hello_world.elf | grep -A 20 "<main>:"
```

### Générer tmem_pretaint.hex automatiquement
```bash
cd /home/user/adam/software/build
./generate_tmem_pretaint.sh
```

### Lancer la simulation
```bash
cd /home/user/adam/bhv
# Votre commande Questa ici, par exemple:
vsim -do run_cv32e40p_tb.do
```

## Prochaines Étapes

Après validation de ce test simple:

1. **Test avec plusieurs variables tainted:** Modifier tmem_pretaint.hex pour tainter plusieurs sources
2. **Test d'opérations complexes:** Multiplication, shift, comparaison
3. **Test de branches conditionnelles:** `if (tainted_var)` devrait propager le tag au PC (optionnel)
4. **Test de détection:** Ajouter un module de détection qui alerte si des données tainted atteignent certaines zones
