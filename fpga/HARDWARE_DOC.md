# Hardware Documentation — RISC-V VPU SoC

**Project:** RISC-V Scalar Core + Vector Processing Unit (VPU) trên DE10-Standard  
**ISA:** `rv32im_zicsr_zve32x_zvl128b` | **VLEN:** 128 bit | **SEW:** 8/16/32 | **LMUL:** 1/2/4/8  
**Target:** Cyclone V 5CSXFC6D6F31C6 | **System Clock:** 50 MHz | **Pixel Clock:** 25 MHz

---

## 1. Kiến trúc tổng quan

```
                    ┌──────────────────────────────────────────────────────┐
                    │                riscv_vpu_top_fpga                    │
                    │                                                       │
  CLOCK_50 ────────►│ i_clk ──────────────────────────────────────────────►│
  KEY[0]  ─(~)─────►│ i_reset                                              │
                    │                                                       │
  UART_RX ─────────►│  ┌─────────────┐    TL-UL     ┌──────────────────┐  │
  UART_TX ◄─────────│  │  pipelined  │◄────────────►│   uart.sv        │  │
                    │  │    _vpu     │  (0xFF00_00xx)│  (RX/TX + FIFO) │  │
                    │  │ (scalar     │              └──────────────────┘  │
                    │  │  core)      │                                     │
                    │  │             │  s_dmem_*    ┌──────────────────┐  │
                    │  │             │◄────────────►│  dmem_qip_       │  │
                    │  └──────┬──────┘  Port A       │  wrapper         │  │
                    │         │ vpu_insn_vld          │  (4×M10K 64KB)  │  │
                    │         │ vpu_insn              │                  │  │
                    │         ▼                       │     Port B      │  │
                    │  ┌─────────────┐  vlsu_mem_*  │  ◄──────────────│  │
                    │  │  vproc_     │◄────────────►│                  │  │
                    │  │  system_    │               │     Port C      │  │
                    │  │  wrapper    │               │  (video, RO)   │  │
                    │  │  (VPU)      │               └──────────────────┘  │
                    │  └─────────────┘                       ▲             │
                    │                                         │ vid_rdata   │
                    │  ┌─────────────────────────────────┐   │             │
                    │  │        hdmi_ctrl                 │───┘             │
                    │  │  (VGA timing + ADV7513 I2C cfg) │                 │
                    │  └─────────────────────────────────┘                 │
                    │         │ hdmi_tx_d/clk/hs/vs/de/scl/sda             │
                    └─────────┼────────────────────────────────────────────┘
                              ▼
                          HDMI Monitor
```

### Memory map

| Địa chỉ | Kích thước | Mô tả |
|---|---|---|
| `0x0000_0000 – 0x0000_1FFF` | 8 KB | IMEM (instruction ROM, sync M10K) |
| `0x0000_0000 – 0x0000_FFFF` | 64 KB | DMEM (data, dual-port M10K) |
| `0xFF00_0000 – 0xFF00_00FF` | 256 B | UART MMIO (TL-UL mapped) |

> IMEM và DMEM share địa chỉ thấp nhưng là bộ nhớ vật lý riêng biệt (Harvard architecture). IMEM chỉ đọc được từ instruction fetch; DMEM chỉ truy cập được từ load/store.

---

## 2. VPU — Vector Processing Unit

### 2.1 Kiến trúc tổng thể VPU

```
  scalar core
  ──────────────────────────────────────────────────────────────
  vpu_insn_vld ──►┌──────────────┐
  vpu_insn     ──►│ vproc_       │  ctrl_bus[47:0]  ┌────────┐
  rs1_data     ──►│ vdecoder     │─────────────────►│        │
  rs2_data     ──►│              │  imm_out[31:0]   │ vproc_ │  ctrl_bus   ┌──────────┐
                  └──────────────┘─────────────────►│ fifo   │────────────►│          │
                                                     │        │  rs1_data  │ vproc_   │
                                                     └────────┘────────────►│ fsm      │
                                                          ▲                  │          │
                                                    pop_ready                └────┬─────┘
                                                                                  │ control signals
                                                    ┌─────────────────────────────┼──────────────┐
                                                    │                             │              │
                                              ┌─────▼───────┐           ┌────────▼──────┐       │
                                              │ vproc_vcsr  │           │ vproc_vrf_    │       │
                                              │ (vl,vtype,  │           │ addr_gen      │       │
                                              │  vlenb)     │           │               │       │
                                              └─────────────┘           └───────────────┘       │
                                                                                 │ vs1/vs2/vd    │
                                                    ┌────────────────────────────▼──────────┐    │
                                                    │           vproc_vregfile              │    │
                                                    │   32 × 128-bit = 4 lanes × 32-bit     │    │
                                                    │   Lane 0: bits [31:0]                 │    │
                                                    │   Lane 1: bits [63:32]                │    │
                                                    │   Lane 2: bits [95:64]                │    │
                                                    │   Lane 3: bits [127:96]               │    │
                                                    └──────────┬────────────────────────────┘    │
                                                               │ vs1[31:0], vs2[31:0] per lane    │
                                                    ┌──────────▼────────────────────────────┐    │
                                                    │      vproc_processor_lane × 4          │◄───┘
                                                    │  (adder/mul/shift/logic/compare/       │
                                                    │   minmax/reduction per element)        │
                                                    └──────────────────────────────────────–-┘
                                                               │ wb_result per lane
                                                    ┌──────────▼──────────────┐
                                                    │  vproc_vec_lsu (VLSU)   │──► Port B DMEM
                                                    └─────────────────────────┘
```

