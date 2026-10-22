OUTPUT_FORMAT("binary")

ENTRY(_start)

SECTIONS
{
    . = 0x8000;

    .text   : { *(.text) }
    .rodata : { *(.rodata) }
    .data   : { *(.data) }
    .bss    : { __bss_start = .; *(.bss) __bss_end = .; }
    ASSERT(__bss_end <= 0xC000, "kernel RAM exceeds the load window")
}
