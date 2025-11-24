# Tests Simplifiés pour DIFT Tag Propagation

## Versions Disponibles

### Version 1: Ultra-Simple (main_v1_simple.c) ⭐ RECOMMANDÉ
```c
int a = 10, b = 20;
sum = a + b;
```

**Attendu dans les waveforms:**
```
Cycle X:   Store a = 10     → tag_mem[addr_a] = 0 (si clean)
Cycle X+1: Store b = 20     → tag_mem[addr_b] = 0
Cycle X+2: Store sum = 0    → tag_mem[addr_sum] = 0
Cycle Y:   Load a           → rdata_tag = 0
Cycle Y+1: Load b           → rdata_tag = 0
Cycle Y+2: ADD (registres)  → tag propagation interne au core
Cycle Y+3: Store sum = 30   → wdata_tag = 0 (car a et b clean)
                            → tag_mem[addr_sum] = 0
```

---

### Version 2: Chaîne d'Opérations (main_v2_chain.c)
```c
result = a + b;      // 30
result = result * 2; // 60
```

**Test de propagation:**
- Si `a` ou `b` tainted → `result` après ADD sera tainted
- `result * 2` propage le tag de `result`

---

### Version 3: Multi-Opérations (main_v3_multi_ops.c)
```c
result = a + b;      // ADD
result = result * 2; // MUL
result = result - c; // SUB
```

**Voir différents types d'opérations:**
- Addition, Multiplication, Soustraction
- Toutes doivent propager les tags correctement

---

### Version 4: Test Clean vs Tainted (main_v4_propagation_test.c)
```c
result1 = clean_a + clean_b;     // devrait rester clean
result2 = result1 + tainted_x;   // devrait devenir tainted
```

**Test de politique DIFT:**
- Clean + Clean → Clean
- Clean + Tainted → Tainted
- Tainted + Tainted → Tainted

---

## Compilation

Pour chaque version, remplacer `main.c`:

```bash
# Version 1 (ultra-simple)
cp src/main_v1_simple.c src/main.c
cd ../../software/build
make hello_world
cp hello_world/hello_world.hex /adam/mem0.hex

# Version 2 (chaîne)
cp src/main_v2_chain.c src/main.c
# ... même processus

# etc.
```

---

## Ce que tu vas voir dans les Waveforms

### Phase 1: Initialisation des variables
```
[Time] DWRITE: addr=0x00001000 data=0x0000000a be=1111  (a = 10)
[Time] TAG_WRITE: addr=0x00001000 tag[3:0]=0000 be=1111
[Time] DWRITE: addr=0x00001004 data=0x00000014 be=1111  (b = 20)
[Time] TAG_WRITE: addr=0x00001004 tag[3:0]=0000 be=1111
```

### Phase 2: Opération Addition
```
[Time] DREAD: addr=0x00001000                           (load a)
[Time] TAG_READ: tags[3:0]=0000
[Time] DREAD: addr=0x00001004                           (load b)
[Time] TAG_READ: tags[3:0]=0000
[Time] DWRITE: addr=0x00001008 data=0x0000001e be=1111  (store sum=30)
[Time] TAG_WRITE: addr=0x00001008 tag[3:0]=0000 be=1111 (sum hérite des tags)
```

### Signaux Clés à Observer

**Data Interface:**
- `data_addr` : adresses des variables (0x1000, 0x1004, 0x1008...)
- `data_wdata` : valeurs écrites (10, 20, 30...)
- `data_rdata` : valeurs lues

**Tag Interface:** ⭐
- `data_wdata_tag[3:0]` : tags écrits (0000=clean, 1111=tainted)
- `data_rdata_tag[3:0]` : tags lus
- `data_we_tag` : écriture de tag active

---

## Règles de Propagation DIFT Attendues

```
Opération      Tag(A)  Tag(B)  →  Tag(Result)
-------------------------------------------------
ADD/SUB/MUL    0       0       →  0 (clean)
ADD/SUB/MUL    0       1       →  1 (tainted)
ADD/SUB/MUL    1       0       →  1 (tainted)
ADD/SUB/MUL    1       1       →  1 (tainted)

Formule: Tag(Result) = Tag(A) OR Tag(B)
```

---

## Débogage

### Si les tags restent toujours 0:
- ✅ Normal si le core ne génère pas encore les tags
- ⚠️ Vérifier que `data_we_tag` s'active lors des stores
- ⚠️ Vérifier que le core propage les tags dans EX stage

### Si les tags sont rouges (X):
- ✅ Normal quand `data_rvalid_tag = 0`
- ⚠️ Vérifier uniquement quand `rvalid = 1`

### Pour forcer un tag tainted:
Modifier le core pour marquer `tainted_x` avec tag=1 dès son initialisation.

---

## Prochaines Étapes

1. ✅ Compiler Version 1 (ultra-simple)
2. ⏳ Simuler avec Questa
3. ⏳ Observer waveforms - regarder les tags
4. ⏳ Vérifier que `data_we_tag` s'active
5. ⏳ Vérifier propagation: Tag(sum) = Tag(a) | Tag(b)
6. ⏳ Passer aux versions 2, 3, 4 pour tests plus complexes