### 2.2 Decoder — `vproc_vdecoder.sv`

Decoder nhận instruction 32-bit từ scalar core và giải mã thành **ctrl_bus 48-bit** đưa vào FIFO.

#### Layout ctrl_bus[47:0]

| Bits | Field | Mô tả |
|---|---|---|
| `[4:0]` | `vs1_addr` | Địa chỉ source register 1 |
| `[9:5]` | `vs2_addr` | Địa chỉ source register 2 |
| `[14:10]` | `vd_addr` | Địa chỉ destination register |
| `[20:15]` | `funct6` | Opcode cụ thể của lệnh vector |
| `[21]` | `is_widen` | Lệnh widening (kết quả gấp đôi SEW) |
| `[22]` | `is_unsigned_vs1` | vs1 xử lý không dấu |
| `[23]` | `is_unsigned_vs2` | vs2 xử lý không dấu |
| `[24]` | `is_subtraction` | Phép trừ (đảo cộng) |
| `[25]` | `is_immediate` | Dùng immediate thay vs1 |
| `[26]` | `is_rs1` | Dùng scalar rs1 |
| `[27]` | `is_mulh` | Lấy phần cao của nhân |
| `[28]` | `is_config` | Lệnh vsetvl/vsetvli |
| `[29]` | `is_vector` | Thuộc opcode OP-V (0x57) |
| `[30]` | `cfg_is_vsetvli` | 1=vsetvli (vtype từ imm), 0=vsetvl (vtype từ rs2) |
| `[31]` | `vm` | Bit mask từ instruction[25] |
| `[39:32]` | `vtype_enc[7:0]` | `{vma, vta, vsew[2:0], vlmul[2:0]}` |
| `[40]` | `is_carry` | vadc / vsbc |
| `[41]` | `is_mask_carry` | vmadc / vmsbc |
| `[42]` | `is_masking` | Lệnh tạo mask (vmseq, vmsltu...) |
| `[43]` | `is_final_masking` | Cần thêm pha ST_FINAL_MASKING |
| `[44]` | `is_reverse_sub` | vrsub (đảo minuend/subtrahend) |
| `[45]` | `minmax_is_min` | 1=min, 0=max |
| `[46]` | `minmax_is_unsign` | 1=unsigned compare |
| `[47]` | `is_reduction` | vred* instruction |

#### Phân loại lệnh config (funct3 = 3'b111)

```
instruction[31:30]
  00 / 01  →  vsetvli  : vtype từ zimm[10:0] (inst[30:20]), AVL từ rs1
  11       →  vsetivli : vtype từ zimm[9:0]  (inst[29:20]), AVL = uimm5 (inst[19:15])
  10       →  vsetvl   : vtype từ rs2_data,                  AVL từ rs1
```

**Timing decoder:** Combinational — latency 0 cycle. Output `ctrl_bus` ổn định trong cùng cycle với `vpu_insn`.

---

### 2.3 FIFO — `vproc_fifo.sv`

FIFO nằm giữa decoder và FSM, decoupling issue từ scalar core với execution của VPU.

```
  Decoder ──ctrl_bus──► [entry0][entry1]...[entry7] ──► FSM
              rs1_data──► [entry0][entry1]...[entry7] ──►
              imm_out ──► [entry0][entry1]...[entry7] ──►
                                   ▲             │
                            push (scalar)    pop_ready (FSM)
```

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `push` | in | Scalar push lệnh mới (khi `vpu_insn_vld & !fifo_full`) |
| `pop_ready` | in | FSM kéo dữ liệu ra (khi chuyển sang trạng thái exec) |
| `data_valid` | out | FIFO có ít nhất 1 entry hợp lệ |
| `fifo_full` | out | FIFO đầy (8 entries) — stall scalar core |

**Timing:** Registered outputs. Dữ liệu xuất hiện ở đầu ra 1 cycle sau khi `push`.

---

### 2.4 FSM — `vproc_fsm.sv`

FSM điều phối toàn bộ execution pipeline của VPU.

#### Sơ đồ trạng thái

