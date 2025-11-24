# Solution: Pre-initialized Memory Approach

## Problème Identifié

La variable globale `volatile int tainted_input = 100` ne fonctionnait pas car:
1. Elle est placée dans la section `.data`
2. Cette section doit être **copiée de ROM vers RAM** par `startup.s`
3. Si la copie ne fonctionne pas, la RAM contient n'importe quoi (pas 100)
4. Le disassembly montrait `0064` mais interprété comme instruction, pas comme data

## Solution: Pré-initialiser dmem et tmem

Au lieu de dépendre de l'initialisation `.data`, on pré-charge **directement** les mémoires du testbench:

### Fichiers Créés

**`/home/user/adam/bhv/dmem.hex`**
```
64000000    ← Index 0 (addr 0x1000) = 0x00000064 = 100 en décimal
00000000    ← Index 1 (addr 0x1004) = 0
00000000    ← Index 2 (addr 0x1008) = 0
...
```

**`/home/user/adam/bhv/tmem_pretaint.hex`** (déjà existant)
```
F    ← Index 0 (addr 0x1000) = TAINTED
0    ← Index 1 (addr 0x1004) = TRUSTED
0    ← Index 2 (addr 0x1008) = TRUSTED
...
```

### Code main.c

```c
int main(void) {
    volatile int *tainted_source = (volatile int *)0x1000;  // Pre-loaded
    volatile int a, b, sum;

    a = *tainted_source;  // LOAD: data=100, tag=1111
    b = 20;               // IMMEDIATE: data=20, tag=0000
    sum = a + b;          // ADD: data=120, tag=1111

    volatile int *result_addr = (volatile int *)0x1010;
    *result_addr = sum;   // STORE: data=120, tag=1111

    while(1);
}
```

### Avantages

1. ✅ **Pas de dépendance sur .data section** - évite les problèmes de copie ROM→RAM
2. ✅ **Contrôle total** - on sait exactement ce qu'il y a en mémoire
3. ✅ **Adresse fixe connue** - 0x1000 = facile à tracker dans les waveforms
4. ✅ **Valeur visible** - 100 (0x64) apparaîtra clairement dans data_rdata
5. ✅ **Tag visible** - 4'b1111 apparaîtra dans data_rdata_tag

## Séquence Attendue dans les Waveforms

### 1. Premier Load (adresse 0x1000)

```
data_req      = 1
data_we       = 0              ← READ
data_addr     = 0x00001000     ← Adresse pré-chargée
data_be       = 4'b1111

Cycle suivant:
data_rvalid   = 1
data_rdata    = 0x00000064     ← ✅ VALEUR 100 VISIBLE!
data_rdata_tag = 4'b1111       ← ✅ TAG TAINTED!
```

### 2. Store de 'a' (quelque part en stack/bss)

```
data_req      = 1
data_we       = 1              ← WRITE
data_addr     = 0x000010XX     ← Adresse de 'a'
data_wdata    = 0x00000064     ← ✅ Valeur 100 propagée
data_wdata_tag = 4'b1111       ← ✅ Tag propagé!
```

### 3. Load immédiat 20 → 'b'

```
Pas d'accès mémoire, juste:
li x16, 20
tag_regfile[x16] = 0  (trusted)
```

### 4. Store de 'b'

```
data_we       = 1
data_wdata    = 0x00000014     ← 20 en hex
data_wdata_tag = 4'b0000       ← Trusted
```

### 5. Addition (dans le core)

```
Pas d'accès mémoire
add x17, x15, x16
tag_result = tag(x15) | tag(x16) = 1 | 0 = 1
```

### 6. Store final à 0x1010

```
data_req      = 1
data_we       = 1              ← WRITE
data_addr     = 0x00001010     ← Adresse explicite
data_wdata    = 0x00000078     ← ✅ 120 = 100+20
data_wdata_tag = 4'b1111       ← ✅ TAG TAINTED PROPAGÉ!
```

## Compilation

```bash
cd /home/user/adam/software/hello_world

riscv32-unknown-elf-gcc \
    -march=rv32imc_zicsr \
    -mabi=ilp32 \
    -O2 -g \
    -T link.ld \
    -nostdlib \
    -o hello_world.elf \
    src/startup.s \
    src/main.c \
    -lc_nano -lgcc -lnosys

riscv32-unknown-elf-objcopy -O ihex hello_world.elf hello_world.hex
cp hello_world.hex ../../mem0.hex
```

## Vérification

```bash
# Vérifier que les fichiers existent
ls -l /home/user/adam/bhv/dmem.hex
ls -l /home/user/adam/bhv/tmem_pretaint.hex
ls -l /home/user/adam/mem0.hex

# Vérifier le contenu de dmem.hex
head -5 /home/user/adam/bhv/dmem.hex
# Attendu: 64000000 (100 en little-endian)

# Vérifier le contenu de tmem_pretaint.hex
head -5 /home/user/adam/bhv/tmem_pretaint.hex
# Attendu: F (tainted)
```

## Debugging

### Si tu ne vois toujours pas 100:

1. **Vérifier dmem.hex:**
   ```bash
   cat /home/user/adam/bhv/dmem.hex | head -1
   ```
   Doit être: `64000000`

2. **Vérifier que le testbench charge dmem.hex:**
   ```systemverilog
   simple_mem #(
       .SIZE      (RAM_SIZE),
       .INIT_FILE ("dmem.hex")  // ← Doit être présent
   ) dmem (
   ```

3. **Vérifier dans les waveforms au premier load:**
   - Chercher `data_addr = 0x1000`
   - Vérifier `data_rdata` au cycle suivant
   - Devrait montrer `0x00000064`

### Si le tag n'est pas 4'b1111:

1. **Vérifier tmem_pretaint.hex:**
   ```bash
   cat /home/user/adam/bhv/tmem_pretaint.hex | head -1
   ```
   Doit être: `F`

2. **Vérifier que le testbench charge tmem_pretaint.hex:**
   ```systemverilog
   tag_mem #(
       .SIZE      (RAM_SIZE),
       .INIT_FILE ("tmem_pretaint.hex")  // ← Doit pointer ici
   ) tmem (
   ```

## Résumé

| Fichier | Contenu | Index 0 | Effet |
|---------|---------|---------|-------|
| `dmem.hex` | Data values | `64000000` (100) | Pré-charge la valeur |
| `tmem_pretaint.hex` | Tag values | `F` (1111) | Pré-charge le tag |
| `mem0.hex` | Instructions | Code compilé | Programme à exécuter |

**Maintenant tu devrais voir:**
- ✅ La valeur 100 dans `data_rdata` lors du premier load
- ✅ Le tag `4'b1111` dans `data_rdata_tag`
- ✅ La propagation jusqu'au store final
