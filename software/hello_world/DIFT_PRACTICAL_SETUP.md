# Guide Pratique: Setup DIFT avec Variable Tainted

## Étape 1: Compiler le Programme

```bash
cd /home/user/adam/software/build
make hello_world
```

## Étape 2: Trouver les Adresses Mémoire

Utiliser `riscv32-unknown-elf-nm` pour trouver l'adresse de `tainted_input`:

```bash
riscv32-unknown-elf-nm hello_world/hello_world.elf | grep tainted_input
```

**Output attendu:**
```
00001000 D tainted_input
```

Ou utiliser `objdump` pour voir toutes les variables:

```bash
riscv32-unknown-elf-objdump -t hello_world/hello_world.elf | grep -E "(tainted_input|\.data|\.bss)"
```

**Note:**
- Variables initialisées (comme `tainted_input = 100`) sont en `.data` section
- Variables non-initialisées (comme `a, b, sum`) sont en `.bss` section
- La RAM commence à 0x1000 selon notre linker script

## Étape 3: Calculer l'Index dans tag_mem

**Formule:**
```
index = (address - RAM_BASE) / 4
```

Où:
- `RAM_BASE = 0x1000` (défini dans link.ld)
- Division par 4 car chaque word (32 bits) a un tag de 4 bits

**Exemple:**

Si `tainted_input` est à l'adresse `0x00001000`:
```
index = (0x1000 - 0x1000) / 4 = 0
```

Si une autre variable est à `0x00001004`:
```
index = (0x1004 - 0x1000) / 4 = 1
```

Si une variable est à `0x00001008`:
```
index = (0x1008 - 0x1000) / 4 = 2
```

## Étape 4: Créer tmem_pretaint.hex

Le fichier `tmem_pretaint.hex` contient les tags initiaux pour chaque word de la RAM.

**Format:**
- Un tag par ligne (format hexadécimal 1 chiffre)
- `F` = 4'b1111 = TAINTED
- `0` = 4'b0000 = TRUSTED
- Index 0 correspond à l'adresse RAM_BASE (0x1000)
- Index 1 correspond à RAM_BASE + 4 (0x1004)
- etc.

**Exemple pour notre cas:**

Si `tainted_input` est à l'index 0, créer ce fichier:

```
F
0
0
0
0
0
...
```

## Étape 5: Script Automatique

Voici un script bash pour automatiser le processus:

```bash
#!/bin/bash
# generate_tmem_pretaint.sh

ELF_FILE="hello_world/hello_world.elf"
OUTPUT_FILE="../../bhv/tmem_pretaint.hex"
RAM_BASE=0x1000
TAG_MEM_SIZE=2048  # 8KB RAM / 4 bytes per word = 2048 entries

echo "=== Génération de tmem_pretaint.hex ==="

# Trouver l'adresse de tainted_input
ADDR_HEX=$(riscv32-unknown-elf-nm $ELF_FILE | grep " tainted_input" | cut -d' ' -f1)

if [ -z "$ADDR_HEX" ]; then
    echo "ERREUR: Variable 'tainted_input' non trouvée dans l'ELF!"
    exit 1
fi

ADDR_DEC=$((16#$ADDR_HEX))
INDEX=$(( ($ADDR_DEC - $RAM_BASE) / 4 ))

echo "tainted_input trouvée à l'adresse: 0x$ADDR_HEX"
echo "Index dans tag_mem: $INDEX"

# Créer le fichier avec tous les tags à 0 sauf tainted_input
{
    for i in $(seq 0 $((TAG_MEM_SIZE - 1))); do
        if [ $i -eq $INDEX ]; then
            echo "F"  # TAINTED
        else
            echo "0"  # TRUSTED
        fi
    done
} > $OUTPUT_FILE

echo "Fichier créé: $OUTPUT_FILE"
echo "✅ Tag memory initialisée avec tainted_input = TAINTED"
```

**Utilisation:**
```bash
cd /home/user/adam/software/build
chmod +x generate_tmem_pretaint.sh
./generate_tmem_pretaint.sh
```

## Étape 6: Vérifier le Fichier Généré

```bash
head -20 ../../bhv/tmem_pretaint.hex
```

**Output attendu (si index = 0):**
```
F
0
0
0
...
```

## Étape 7: Modifier le Testbench

S'assurer que `cv32e40p_tb.sv` utilise le fichier pretaint:

```systemverilog
tag_mem #(
    .SIZE      (RAM_SIZE),
    .INIT_FILE ("tmem_pretaint.hex")  // ← Utiliser le fichier
) tmem (
    ...
);
```

## Étape 8: Simuler et Observer

```bash
cd /home/user/adam/bhv
./run_questa.sh  # Ou votre commande de simulation
```

**Signaux à observer dans les waveforms:**

1. **Premier load (tainted_input):**
   - `data_req = 1`
   - `data_addr = 0x00001000` (ou l'adresse trouvée)
   - `data_rdata = 100` (la valeur)
   - `data_rdata_tag = 4'b1111` ✅ **TAG RÉCUPÉRÉ!**

2. **Store de a:**
   - `data_we = 1`
   - `data_wdata = 100`
   - `data_wdata_tag = 4'b1111` ✅ **TAG PROPAGÉ!**

3. **Store de sum:**
   - `data_we = 1`
   - `data_wdata = 120` (100 + 20)
   - `data_wdata_tag = 4'b1111` ✅ **TAG PROPAGÉ APRÈS ADD!**

## Résumé des Commandes

```bash
# 1. Compiler
cd /home/user/adam/software/build
make hello_world

# 2. Trouver l'adresse
riscv32-unknown-elf-nm hello_world/hello_world.elf | grep tainted_input

# 3. Calculer l'index manuellement
# index = (address - 0x1000) / 4

# 4. Générer tmem_pretaint.hex (script automatique)
./generate_tmem_pretaint.sh

# 5. Simuler
cd /home/user/adam/bhv
./run_questa.sh  # Ou votre commande
```

## Debugging

Si les tags ne se propagent pas:

1. ✅ **Vérifier que tainted_input est bien une variable globale** (pas locale)
2. ✅ **Vérifier l'adresse dans le .elf** correspond à l'index dans tmem_pretaint.hex
3. ✅ **Vérifier que le testbench charge bien tmem_pretaint.hex**
4. ✅ **Vérifier dans les waveforms** que `data_rdata_tag = 4'b1111` lors du premier load
5. ✅ **Vérifier les signaux internes du core** (si accessible): `tag_regfile[x15]` devrait être 1 après le load

## Exemple Complet avec Adresse Réelle

Supposons que vous obtenez:
```
$ riscv32-unknown-elf-nm hello_world.elf | grep tainted_input
00001000 D tainted_input
```

Alors:
- Adresse: `0x00001000`
- RAM_BASE: `0x00001000`
- Index: `(0x1000 - 0x1000) / 4 = 0`

Créer `tmem_pretaint.hex`:
```
F    ← Index 0 = addr 0x1000 = tainted_input (TAINTED)
0    ← Index 1 = addr 0x1004
0    ← Index 2 = addr 0x1008
...
```

Dans la simulation, vous devriez voir:
```
[Time] DREAD: addr=00001000 rdata=00000064 rdata_tag=F  ← Load tainted_input
[Time] DWRITE: addr=000010XX wdata=00000064 wdata_tag=F ← Store a
[Time] DWRITE: addr=000010YY wdata=00000078 wdata_tag=F ← Store sum (120 = 0x78)
```