```
                         ┌─────────────────────────────────────────────┐
                         │                                             │
                         ▼        instr_valid=1                        │
              ┌────────────────┐ ──────────────┬──────────────────────►│
              │   ST_IDLE (0)  │               │ is_config             │
              └────────────────┘               ▼                       │
                    ▲    ▲    ▲    ┌──────────────────┐                │
                    │    │    │    │  ST_CONFIG (1)   │─(1 cycle)──────┘
                    │    │    │    └──────────────────┘
                    │    │    │               │ is_masking             
                    │    │    │               ▼                        
                    │    │    │    ┌──────────────────┐   counter_done
                    │    │    │    │  ST_MASKING (5)  │──────────────►┌──────────────────────┐
                    │    │    │    └──────────────────┘               │ ST_FINAL_MASKING (6) │──►│
                    │    │    │               │ is_widen              └──────────────────────┘
                    │    │    │               ▼
                    │    │    │    ┌──────────────────┐
                    │    │    │    │  ST_WIDENL (3)   │─(1 cycle)──►┌──────────────────┐
                    │    │    │    └──────────────────┘             │  ST_WIDENH (4)   │
                    │    │    │                                      └────────┬─────────┘
                    │    │    │                                         counter_done?
                    │    │    │                                          NO ──► ST_WIDENL
                    │    │    │                                         YES ──►│
                    │    │    │               │ is_reduction
                    │    │    │               ▼
                    │    │    │    ┌──────────────────┐   reduction_done
                    │    │    │    │ ST_REDUCTION (7) │─────────────►┌─────────────────────┐
                    │    │    │    └──────────────────┘              │ ST_REDUCTION_DONE(8)│──►│
                    │    │    │               │ else                 └─────────────────────┘
                    │    │    │               ▼
                    │    │    └──── ┌──────────────────┐   counter_done
                    │    └──────── │   ST_EXEC (2)    │──────────────────────────────────────►│
                    └─────────────  └──────────────────┘
```

#### Output signals của FSM theo từng state

| State | `latch_ctrl_en` | `csr_cfg_en` | `vrf_wren` | `s_offset_en` | `d_offset_en` | `pop_ready` |
|---|---|---|---|---|---|---|
| IDLE (có insn) | ✓ | - | - | - | - | ✓ |
| CONFIG | - | ✓ | - | - | - | - |
| EXEC | - | - | ✓ | ✓ | ✓ | - |
| WIDENL | - | - | ✓ | - | ✓ | - |
| WIDENH | - | - | ✓ | ✓ | ✓ | - |
| MASKING | - | - | - | ✓ | - | - |
| FINAL_MASKING | - | - | ✓ | - | - | - |
| REDUCTION | - | - | - | ✓ | - | - |
| REDUCTION_DONE | - | - | ✓ | - | - | - |

**Timing FSM:**
- `latch_ctrl_en` pulse trong cùng cycle với `instr_valid` (tại IDLE) → ctrl_bus, rs1, imm được chốt vào register
- Mỗi state chuyển tiếp tại cạnh lên của `clk`
- `counter_start` pulse 1 cycle (tại IDLE khi non-config) → counter bắt đầu đếm số cycle theo `vl`

---

### 2.5 Vector Register File — `vproc_vregfile.sv`

```
  32 registers × 128-bit
  ┌──────────────────────────────────────────────────────────┐
  │  v0  [127:0]  ─── 4 × 32-bit lanes                      │
  │  v1  [127:0]                                             │
  │  ...                                                     │
  │  v31 [127:0]                                             │
  └──────────────────────────────────────────────────────────┘
           │ Lane 0 [31:0]   │ Lane 1 [63:32]  │ Lane 2 [95:64] │ Lane 3 [127:96]
           ▼                 ▼                  ▼                 ▼
      vproc_lane0      vproc_lane1        vproc_lane2        vproc_lane3
```

**SEW và phân bổ element trong lane với VLEN=128:**

| SEW | Elements/register | Elements/lane | Bit width/element/lane |
|---|---|---|---|
| 8-bit | 16 | 4 | 8 bit × 4 = 32 bit |
| 16-bit | 8 | 2 | 16 bit × 2 = 32 bit |
| 32-bit | 4 | 1 | 32 bit × 1 = 32 bit |

Mỗi lane luôn xử lý dữ liệu 32-bit, số phần tử bên trong lane thay đổi theo SEW.

**Tín hiệu VRF chính:**

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `vs1_addr`, `vs2_addr` | in | Địa chỉ đọc (5-bit) |
| `vd_addr` | in | Địa chỉ ghi (5-bit) |
| `vs1_data[31:0]` | out | Dữ liệu đọc lane (per lane) |
| `vs2_data[31:0]` | out | Dữ liệu đọc lane (per lane) |
| `vd_wdata[31:0]` | in | Dữ liệu ghi lane (per lane) |
| `vrf_wren` | in | Write enable từ FSM |
| `s_offset`, `d_offset` | in | Offset trong instruction loop |

---

### 2.6 Execution Lane — `vproc_processor_lane.sv`

Mỗi lane là một datapath 32-bit xử lý song song, chứa tất cả các functional unit:

