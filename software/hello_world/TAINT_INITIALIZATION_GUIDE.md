# Guide: Comment Créer des Variables Tainted pour Tests DIFT

## Le Problème

```c
int a = 10;  // Génère: li x15, 10 → tag(x15) = 0 (constante immediate = trusted)
             //         sw x15, addr → tag_mem[addr] = 0
```

**Toutes les constantes immédiates sont automatiquement trusted!**

---

## Solutions

### ✅ Solution 1: Pré-initialiser Tag Memory ⭐ **RECOMMANDÉ**

**Principe:** Marquer certaines adresses comme tainted AVANT l'exécution du programme.

#### Étape 1: Déterminer les adresses mémoire

Compiler et regarder le fichier `.map` ou `.dump`:

```bash
cd software/build
make hello_world
riscv32-unknown-elf-nm hello_world/hello_world.elf | grep -E "(^a$|^b$|^sum$)"
```

Output exemple:
```
00001000 b a
00001004 b b
00001008 b sum
```

#### Étape 2: Créer tmem_pretaint.hex

Calculer l'index dans tag_mem:
- Adresse 0x1000 → index = (0x1000 - 0x1000) / 4 = 0
- Adresse 0x1004 → index = (0x1004 - 0x1000) / 4 = 1
- Adresse 0x1008 → index = (0x1008 - 0x1000) / 4 = 2

Créer `tmem_pretaint.hex`:
```
F    # Index 0: 'a' tainted (4'b1111)
0    # Index 1: 'b' trusted (4'b0000)
0    # Index 2: 'sum' trusted initially
0
0
... (reste en 0)
```

#### Étape 3: Utiliser dans le test bench

Modifier `cv32e40p_tb.sv`:
```systemverilog
tag_mem #(
    .SIZE      (RAM_SIZE),
    .INIT_FILE ("tmem_pretaint.hex")  // ← Utiliser le fichier pré-taint
) tmem (
    ...
);
```

#### Étape 4: Code test (main_v1b_pretaint.c)

```c
int main(void) {
    volatile int a = 10;  // Store en RAM
    volatile int b = 20;
    volatile int sum;

    // IMPORTANT: Re-load pour récupérer les tags!
    int temp_a = a;       // Load → rdata_tag = 1111 (tainted!)
    int temp_b = b;       // Load → rdata_tag = 0000

    sum = temp_a + temp_b; // Tag(sum) = 1111 (tainted)

    while(1);
}
```

**Attendu dans waveforms:**
```
[Time] DREAD: addr=0x1000 (load a)
[Time] TAG_READ: tags[3:0]=1111 ← tag pré-taint récupéré!
[Time] DREAD: addr=0x1004 (load b)
[Time] TAG_READ: tags[3:0]=0000
[Time] DWRITE: addr=0x1008 (store sum)
[Time] TAG_WRITE: tag[3:0]=1111 ← sum propagé comme tainted!
```

---

### ✅ Solution 2: Via CSR (TPR/TCR)

**Principe:** Utiliser les registres DIFT pour contrôler le tagging.

```c
#define CSR_TPR 0x7C0

write_csr(CSR_TPR, 0xFFFFFFFF);  // Activer tainting
int a = 10;                       // a sera tainted
write_csr(CSR_TPR, 0x00000000);  // Désactiver
int b = 20;                       // b sera trusted
```

**Avantages:**
- Dynamique
- Contrôle précis

**Inconvénients:**
- Dépend de l'implémentation du core
- Plus complexe

---

### ✅ Solution 3: Source Externe Simulée

**Principe:** Créer une zone mémoire "spéciale" pré-taintée.

```c
#define TAINTED_SOURCE_ADDR 0x2000
volatile int *tainted_src = (int*)TAINTED_SOURCE_ADDR;

int a = *tainted_src;  // Load depuis source tainted
int b = 20;            // Normal (trusted)
int sum = a + b;       // sum tainted
```

Initialiser `tmem_pretaint.hex`:
```
# Adresse 0x2000 → index = (0x2000 - 0x1000) / 4 = 1024
# Ligne 1024: F (tainted)
```

**Avantages:**
- Simule une vraie source externe (UART, réseau, etc.)
- Réaliste pour tests de sécurité

---

## Comparaison des Solutions

| Solution | Complexité | Réalisme | Flexibilité |
|----------|-----------|----------|-------------|
| **1. Pré-init Tag Memory** | ⭐ Simple | Moyen | Faible |
| **2. CSR (TPR/TCR)** | ⭐⭐ Moyen | Moyen | Élevée |
| **3. Source Externe** | ⭐ Simple | ⭐⭐⭐ Élevé | Moyen |

---

## Recommandation

**Pour débuter:** Solution 1 (Pré-initialisation)
- Le plus simple à mettre en place
- Pas besoin de modifier le core
- Suffit pour valider la propagation

**Pour tests avancés:** Solution 3 (Source Externe)
- Plus réaliste
- Simule des données venant de l'extérieur
- Bon pour valider des scénarios de sécurité

**Pour production:** Solution 2 (CSR)
- Contrôle dynamique
- Politique de sécurité configurable

---

## Script Helper: Générer tmem_pretaint.hex

```bash
#!/bin/bash
# generate_pretaint.sh

# Obtenir les adresses depuis le .elf
ADDR_A=$(riscv32-unknown-elf-nm hello_world.elf | grep " a$" | cut -d' ' -f1)
ADDR_B=$(riscv32-unknown-elf-nm hello_world.elf | grep " b$" | cut -d' ' -f1)

# Calculer les index (base RAM = 0x1000)
INDEX_A=$(( (0x$ADDR_A - 0x1000) / 4 ))
INDEX_B=$(( (0x$ADDR_B - 0x1000) / 4 ))

echo "Génération de tmem_pretaint.hex"
echo "a at 0x$ADDR_A → index $INDEX_A (tainted)"
echo "b at 0x$ADDR_B → index $INDEX_B (trusted)"

# Créer le fichier
{
    for i in $(seq 0 2047); do
        if [ $i -eq $INDEX_A ]; then
            echo "F"  # a = tainted
        else
            echo "0"  # reste = trusted
        fi
    done
} > tmem_pretaint.hex

echo "Fichier créé: tmem_pretaint.hex"
```

---

## Vérification

Dans les waveforms, vérifier:

1. ✅ Après load de la variable tainted:
   - `data_rdata_tag = 4'b1111`

2. ✅ Après addition:
   - `data_wdata_tag = 4'b1111` (propagation)

3. ✅ Tag memory:
   - Lecture retourne les bons tags
   - Écriture met à jour correctement

---

## Exemples de Tests

### Test 1: Trusted + Trusted = Trusted
```c
int a = 10;  // trusted (tag=0)
int b = 20;  // trusted (tag=0)
int sum = a + b;  // trusted (tag=0)
```

### Test 2: Tainted + Trusted = Tainted
```c
int a = 10;  // tainted (pré-init tag=1)
int b = 20;  // trusted (tag=0)
int sum = a + b;  // tainted (tag=1)
```

### Test 3: Tainted + Tainted = Tainted
```c
int a = 10;  // tainted (pré-init tag=1)
int b = 20;  // tainted (pré-init tag=1)
int sum = a + b;  // tainted (tag=1)
```
