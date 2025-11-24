# ✅ DIFT Test Setup - Prêt pour Simulation

Tout est configuré pour tester la propagation des tags DIFT avec une variable pré-tainted!

## 📁 Fichiers Créés/Modifiés

### 1. Code de Test
**`/home/user/adam/software/hello_world/src/main.c`**
- Programme simple avec `tainted_input` (variable globale pré-tainted)
- Charge la valeur depuis mémoire → tag récupéré
- Fait une addition → tag propagé
- Store le résultat → tag écrit en mémoire

### 2. Tag Memory Initialization
**`/home/user/adam/bhv/tmem_pretaint.hex`**
- 2048 entrées (une par word de RAM)
- Index 0 (adresse 0x1000) = `F` (TAINTED)
- Tous les autres = `0` (TRUSTED)
- **Note:** Index 0 correspond typiquement à `tainted_input` si c'est la première variable globale

### 3. Testbench
**`/home/user/adam/bhv/cv32e40p_tb.sv`**
- Modifié pour utiliser `tmem_pretaint.hex` au lieu de `tmem.hex`
- Tag memory connectée en parallèle avec data memory

### 4. Documentation
**`/home/user/adam/software/hello_world/DIFT_PRACTICAL_SETUP.md`**
- Guide complet étape par étape
- Commandes pour compiler et trouver les adresses
- Explication du calcul d'index dans tag_mem

**`/home/user/adam/bhv/EXPECTED_WAVEFORMS_DIFT.md`**
- Description détaillée de ce qui doit apparaître dans les waveforms
- Timeline complète de la propagation
- Checklist de validation
- Guide de debugging

### 5. Script Automatique
**`/home/user/adam/software/build/generate_tmem_pretaint.sh`**
- Script bash pour générer automatiquement tmem_pretaint.hex
- Lit le fichier ELF pour trouver l'adresse de `tainted_input`
- Calcule l'index et génère le fichier

## 🚀 Prochaines Étapes

### Étape 1: Compiler le Programme

```bash
cd /home/user/adam/software/hello_world

# Compilation (nécessite RISC-V toolchain)
riscv32-unknown-elf-gcc \
    -march=rv32imc_zicsr \
    -mabi=ilp32 \
    -O2 -g -Wall \
    -mcmodel=medany \
    -static \
    -ffunction-sections \
    -fdata-sections \
    -T link.ld \
    -nostdlib \
    -o hello_world.elf \
    src/startup.s \
    src/main.c \
    -lc_nano -lgcc -lnosys

# Conversion en hex pour simulation
riscv32-unknown-elf-objcopy -O ihex hello_world.elf hello_world.hex

# Copier pour la simulation
cp hello_world.hex ../../mem0.hex
```

### Étape 2: Vérifier l'Adresse de tainted_input

```bash
riscv32-unknown-elf-nm hello_world.elf | grep tainted_input
```

**Attendu:** `00001000 D tainted_input`

Si l'adresse est **différente de 0x1000**, vous devez mettre à jour `tmem_pretaint.hex`:

```bash
cd /home/user/adam/software/build
./generate_tmem_pretaint.sh
```

### Étape 3: Lancer la Simulation

```bash
cd /home/user/adam/bhv

# Votre commande Questa, par exemple:
vsim -do run_cv32e40p_tb.do

# Ou si vous utilisez une autre commande
```

### Étape 4: Observer les Waveforms

#### Signaux Critiques à Ajouter à la Vue:

**Groupe Data Memory:**
```
data_req
data_we
data_addr
data_wdata
data_rdata
```

**Groupe Tag Memory (DIFT):**
```
data_wdata_tag    ← Devrait être 4'b1111 pour les stores tainted
data_rdata_tag    ← Devrait être 4'b1111 pour le premier load
data_we_tag
```

**Groupe Tag Memory Internal:**
```
tmem/tag_mem[0]   ← Devrait être F dès le début
tmem/tag_mem[1]   ← Devrait devenir F après store 'a'
tmem/tag_mem[3]   ← Devrait devenir F après store 'sum'
```

