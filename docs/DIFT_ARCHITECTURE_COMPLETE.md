# Architecture DIFT Complète - Comment les Tags Se Propagent

## Le Problème que tu Soulèves

```c
volatile int a = 10;  // Comment cela devient tainted?
```

**Code assembleur généré:**
```assembly
li   x15, 10       # x15 = 10 (load immediate)
sw   x15, 0(sp)    # RAM[sp] = x15
```

**Ta question clé:** Si `a` doit être tainted, comment le tag se propage-t-il?
- `li` charge une constante → tag(x15) = 0 (trusted par défaut)
- `sw` écrit x15 en RAM → tag_mem[RAM] = tag(x15) = 0

**Problème:** On ne peut pas marquer `a` comme tainted avec cette approche!

---

## Architecture DIFT Complète (Palmiero sur RI5CY)

### Structure: Deux Espaces de Tags

```
┌─────────────────────────────────────────────────────────┐
│                    CV32E40P Core                        │
│                                                         │
│  ┌─────────────────┐         ┌─────────────────┐      │
│  │ Data Registers  │         │  Tag Registers  │      │
│  │                 │         │                 │      │
│  │ x0  = 0         │   ←→    │ tag(x0)  = 0    │      │
│  │ x1  = ...       │   ←→    │ tag(x1)  = 0    │      │
│  │ x2  = ...       │   ←→    │ tag(x2)  = 0    │      │
│  │ ...             │   ←→    │ ...             │      │
│  │ x15 = 10        │   ←→    │ tag(x15) = ?    │      │
│  │ ...             │   ←→    │ ...             │      │
│  │ x31 = ...       │   ←→    │ tag(x31) = 0    │      │
│  └─────────────────┘         └─────────────────┘      │
│                                                         │
│  Pipeline: IF → ID → EX → MEM → WB                    │
│              │    │    │    │     │                    │
│              │    │    │    │     └─→ Update tags     │
│              │    │    │    └──────→ Load/Store tags  │
│              │    │    └─────────→ Propagate tags     │
│              │    └──────────────→ Read tags          │
│              └───────────────────→ (optional)          │
└─────────────────────────────────────────────────────────┘
                        ║
                        ║ data_wdata_tag
                        ║ data_rdata_tag
                        ▼
        ┌────────────────────────────┐
        │       TAG MEMORY           │
        │  (Hors du core)           │
        │                           │
        │  tag_mem[addr] = 4 bits   │
        └────────────────────────────┘
```

---

## Pipeline DIFT Stage par Stage

### IF Stage (Instruction Fetch)
```verilog
// Pas de tags pour les instructions (optionnel dans certaines implémentations)
// Focus sur les données
```

### ID Stage (Instruction Decode)
```verilog
// Lecture des tags des opérandes
logic tag_rs1, tag_rs2;

always_comb begin
    tag_rs1 = tag_regfile[rs1];  // Tag du registre source 1
    tag_rs2 = tag_regfile[rs2];  // Tag du registre source 2
end
```

### EX Stage (Execute) ⭐ **PROPAGATION ICI**
```verilog
// Propagation des tags selon l'opération
logic tag_result;

always_comb begin
    case (alu_op)
        ADD, SUB, MUL, DIV:
            tag_result = tag_rs1 | tag_rs2;  // OR logique

        AND, OR, XOR:
            tag_result = tag_rs1 | tag_rs2;

        SLT, SLTU:
            tag_result = tag_rs1 | tag_rs2;

        default:
            tag_result = 1'b0;
    endcase
end
```

### MEM Stage (Memory Access)
```verilog
// STORE: Écrire le tag en mémoire
if (mem_we) begin
    data_wdata     = regfile[rs2];
    data_wdata_tag = {4{tag_regfile[rs2]}};  // Répliquer le bit 4 fois
    data_we_tag    = 1'b1;
end

// LOAD: Lire le tag depuis la mémoire
if (mem_re) begin
    data_rdata     = ... (depuis RAM)
    data_rdata_tag = ... (depuis tag_mem)
    tag_load_result = |data_rdata_tag;  // OR de tous les bits
end
```

### WB Stage (Write Back)
```verilog
// Écrire le tag dans le tag register file
always_ff @(posedge clk) begin
    if (wb_valid) begin
        regfile[rd]     <= wb_data;
        tag_regfile[rd] <= wb_tag;  // Update tag!
    end
end

where:
    wb_tag = (is_load) ? tag_load_result : tag_result;
```

