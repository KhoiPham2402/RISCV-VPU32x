/*
 * Harvard: PC reads IMEM; load/store → LSU → dmem[addr[10:2]] (byte 0..0x7FF).
 *
 * IMEM (rx, 8KB):  .text.init  .text  .rodata
 * DMEM (rw, 2KB):  .bss   (zero-initialized globals — zeroed by crt0)
 *
 * IMPORTANT — Harvard constraint:
 *   .rodata lives in IMEM and is NOT accessible by scalar LW/LH/LB.
 *   Only use compile-time constants (#define, immediate literals) in C.
 *   Pointer-like access to fixed DMEM addresses (0x000–0x7FF) works fine.
 *
 * Stack: crt0 sets sp = 0x7F0 (top of DMEM).
 */
ENTRY(_start)
MEMORY {
  imem (rx) : ORIGIN = 0x00000000, LENGTH = 8K
  dmem (rw) : ORIGIN = 0x00000000, LENGTH = 2K
}

SECTIONS {
  .text : {
    *(.text.init)           /* crt0 _start must be first → lands at 0x000 */
    *(.text .text.*)
  } > imem

  .rodata : {
    *(.rodata .rodata.*)
  } > imem

  /* BSS: zero-initialized globals live in DMEM.
     crt0 zeroes __bss_start .. __bss_end before calling main(). */
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*) *(COMMON)
    __bss_end = .;
  } > dmem

  /DISCARD/ : { *(.eh_frame*) }
}