#### Que Chercher:

1. **Premier LOAD (tainted_input):**
   - `data_addr = 0x00001000`
   - `data_rdata = 0x00000064` (100 en décimal)
   - **`data_rdata_tag = 4'b1111`** ✅ TAG RÉCUPÉRÉ!

2. **Store 'a':**
   - `data_we = 1`
   - `data_wdata = 0x00000064`
   - **`data_wdata_tag = 4'b1111`** ✅ TAG PROPAGÉ!

3. **Store 'sum' (après addition):**
   - `data_wdata = 0x00000078` (120 = 100+20)
   - **`data_wdata_tag = 4'b1111`** ✅ TAG PROPAGÉ APRÈS ADD!

## ✅ Checklist de Validation

- [ ] Code compilé sans erreur
- [ ] `tainted_input` trouvée à 0x1000 (ou tmem_pretaint.hex mis à jour)
- [ ] mem0.hex copié dans /adam/
- [ ] Simulation lancée sans erreur
- [ ] Premier load récupère `data_rdata_tag = 4'b1111`
- [ ] Store de 'a' écrit `data_wdata_tag = 4'b1111`
- [ ] Store de 'sum' écrit `data_wdata_tag = 4'b1111`
- [ ] Tag propagé correctement: TAINTED + TRUSTED = TAINTED

## 📚 Documentation de Référence

Si vous avez des questions, consultez ces fichiers:

1. **`software/hello_world/DIFT_PRACTICAL_SETUP.md`**
   - Guide pratique complet
   - Comment trouver les adresses
   - Comment créer tmem_pretaint.hex

2. **`bhv/EXPECTED_WAVEFORMS_DIFT.md`**
   - Description détaillée des waveforms attendus
   - Timeline complète cycle par cycle
   - Guide de debugging

3. **`docs/DIFT_ARCHITECTURE_COMPLETE.md`**
   - Architecture DIFT complète
   - Comment les tags se propagent dans le pipeline
   - Explication théorique

4. **`software/hello_world/TAINT_INITIALIZATION_GUIDE.md`**
   - Différentes méthodes pour créer des variables tainted
   - Comparaison des approches

## 🔧 Debugging

### Si data_rdata_tag = 0000 (au lieu de 1111):

1. Vérifier que `tmem_pretaint.hex` existe dans `/adam/bhv/`
2. Vérifier la première ligne: doit être `F`
3. Vérifier que le testbench charge bien le fichier
4. Vérifier l'adresse de `tainted_input` avec `nm`

### Si data_wdata_tag = 0000 (au lieu de 1111):

1. Vérifier que les modifications DIFT sont bien dans le core
2. Vérifier que `data_wdata_tag` est connecté depuis le core
3. Vérifier que le tag_regfile se met bien à jour lors des loads

### Si le core ne boot pas:

1. Vérifier que mem0.hex existe et contient du code
2. Vérifier l'adresse de boot (0x00000000)
3. Vérifier startup.s et l'adresse de _start

## 🎯 Résumé

**Configuration actuelle:**
- ✅ main.c prêt avec `tainted_input` global
- ✅ tmem_pretaint.hex généré (index 0 = TAINTED)
- ✅ Testbench configuré pour utiliser tmem_pretaint.hex
- ✅ Documentation complète disponible
- ✅ Script automatique pour régénérer si besoin

**Ce qui reste à faire (de votre côté):**
1. Compiler avec votre toolchain RISC-V
2. Vérifier l'adresse de `tainted_input` (devrait être 0x1000)
3. Copier mem0.hex dans /adam/
4. Lancer la simulation Questa
5. Observer les signaux `data_rdata_tag` et `data_wdata_tag`

**Résultat attendu:**
Vous devriez voir le tag `4'b1111` (TAINTED) se propager de `tainted_input` → registre → addition → `sum`, démontrant que le système DIFT fonctionne correctement!

---

🎉 **Tout est prêt pour votre premier test DIFT!** 🎉
