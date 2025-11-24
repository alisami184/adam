# Tag Memory pour DIFT - Documentation

## Vue d'Ensemble

La **tag memory** est une mémoire parallèle à la RAM qui stocke les tags DIFT (Dynamic Information Flow Tracking) pour chaque donnée. Elle fonctionne en parallèle avec la mémoire de données pour permettre la propagation et la vérification des tags de sécurité.

## Architecture

### Organisation Mémoire

```
Data Memory (RAM)              Tag Memory (TMEM)
┌──────────────────┐          ┌──────────────────┐
│ Byte 0: 0xXX     │ ◄──────► │ Tag 0: 4 bits    │
│ Byte 1: 0xXX     │ ◄──────► │ Tag 1: 4 bits    │
│ Byte 2: 0xXX     │ ◄──────► │ Tag 2: 4 bits    │
│ Byte 3: 0xXX     │ ◄──────► │ Tag 3: 4 bits    │
├──────────────────┤          ├──────────────────┤
│    (8KB RAM)     │          │   (2KB tags)     │
└──────────────────┘          └──────────────────┘
```

### Paramètres

| Paramètre | Valeur | Description |
|-----------|--------|-------------|
| `SIZE` | 8192 | Taille en bytes (même que RAM) |
| `TAG_WIDTH` | 4 | Largeur d'un tag en bits |
| `INIT_FILE` | "tmem.hex" | Fichier d'initialisation |

### Stockage Interne

- **Mémoire interne**: Mots de 32 bits
- **Organisation**: 8 tags de 4 bits par mot 32 bits
- **Format d'un mot**:
  ```
  [31:28] = Tag pour byte 3
  [27:24] = Tag pour byte 2
  [23:20] = Tag pour byte 1
  [19:16] = Tag pour byte 0
  [15:12] = Tag pour byte 3 (mot précédent)
  [11:8]  = Tag pour byte 2 (mot précédent)
  [7:4]   = Tag pour byte 1 (mot précédent)
  [3:0]   = Tag pour byte 0 (mot précédent)
  ```

## Interface OBI

### Signaux

```systemverilog
input  logic             req         // Requête d'accès
output logic             gnt         // Accord (1 cycle)
output logic             rvalid      // Donnée valide (1 cycle après gnt)
input  logic [31:0]      addr        // Adresse (même que data memory)
input  logic             we          // Write enable
input  logic [3:0]       be          // Byte enables
input  logic [3:0]       wdata_tag   // Tag à écrire (4 bits)
output logic [3:0]       rdata_tag   // Tag lu (4 bits)
```

### Protocole

```
     ┌───┬───┬───┬───┬───┐
clk  │   │   │   │   │   │
     └───┘   └───┘   └───┘
     ┌───────┐
req  ┘       └───────────
     ┌───────┐
gnt  ┘       └───────────
             ┌───────┐
rvalid       ┘       └───
     ════════════════════
addr ════ 0x1000 ════════
             ════════════
rdata_tag    ════ 0xA ═══
```

## Intégration Test Bench

### Connexions

```systemverilog
tag_mem #(
    .SIZE      (8192),
    .TAG_WIDTH (4),
    .INIT_FILE ("tmem.hex")
) tmem (
    .clk       (clk),
    .rst_n     (rst_n),
    .req       (data_req),          // Partagé avec data mem
    .addr      (dmem_addr),         // Même adresse que data mem
    .we        (data_we_tag),       // Depuis core
    .be        (data_be),           // Partagé avec data mem
    .wdata_tag (data_wdata_tag),    // Depuis core (4 bits)
    .rdata_tag (data_rdata_tag),    // Vers core (4 bits)
    .gnt       (data_gnt_tag),      // Vers core
    .rvalid    (data_rvalid_tag)    // Vers core
);
```

### Synchronisation avec Data Memory

La tag memory fonctionne **en parallèle** avec la data memory:
- Même requête (`data_req`)
- Même adresse (avec offset pour RAM base)
- Même byte enables
- Signaux de contrôle séparés (gnt, rvalid)

## Valeurs de Tags

### Convention DIFT

| Valeur | Signification | Usage |
|--------|---------------|-------|
| `0x0` | **Untainted** | Données sûres, non marquées |
| `0x1` | **Tainted L1** | Niveau de taint 1 (ex: entrée utilisateur) |
| `0x2` | **Tainted L2** | Niveau de taint 2 (ex: réseau) |
| `0x3` | **Tainted L3** | Niveau de taint 3 (ex: fichier) |
| `0x4-0xF` | **Réservé** | Niveaux supplémentaires ou drapeaux |

### Initialisation