---

## Exemple Complet: Propagation d'un Tag

### Scénario: Load depuis source tainted

```c
volatile int tainted_source = 10;  // Pré-tainted en mémoire
volatile int a = tainted_source;    // Load
volatile int b = 20;                 // Constante
volatile int sum = a + b;            // Addition
```

### Assembleur généré:
```assembly
# tainted_source déjà en mémoire avec tag=1

lw   x15, [tainted_source]   # Load
li   x16, 20                  # Load immediate
add  x17, x15, x16            # Addition
sw   x17, [sum]               # Store
```

### Étape 1: Load depuis source tainted

```
Instruction: lw x15, [tainted_source]

Pipeline:
┌──────┬─────────────────────────────────────────┐
│ IF   │ Fetch lw instruction                    │
├──────┼─────────────────────────────────────────┤
│ ID   │ Decode: rd=x15, addr=tainted_source    │
├──────┼─────────────────────────────────────────┤
│ EX   │ Compute address                         │
├──────┼─────────────────────────────────────────┤
│ MEM  │ Read data_mem[addr] → 10               │
│      │ Read tag_mem[addr]  → 4'b1111 (tainted!)│
│      │ tag_load = 1                            │
├──────┼─────────────────────────────────────────┤
│ WB   │ regfile[x15] ← 10                      │
│      │ tag_regfile[x15] ← 1  ✅ TAG RÉCUPÉRÉ! │
└──────┴─────────────────────────────────────────┘

Résultat: x15 = 10, tag(x15) = 1
```

### Étape 2: Load immediate (constante)

```
Instruction: li x16, 20

Pipeline:
┌──────┬─────────────────────────────────────────┐
│ IF   │ Fetch li instruction                    │
├──────┼─────────────────────────────────────────┤
│ ID   │ Decode: rd=x16, imm=20                 │
├──────┼─────────────────────────────────────────┤
│ EX   │ x16 = 20                                │
│      │ tag = 0 (constante = trusted)          │
├──────┼─────────────────────────────────────────┤
│ MEM  │ -                                       │
├──────┼─────────────────────────────────────────┤
│ WB   │ regfile[x16] ← 20                      │
│      │ tag_regfile[x16] ← 0  ✅ TRUSTED       │
└──────┴─────────────────────────────────────────┘

Résultat: x16 = 20, tag(x16) = 0
```

### Étape 3: Addition (propagation)

```
Instruction: add x17, x15, x16

Pipeline:
┌──────┬─────────────────────────────────────────┐
│ IF   │ Fetch add instruction                   │
├──────┼─────────────────────────────────────────┤
│ ID   │ Read regfile[x15] = 10                 │
│      │ Read regfile[x16] = 20                 │
│      │ Read tag_regfile[x15] = 1              │
│      │ Read tag_regfile[x16] = 0              │
├──────┼─────────────────────────────────────────┤
│ EX   │ result = 10 + 20 = 30                  │
│      │ tag_result = 1 | 0 = 1  ✅ PROPAGATION!│
├──────┼─────────────────────────────────────────┤
│ MEM  │ -                                       │
├──────┼─────────────────────────────────────────┤
│ WB   │ regfile[x17] ← 30                      │
│      │ tag_regfile[x17] ← 1  ✅ TAINTED!      │
└──────┴─────────────────────────────────────────┘

Résultat: x17 = 30, tag(x17) = 1
```

### Étape 4: Store (écriture en mémoire)

```
Instruction: sw x17, [sum]

Pipeline:
┌──────┬─────────────────────────────────────────┐
│ IF   │ Fetch sw instruction                    │
├──────┼─────────────────────────────────────────┤
│ ID   │ Read regfile[x17] = 30                 │
│      │ Read tag_regfile[x17] = 1              │
├──────┼─────────────────────────────────────────┤
│ EX   │ Compute address                         │
├──────┼─────────────────────────────────────────┤
│ MEM  │ Write data_mem[sum] ← 30               │
│      │ Write tag_mem[sum] ← {4{1}} = 4'b1111 │
│      │                                         │
│      │ Signaux OBI:                           │
│      │   data_wdata = 30                      │
│      │   data_wdata_tag = 4'b1111 ✅          │
│      │   data_we_tag = 1                      │
├──────┼─────────────────────────────────────────┤
│ WB   │ -                                       │
└──────┴─────────────────────────────────────────┘

Résultat: RAM[sum] = 30, tag_mem[sum] = 4'b1111
```

