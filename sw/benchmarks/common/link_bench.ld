OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    imem (rx) : ORIGIN = 0x00000000, LENGTH = 8K
}

_stack_top = 0x7F0;

SECTIONS {
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > imem

    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > imem

    /DISCARD/ : {
        *(.eh_frame*)
        *(.riscv.attributes)
        *(.comment)
    }
}