```
  vs1_data[31:0] ─────┬──────────────────────────────────────────────────────►┐
  vs2_data[31:0] ─────┼──►┌──────────────┐                                    │
                       │   │ vproc_adder  │ VADD/VSUB/VRSUB/VADC/VSBC         │
                       │   └──────────────┘                                    │
                       │   ┌──────────────┐                                    │
                       │   │ vproc_mul    │ VMUL/VMULH/VMULHU/VMULHSU         │
                       │   └──────────────┘                                    │
                       │   ┌──────────────┐                                    ▼
                       │   │ vproc_shifter│ VSLL/VSRL/VSRA               ┌──────────┐
  ctrl_bus ────────────┼──►│              │                               │ result   │
  (funct6, flags)      │   └──────────────┘                               │  mux     │──► wb_data[31:0]
                       │   ┌──────────────┐                               │          │
                       │   │ vproc_logic  │ VAND/VOR/VXOR                 └──────────┘
                       │   └──────────────┘                                    ▲
                       │   ┌──────────────┐                                    │
                       │   │ vproc_compare│ VMSEQ/VMSNE/VMSLT/VMSLTU/...      │
                       │   └──────────────┘                                    │
                       │   ┌──────────────┐                                    │
                       │   │ vproc_minmax │ VMIN/VMINU/VMAX/VMAXU              │
                       │   └──────────────┘                                    │
                       └──►┌──────────────┐                                    │
                            │ vproc_       │ VREDSUM/VREDMAX/VREDMIN/...        │
                            │ reduction    │────────────────────────────────────┘
                            └──────────────┘
```

**Timing thực thi (SEW=8, LMUL=1, VL=16):**

```
Cycle 0:  FSM = IDLE,  latch_ctrl_en=1 → ctrl_r ← ctrl_bus, counter_start=1
Cycle 1:  FSM = EXEC,  vrf_wren=1, s_offset_en=1, d_offset_en=1
          Lane 0: vs1[7:0]×4, vs2[7:0]×4 → ALU → wb[7:0]×4
          Lane 1: vs1[15:8]×4, vs2[15:8]×4 → ALU → wb[15:8]×4
          ...
Cycle 1:  counter_done=1 (VL=16 elements = 1 register group = 1 cycle)
          FSM → IDLE
```

Với LMUL=2, VL=32: cần 2 cycles (offset tăng +1 mỗi cycle để đọc v[d], v[d+1]).

---

### 2.7 Vector LSU — `vproc_vec_lsu.sv`

VLSU xử lý `VLE8/16/32` (load) và `VSE8/16/32` (store) đơn vị-stride.

#### Load (VLE8.v vd, (rs1))

```
  Cycle 0:  vls_valid=1, vls_is_load=1
            mem_req=1, mem_we=0, mem_addr = rs1_data
  Cycle 1:  mem_rdata valid (1-cycle SRAM latency)
            Dữ liệu 32-bit accumulate vào line_buffer[31:0]
  Cycle 2:  mem_addr = rs1_data + 4
            line_buffer[63:32] ← mem_rdata
  Cycle 3:  mem_addr = rs1_data + 8
            line_buffer[95:64] ← mem_rdata
  Cycle 4:  mem_addr = rs1_data + 12
            line_buffer[127:96] ← mem_rdata
            vrf_we=1 → ghi line_buffer[127:0] vào 4 lanes của VRF[vd]
  ...       Lặp lại cho các register tiếp theo nếu LMUL > 1
```

**SEW mapping cho số word cần đọc:**

| SEW | Elements/word | num_words = ceil(vl / n) |
|---|---|---|
| e8 | 4 | `ceil(vl / 4)` |
| e16 | 2 | `ceil(vl / 2)` |
| e32 | 1 | `vl` |

#### Tín hiệu VLSU → DMEM Port B

| Tín hiệu | Width | Mô tả |
|---|---|---|
| `mem_req` | 1 | Request hợp lệ trong cycle này |
| `mem_we` | 1 | 1=store, 0=load |
| `mem_addr` | 32 | Byte address (word-aligned) |
| `mem_be` | 4 | Byte enables (cho masked/partial store) |
| `mem_wdata` | 32 | Dữ liệu ghi (store) |
| `mem_rdata` | 32 | Dữ liệu đọc (load), valid 1 cycle sau req |
| `mem_ready` | 1 | DMEM xác nhận (luôn =1 vì sync SRAM) |

---

## 3. UART — `uart.sv`

### 3.1 Kiến trúc UART