---

## Réponse à Ta Question

> "Comment mon core voit les déclarations volatile int a = 10?"

**Réponse:**

1. **Compilation:**
   ```c
   volatile int a = 10;
   ```

   Devient:
   ```assembly
   li x15, 10      # Charge constante dans registre
   sw x15, [a]     # Store en mémoire
   ```

2. **Exécution dans le core:**

   **Load Immediate:**
   - `x15 ← 10`
   - `tag_regfile[x15] ← 0` (constante = trusted)

   **Store Word:**
   - `RAM[a] ← x15 = 10`
   - `tag_mem[a] ← tag_regfile[x15] = 0`

3. **Problème:** Le tag vient du **registre**, pas de la constante!

   **Solution:** Pour marquer `a` comme tainted:

   **Option A - Pré-charger depuis mémoire:**
   ```c
   volatile int source = 10;  // Déjà en RAM avec tag=1
   volatile int a = source;    // Load récupère le tag!
   ```

   **Option B - Forcer via CSR:**
   ```c
   write_csr(CSR_TPR, 1);  // Forcer prochain tag
   volatile int a = 10;     // tag(x15) forcé à 1
   ```

---

## Architecture du Tag Register File

### Dans le Core CV32E40P (modifié)

```verilog
// cv32e40p_register_file_tag_ff.sv

module cv32e40p_register_file_tag_ff (
    input  logic        clk,
    input  logic        rst_n,

    // Read ports
    input  logic [4:0]  raddr_a,
    output logic        rtag_a,    // Tag output

    input  logic [4:0]  raddr_b,
    output logic        rtag_b,    // Tag output

    // Write port
    input  logic [4:0]  waddr,
    input  logic        wtag,      // Tag input
    input  logic        we
);

    // Tag storage: 32 registers x 1 bit each
    logic [31:0] tag_mem;

    // Read tags
    assign rtag_a = (raddr_a == 5'b0) ? 1'b0 : tag_mem[raddr_a];
    assign rtag_b = (raddr_b == 5'b0) ? 1'b0 : tag_mem[raddr_b];

    // Write tag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_mem <= 32'h0;  // Tous trusted au reset
        end else if (we && waddr != 5'b0) begin
            tag_mem[waddr] <= wtag;
        end
    end

endmodule
```

---

## Solution Pratique pour Tes Tests

### Approche Recommandée: Load depuis Mémoire Pré-Tainted

**Code C:**
```c
// Déclarer une variable globale qui sera en .data
volatile int tainted_input = 100;

int main(void) {
    // Load depuis la variable globale (récupère tag!)
    volatile int a = tainted_input;

    // Constante normale
    volatile int b = 20;

    // Addition
    volatile int sum = a + b;

    while(1);
}
```

**Pré-initialisation:**

1. Trouver l'adresse de `tainted_input`:
   ```bash
   riscv32-unknown-elf-nm hello_world.elf | grep tainted_input
   # Output: 00001000 D tainted_input
   ```

2. Créer `tmem_pretaint.hex`:
   ```
   F    # Index 0 (addr 0x1000): tainted_input = TAINTED
   0    # Index 1
   0    # Index 2
   ...
   ```

3. **Résultat:**
   - `lw x15, [tainted_input]` → `tag(x15) = 1`
   - `add x17, x15, x16` → `tag(x17) = 1`
   - `sw x17, [sum]` → `tag_mem[sum] = 1`

---

## Vérification dans les Waveforms

**Signaux à observer:**

1. **Tag Register File (interne au core):**
   - `tag_regfile[x15]` après load → devrait être 1
   - `tag_regfile[x16]` après li → devrait être 0
   - `tag_regfile[x17]` après add → devrait être 1

2. **Signaux externes (OBI):**
   - `data_rdata_tag` lors du load → 4'b1111
   - `data_wdata_tag` lors du store → 4'b1111

---

## Résumé

**Ta question:** Comment le tag se propage de la mémoire → registre → mémoire?

**Réponse:**

1. **Tag Memory → Tag Register:**
   - `lw` instruction → lit `data_rdata_tag` → écrit `tag_regfile[rd]`

2. **Tag Register → Tag Register:**
   - Opérations ALU → `tag_result = tag(rs1) | tag(rs2)`

3. **Tag Register → Tag Memory:**
   - `sw` instruction → lit `tag_regfile[rs2]` → écrit `data_wdata_tag`

**Clé:** Les tags suivent les données à travers tout le pipeline!