Par défaut, tous les tags sont initialisés à `0x0` (untainted):
```systemverilog
initial begin
    for (int i = 0; i < ALIGNED_SIZE; i++) begin
        mem[i] = 32'h0;  // Tous les tags à 0
    end
end
```

## Fichier d'Initialisation (tmem.hex)

Format: Mots 32 bits en hexadécimal, un par ligne.

### Exemple - Tous untainted
```
00000000
00000000
00000000
...
```

### Exemple - Tags personnalisés
```
00001111   // Bytes 0-3: tags 1,1,1,1 (tainted L1)
22220000   // Bytes 4-7: tags 0,0,2,2 (mix)
FFFFFFFF   // Bytes 8-11: tous tags F
...
```

## Monitoring et Debug

### Affichage Console

Le test bench affiche automatiquement les accès tags:
```
[1234] TAG_WRITE: addr=0x00001000 tag=0x1 be=1111
[1235] TAG_READ: tag=0x0
```

### Signaux Waveform

Dans Questa, surveiller:
- `data_we_tag`: Écriture de tag active
- `data_wdata_tag[3:0]`: Tag à écrire
- `data_rdata_tag[3:0]`: Tag lu
- `data_gnt_tag`: Tag memory ready
- `data_rvalid_tag`: Tag data valid

## Comportement Attendu

### Scénario 1: Premier Store (Tag Initialization)

```
Cycle 1: data_req=1, data_we=1, addr=0x1000, data=0xDEADBEEF
         data_we_tag=?, data_wdata_tag=?
         → Le core devrait écrire le tag approprié
```

### Scénario 2: Load avec Tag

```
Cycle 1: data_req=1, data_we=0, addr=0x1000
Cycle 2: data_rvalid=1, data_rdata=0xDEADBEEF
         data_rvalid_tag=1, data_rdata_tag=0xX
         → Le core reçoit la donnée ET son tag
```

### Scénario 3: Propagation de Tag

```
Load  x = memory[0x1000]  → tag(x) = tag(memory[0x1000])
      y = x + 10          → tag(y) = tag(x)  (propagation)
Store memory[0x1004] = y  → tag(memory[0x1004]) = tag(y)
```

## Tests de Validation

### Test 1: Vérifier Initialisation
- Lire plusieurs adresses RAM
- Vérifier que tous les tags sont 0x0

### Test 2: Write puis Read
- Écrire donnée avec tag à 0x1000
- Relire la même adresse
- Vérifier que le tag est préservé

### Test 3: Multiple Bytes
- Écrire 4 bytes avec be=1111
- Vérifier que tous les bytes ont le même tag
- Lire chaque byte individuellement

### Test 4: Propagation Arithmétique
- Load avec tag non-zero
- Opération arithmétique
- Store résultat
- Vérifier propagation du tag

## Intégration DIFT Core

### Modifications Requises dans cv32e40p

Pour que le core utilise réellement la tag memory:

1. **IF Stage**: Tags pour instructions (optionnel)
2. **ID Stage**: Lecture tags des opérandes
3. **EX Stage**: Propagation des tags selon l'opération
4. **WB Stage**: Écriture tags des résultats

### Signaux DIFT dans le Core

```systemverilog
// Sorties du core
output logic       data_we_tag_o      // Active si écriture de tag
output logic [3:0] data_wdata_tag_o   // Tag à écrire en mémoire

// Entrées vers le core
input  logic [3:0] data_rdata_tag_i   // Tag lu depuis mémoire
input  logic       data_gnt_tag_i     // Tag memory ready
input  logic       data_rvalid_tag_i  // Tag data valid
```

## Dépannage

### Problème: Tags toujours 0x0

**Cause possible**: Core ne génère pas `data_we_tag`
**Solution**: Vérifier modifications DIFT dans le core

### Problème: Tags rouges (X) en simulation

**Cause**: Normal quand `data_rvalid_tag=0`
**Solution**: Vérifier tags uniquement quand rvalid=1

### Problème: Tags perdus après write/read

**Cause**: Adressage incorrect ou byte enables
**Solution**: Vérifier que `dmem_addr` est correct (avec offset)

## Prochaines Étapes

1. ✅ Tag memory créée et intégrée
2. ⏳ Vérifier que core génère signaux DIFT
3. ⏳ Tester propagation de tags
4. ⏳ Implémenter politiques de sécurité
5. ⏳ Validation complète DIFT

## Références

- **DIFT Original**: Palmiero sur RI5CY core
- **CV32E40P Docs**: https://docs.openhwgroup.org/projects/cv32e40p-user-manual/
- **Test Bench**: `cv32e40p_tb.sv`
- **Module**: `tag_mem.sv`