```
  uart_rx (serial in)
       │
       ▼
  ┌──────────────────────────────────────────────────────────────────┐
  │                     uart.sv                                       │
  │                                                                   │
  │  ┌─────────────────┐     ┌──────────────────────┐               │
  │  │  RX Engine      │────►│  RX FIFO (8 × 8-bit) │               │
  │  │  8N1, 16× OS    │     │  (* ramstyle="logic")│               │
  │  └─────────────────┘     └──────────────┬───────┘               │
  │                                          │ rx_rptr (dequeue)      │
  │  TL-UL register interface ◄─────────────┘                        │
  │  ┌────────────────────────────────────────────────────────┐      │
  │  │ offset│ name │ access │ bit definition                 │      │
  │  │ 0x00  │ CTRL │  RW    │ [0]=TX_EN, [1]=RX_EN          │      │
  │  │ 0x04  │ STAT │  RO    │ [0]=TX_BUSY, [1]=RX_VALID     │      │
  │  │ 0x08  │ TXDAT│  WO    │ [7:0]=byte → push TX FIFO     │      │
  │  │ 0x0C  │ RXDAT│  RO    │ [7:0]=byte ← pop RX FIFO      │      │
  │  │ 0x10  │ BAUD │  RW    │ [15:0]=divisor                │      │
  │  └────────────────────────────────────────────────────────┘      │
  │                                          │                        │
  │  ┌─────────────────┐     ┌──────────────┴───────┐               │
  │  │  TX Engine      │◄────│  TX FIFO (8 × 8-bit) │               │
  │  │  8N1            │     │  (* ramstyle="logic")│               │
  │  └─────────────────┘     └──────────────────────┘               │
  └──────────────────────────────────────────────────────────────────┘
       │
       ▼
  uart_tx (serial out)
```

### 3.2 Baud Rate

```
baud_div = CLK_FREQ / (16 × BAUD_RATE) - 1
         = 50_000_000 / (16 × 115200) - 1
         = 27 - 1 = 26   (default)

Mỗi bit = (baud_div + 1) × (1/CLK_FREQ) = 27 × 20 ns = 540 ns ≈ 115200 baud
```

Trong simulation: `force dut.u_uart.baud_div = 16'd3` → 4 cycles/bit (~2.3M sys-clk cycles tổng)

### 3.3 RX Engine — 16× oversampling

```
  uart_rx ──► [2FF sync] ──► rx_sync1

  Phát hiện start bit: !rx_active && ctrl_rx_en && !rx_sync1
    → rx_active = 1
    → rx_baud_cnt = baud_div/2  (canh giữa bit đầu)

  Sampling mỗi baud_div+1 cycles:
    rx_shift ← {rx_sync1, rx_shift[7:1]}  (LSB first)
    rx_bit_cnt--

  Khi rx_bit_cnt == 0 (stop bit):
    if rx_sync1 (stop valid) && !rx_full:
      rx_fifo[rx_wptr] ← rx_shift
      rx_wptr++
    rx_active = 0
```

### 3.4 TX Engine

```
  Khi !tx_busy && !tx_empty && ctrl_tx_en:
    tx_shift = {1'b1, tx_fifo[tx_rptr], 1'b0}  → {stop, data[7:0], start}
    tx_rptr++
    tx_bit_cnt = 10

  Mỗi baud_div+1 cycles:
    uart_tx ← tx_shift[0]
    tx_shift ← {1'b1, tx_shift[9:1]}  (LSB first)
    tx_bit_cnt--
```

**Timing UART frame (115200 baud, 50 MHz clock):**

```
  │ start │ b0 │ b1 │ b2 │ b3 │ b4 │ b5 │ b6 │ b7 │ stop │
  │  27cy │27cy│27cy│27cy│27cy│27cy│27cy│27cy│27cy│  27cy│
  ←────────────────────── 270 cycles ≈ 5.4 µs ──────────────►
```

### 3.5 TL-UL Interface → UART

Scalar core truy cập UART qua địa chỉ `0xFF00_00xx`. Top module decode `uart_sel = (addr[31:8] == 24'hFF0000)` và tạo TL-UL transaction:

```
  Write (SW instruction):
    tl_a.valid  = 1
    tl_a.opcode = TL_A_PUT_PARTIAL (3'd1)
    tl_a.address = s_dmem_addr
    tl_a.mask    = s_dmem_be
    tl_a.data    = s_dmem_wdata

  Read (LW instruction):
    tl_a.valid  = 1
    tl_a.opcode = TL_A_GET (3'd4)
    tl_a.address = s_dmem_addr
    → tl_d.data  = register_output (combinational, 0 latency)
    → uart_rdata_r ← tl_d.data (registered 1 cycle sau)
      để align với 1-cycle DMEM read latency
```

---

## 4. Memory Subsystem

### 4.1 IMEM — `imem_sync.sv`

```
  ┌──────────────────────────────────────────────────────┐
  │               imem_sync                              │
  │                                                      │
  │  (* ram_init_file = "uart_lena.mif" *)               │
  │  logic [31:0] mem [0:2047]  ← M10K ROM infer        │
  │                                                      │
  │  always_ff @(posedge clk):                           │
  │    if (reset || flush)  instr ← NOP (0x00000013)    │
  │    else if (!stall)     instr ← mem[pc[12:2]]       │
  └──────────────────────────────────────────────────────┘
```

