OUTPUT_FORMAT("binary")

ENTRY(_start)

SECTIONS
{
    . = 0x2000;

    .text   : { *(.text) }
    .rodata : { *(.rodata) }
    .data   : { *(.data) }
    .bss    : { __bss_start = .; *(.bss) __bss_end = .; }
    ASSERT(__bss_end <= 0x2E00, "loader RAM exceeds reserved load window")
}