| Tín hiệu | Mô tả |
|---|---|
| `pc[31:0]` | Program counter từ scalar core |
| `flush` | Branch/jump taken → inject NOP |
| `stall` | Pipeline stall (load-use hoặc VPU stall) |
| `instr[31:0]` | Instruction output (1-cycle latency) |
| `reset` | Active-high, sync reset → output NOP |

**Synthesis:** `ram_init_file = "uart_lena.mif"` → Quartus init M10K từ MIF file.  
**Simulation:** `$readmemh("uart_lena.hex", mem)` (bên trong `translate_off/on`).

**Firmware loaded: `uart_lena.S`** — Receive R/G/B UART → VPU grayscale → ACK 0xAA.

### 4.2 DMEM — `dmem_qip_wrapper.sv`

```
  ┌─────────────────────────────────────────────────────────────────┐
  │               dmem_qip_wrapper                                  │
  │                                                                 │
  │   4 × dmem_bank (True Dual-Port M10K, 8-bit × 16384 words)    │
  │                                                                 │
  │   Port A (scalar):                                              │
  │     a_word = s_re ? s_addr[15:2] : vid_addr   ← mux           │
  │     a_rden = s_re | vid_re                                      │
  │     a_wren[3:0] = {4{s_we}} & s_be            ← per-bank      │
  │     → q_a → s_rdata / vid_rdata (same wire)                   │
  │                                                                 │
  │   Port B (VLSU):                                                │
  │     b_word = vlsu_addr[15:2]                                    │
  │     b_rden = vlsu_req & ~vlsu_we                                │
  │     b_wren[3:0] = {4{vlsu_req & vlsu_we}} & vlsu_be            │
  │     → q_b → vlsu_rdata                                         │
  └─────────────────────────────────────────────────────────────────┘
```

#### DMEM byte layout (64 KB)

```
  Byte addr   Word addr    Nội dung
  0x0000      0            ┐
  ...         ...          │ R channel: 16384 bytes (firmware nhận qua UART)
  0x3FFF      4095         ┘
  0x4000      4096         ┐
  ...         ...          │ G channel: 16384 bytes
  0x7FFF      8191         ┘
  0x8000      8192         ┐
  ...         ...          │ B channel: 16384 bytes
  0xBFFF      12287        ┘
  0xC000      12288        ┐
  ...         ...          │ Y output: 16384 bytes (VPU ghi, HDMI đọc)
  0xFFFF      16383        ┘
```

#### Tại sao dùng 4 × 8-bit thay vì 1 × 32-bit + byteena?

Cyclone V M10K ở chế độ True Dual-Port với byteena chỉ support depth = 512 words (chiếm 1/8 capacity). Dùng 4 bank 8-bit riêng biệt → giữ full depth 16384 words, tổng 16 M10K thay vì 128 M10K.

#### Port A mux — scalar vs video

```
  Port A address mux:
    s_re=1 → a_word = s_addr[15:2]   (scalar có priority)
    s_re=0 → a_word = vid_addr       (HDMI video đọc khi scalar rảnh)

  Mutual exclusion:
    Sau khi firmware gửi ACK, scalar ở spin loop "j done" (JAL, không read DMEM)
    → s_re = 0 mãi → HDMI luôn thắng Port A trong suốt phase hiển thị
```

#### vlsu_ready handshake

```
  Write: vlsu_ready = vlsu_req            (ack ngay trong cycle hiện tại)
  Read:  vlsu_ready = vlsu_rd_pending_r   (ack sau 1 cycle do M10K registered output)
```

---

## 5. HDMI Controller — `hdmi_ctrl.sv`

### 5.1 VGA Timing (640×480 @ 60 Hz)

```
  Horizontal (800 pixels total per line):
  ├─────── 640 active ────────┤─ 16 FP ─┤── 96 sync ──┤─ 48 BP ─┤
  hc: 0─────────────────────639  640──655  656────────751  752───799

  Vertical (525 lines total per frame):
  ├─────── 480 active ────────┤─ 10 FP ─┤── 2 sync ──┤─ 33 BP ─┤
  vc: 0─────────────────────479  480──489  490─────────491  492──524

  Pixel clock: 25 MHz → 40 ns/pixel
  Line rate:   800 × 40 ns = 32 µs/line
  Frame rate:  525 × 32 µs ≈ 16.8 ms → 59.5 Hz ≈ 60 Hz
```

### 5.2 Image mapping trong frame

```
  Frame 640×480:
  ┌──────────────────────────────────────────────────────┐
  │  black (background)                                  │  vc = 0..47
  │  ┌──────────────────────────────────────────────┐   │
  │  │                                              │   │  vc = 48..431
  │  │   Lena grayscale 128×128 @ 3× zoom           │   │
  │  │   (384×384 pixels)                           │   │
  │  │                                              │   │
  │  └──────────────────────────────────────────────┘   │
  │  hc offsets: 128..511                                │
  │  black (background)                                  │  vc = 432..479
  └──────────────────────────────────────────────────────┘
```

### 5.3 Read pipeline (1-cycle DMEM latency)

```
  pclk N:
    hc_next = hc + 1
    in_img_next = (hc_next ∈ [128..511]) && (vc_next ∈ [48..431])
    row_next = (vc_next - 48) / 3      → [0..127]
    col_next = (hc_next - 128) / 3     → [0..127]
    next_word_addr = 12288 + row_next×32 + col_next/4
    next_byte_lane = col_next % 4
    vid_addr_o ← next_word_addr   (issued 1 cycle early)
    vid_re_o   ← in_img_next

  pclk N+1:
    vid_rdata_i = DMEM[next_word_addr]  (valid, 1-cycle latency)
    de_r        ← de (delayed)
    byte_lane_r ← next_byte_lane
    in_img_r    ← in_img_next

    y_pixel = vid_rdata_i[byte_lane_r × 8 +: 8]
    out_px  = in_img_r ? y_pixel : 8'h00
    hdmi_d_o = de_r ? {out_px, out_px, out_px} : 24'h000000
```

### 5.4 ADV7513 I2C configuration

Sau reset, `adv7513_cfg` gửi **14 register writes** qua I2C để khởi động chip ADV7513:

| Register | Giá trị | Mục đích |
|---|---|---|
| 0x41 | 0x10 | Power on |
| 0x15 | 0x00 | RGB 444 input, 8-bit |
| 0x16 | 0x38 | 8 bpc, style 1 |
| 0xAF | 0x06 | HDMI mode (không phải DVI) |
| 0xD6 | 0xC0 | HPD override (bỏ qua hotplug detect) |
| 0x17 | 0x02 | Aspect ratio 16:9 |
| 0x98–0xF9 | (ADI required) | Internal ADV7513 calibration |

---

## 6. Luồng dữ liệu tổng thể — Lena Demo

### 6.1 Phase 1: Nhận ảnh qua UART → DMEM

```
  Host PC                    DE10-Standard FPGA
  ─────────────────────────────────────────────────────────────────
  [Python send_lena.py]       [uart_lena firmware running on RISC-V]

  Gửi R[0..16383]    →──────→  uart_rx
  (16384 bytes)                   │
                                  ▼ RX engine sample + push RX FIFO
                              [firmware recv_block]:
                                  lw  t1, 4(s0)   # poll STAT.RX_VALID
                                  lw  t1, 12(s0)  # RXDAT → dequeue
                                  sb  t1, 0(a0)   # store to DMEM[0x0000+]
                                  ... (16384 lần)

  Gửi G[0..16383]    →──────→  (tương tự, store tại 0x4000)
  Gửi B[0..16383]    →──────→  (tương tự, store tại 0x8000)
```

### 6.2 Phase 2: VPU xử lý BT.601 grayscale

```
  Firmware: vsetvli t1, t1, e8, m1, ta, ma   # vl=16, SEW=8
            li t0, 1024                        # 1024 vòng lặp × 16 = 16384 elements

  vpu_loop (mỗi iteration):
    vle8.v  v1, (a0)   → VLSU: load 16 bytes R từ DMEM[a0..a0+15]
    vle8.v  v2, (a1)   → VLSU: load 16 bytes G từ DMEM[a1..a1+15]
    vle8.v  v3, (a2)   → VLSU: load 16 bytes B từ DMEM[a2..a2+15]

    vmulhu.vx v4, v1, t3   # v4[i] = (R[i] × 77) >> 8    (upper byte)
    vmulhu.vx v5, v2, t4   # v5[i] = (G[i] × 150) >> 8
    vmulhu.vx v6, v3, t5   # v6[i] = (B[i] × 29) >> 8

    vadd.vv v7, v4, v5     # v7[i] = yr + yg
    vadd.vv v7, v7, v6     # v7[i] = yr + yg + yb = Y[i]

    vse8.v  v7, (a3)   → VLSU: store 16 bytes Y vào DMEM[a3..a3+15]

    a0+=16, a1+=16, a2+=16, a3+=16
    t0--
    bnez t0, vpu_loop

  Kết quả: DMEM[0xC000..0xFFFF] = Y grayscale (16384 bytes)
```

**BT.601 công thức:**
```
Y = (R × 77 + G × 150 + B × 29) >> 8
  ≈ 0.299R + 0.587G + 0.114B
Max: (255×77 + 255×150 + 255×29) >> 8 = 255×256/256 = 255 (không overflow 8-bit)
```

### 6.3 Phase 3: Gửi ACK + HDMI hiển thị

```
  Firmware:
    li   a0, 0xAA
    call uart_tx_byte         # gửi ACK → Host PC nhận [PASS]
    j    done                 # spin loop (s_re = 0 mãi)

  HDMI controller (pclk domain, song song):
    Mỗi frame 60 Hz:
      Đọc DMEM[0xC000..0xFFFF] qua Port A (video)
      Scale 3× → 384×384 pixels
      Output RGB888 = {Y, Y, Y} cho mỗi pixel
```

---

## 7. Tóm tắt tín hiệu giao tiếp giữa các module

### 7.1 Scalar Core ↔ VPU

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `vpu_insn_vld` | Core → VPU | Có lệnh vector hợp lệ tại EX stage |
| `vpu_insn[31:0]` | Core → VPU | Instruction 32-bit |
| `vpu_rs1_data[31:0]` | Core → VPU | Giá trị rs1 (AVL cho vsetvl, base addr cho vlse) |
| `vpu_rs2_data[31:0]` | Core → VPU | Giá trị rs2 (vtype cho vsetvl) |
| `vpu_ready` | VPU → Core | VPU sẵn sàng nhận lệnh mới (= ~fifo_full & ~vlsu_busy) |
| `vpu_cfg_done` | VPU → Core | vsetvl/vsetvli đã hoàn tất, vl_remain hợp lệ |
| `vpu_vl_remain[31:0]` | VPU → Core | Giá trị vl mới để writeback vào rd |

**Stall logic:**
```
  vpu_stall = is_vector_exe && !vpu_ready_i
  stall      = stall_ld | vpu_stall
  → PC, IF/ID, ID/EX registers freeze khi stall=1
```

### 7.2 Scalar Core ↔ DMEM (Port A)

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `s_dmem_addr[31:0]` | Core → DMEM | Byte address |
| `s_dmem_wdata[31:0]` | Core → DMEM | Write data |
| `s_dmem_we` | Core → DMEM | Write enable |
| `s_dmem_be[3:0]` | Core → DMEM | Byte enable (sb/sh/sw) |
| `s_dmem_re` | Core → DMEM | Read enable |
| `s_dmem_rdata[31:0]` | DMEM → Core | Read data (1-cycle latency), muxed với UART |

**UART mux:**
```
  uart_sel = (s_dmem_addr[31:8] == 24'hFF0000)
  dmem_we  = s_dmem_we & ~uart_sel   ← block UART address từ DMEM
  dmem_re  = s_dmem_re & ~uart_sel
  s_dmem_rdata = uart_rd_pending_r ? uart_rdata_r : dmem_rdata
```

### 7.3 VPU ↔ DMEM (Port B via VLSU)

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `vlsu_req` | VPU → DMEM | VLSU yêu cầu memory access |
| `vlsu_we` | VPU → DMEM | 1=write, 0=read |
| `vlsu_addr[31:0]` | VPU → DMEM | Byte address |
| `vlsu_be[3:0]` | VPU → DMEM | Byte enables |
| `vlsu_wdata[31:0]` | VPU → DMEM | Write data |
| `vlsu_rdata[31:0]` | DMEM → VPU | Read data (1-cycle latency) |
| `vlsu_ready` | DMEM → VPU | 1 khi write (ngay), hoặc 1 cycle sau khi read |

### 7.4 HDMI ↔ DMEM (Port A video)

| Tín hiệu | Chiều | Mô tả |
|---|---|---|
| `vid_addr[13:0]` | HDMI → DMEM | Word address (14-bit = 16384 words) |
| `vid_re` | HDMI → DMEM | Read enable |
| `vid_rdata[31:0]` | DMEM → HDMI | Word data (1-cycle latency) |

> Clock domain: `vid_addr`/`vid_re` từ pclk domain (25 MHz), DMEM chạy sys_clk (50 MHz). An toàn vì pclk = sys_clk/2 (PLL-derived, phase-aligned): data ready trong 20 ns (1 sys_clk) < 40 ns (1 pclk).

---

## 8. Timing Summary

| Domain | Clock | Frequency | Nguồn |
|---|---|---|---|
| System | `i_clk` (CLOCK_50) | 50 MHz | Board oscillator trực tiếp |
| Pixel | `pclk_int` (outclk_1) | 25 MHz | PLL từ CLOCK_50 |

| Module | Latency | Ghi chú |
|---|---|---|
| IMEM read | 1 sys_clk | M10K registered output |
| DMEM Port A | 1 sys_clk | M10K registered output |
| DMEM Port B | 1 sys_clk | M10K registered output |
| UART RX byte | ~10 baud × 27 cycles = 270 cycles | 115200 baud, 50 MHz |
| UART TX byte | ~10 baud × 27 cycles = 270 cycles | (idle → done) |
| VPU CONFIG | 1 cycle (ST_CONFIG) | Chỉ update CSR |
| VPU EXEC (VL=16, SEW=8) | 1 cycle (ST_EXEC) | 1 register group |
| VLSU load 16 bytes | 5 cycles | 4 word reads + 1 VRF write |
| HDMI frame | 525 × 800 pclk = 420,000 pclk | ~16.8 ms @ 25 MHz |
| ADV7513 I2C cfg | 14 writes × ~9 bytes × I2C speed | ~1.4 ms @ 400 kHz I2C |
