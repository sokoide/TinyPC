---
title: TinyPC：INTとIVTの仕組み
type: chapter
topic: 情報・コンピュータ
source:
  - "https://wiki.osdev.org/BIOS"
  - "https://wiki.osdev.org/Interrupt_Vector_Table"
  - "https://www.ctyme.com/rbrown.htm"
  - "https://www.nasm.us/doc/"
created: 2026-10-04
updated: 2026-10-22
tags: [8086, x86, BIOS, 割り込み, IVT, アセンブリ, 教材]
---

# 第3章：INTとIVTの仕組み

[[02_最初のブートセクタ]]では `int 0x10` と `int 0x16` を「BIOSのAPI呼び出し」として使った。本章ではその裏を取る。`int n` はFLAGS・CS・IPをスタックにpushしてから、IVT (Interrupt Vector Table) が指す先へ飛ぶだけの機構であり、IVTは起動後に誰でも書けるRAM上のテーブルである。自作のハンドラを登録して`int 0x28`を発行し、さらにBIOS自身が書いたIVT[0x10]の値を実測する。

## この章の制作順と合格条件

> [!note] 編集者が追加した学習用の補足
> 今回の問いは「呼出しと復帰を対にする」である。IVTエントリを読む → 自作ハンドラのsegment:offsetを書き込む → INT命令で呼ぶ → `iret`後の処理まで確認する。
>
> 合格条件：INTで積まれるFLAGS・CS・IPと、`iret`で戻す順序を図にできる。IF=0でもINT命令は実行できると説明できる。 本編用ソースの収録状況と実験手順は[[学習ガイド]]を参照する。

> [!note] 編集者によるコード補正
> 掲載コードの入口に`cld`を追加し、文字列処理のDF=0を明示した。これは今回の補正であり、既存の逆アセンブル・番地・サイズの実測引用は補正前の記録である。追加命令により、後続のラベル位置は変わりうる。

## IVTはRAM上のテーブル

IVTは物理アドレス0x00000-0x003FFに置かれた256個のベクタ (4バイト/個) である。番号nのベクタはアドレスn×4にあり、下位ワードにoffset、上位ワードにsegmentがリトルエンディアンで並ぶ。

```text
アドレス    内容
0x0000     IVT[0x00] offset   ┐ n=0: INT 00h (除算エラー)
0x0002     IVT[0x00] segment  ┘
0x0004     IVT[0x01] offset   ┐ n=1
0x0006     IVT[0x01] segment  ┘
   ...
0x0040     IVT[0x10] offset   ┐ n=0x10: INT 10h (ビデオサービス)
0x0042     IVT[0x10] segment  ┘
   ...
0x03FC     IVT[0xFF]          ┐ n=0xFF
0x03FE     IVT[0xFF]          ┘
```

Stage 1のTiny6502VMでは、reset vector `$FFFC` はROMの中に固定されていた ([[22_Library/情報・コンピュータ/コンピュータシステム/Tiny6502VM/05_ディスクコントローラとBoot_ROM]])。8086のIVTはRAMであり、電源投入時の中身は不定だが、BIOSがPOST中に書き込んで整える。つまりベクタの実体は「ROMの取り決め」ではなく「BIOSが書いたデータ」であり、OSや常駐プログラムが後から書き換えることも実機では行われてきた。

## int n は何をしているか

`int n` が実行されると、CPUは次の手続きをハードウェアで行う。

1. FLAGSをpushする
2. CS (現セグメント) をpushする
3. IP (次の命令のアドレス) をpushする
4. IVT[n] のoffsetとsegmentを読み、そこへfar jumpする

`iret` はこの逆で、スタックからIP・CS・FLAGSの順にpopして元の流れに戻る。`int n` は飛ぶ前にIF (割り込み許可フラグ) とTF (トレースフラグ) をクリアする。`cli` / `sti` はIFをクリア/セットする命令であり、IFが効くのは実機のINTRピン経由のハードウェア割り込み (キーボードやタイマ) に対してであって、ソフトウェアが `int n` を発行する分にはIFの状態は影響しない。本教材はハードウェア割り込みを使わないポーリング設計であるため、`cli` はhlt前の習慣的な安全策として現れる。

## ch03：自分のハンドラを登録する

実験コードは3部構成である。(1) IVT[0x28]に自作ハンドラを登録して `int 0x28` を3回発行する。(2) IVT[0x10]を読んで16進表示する。(3) INT 16h AH=00hでキー入力を待つ (GUI専用)。全文が次である。

```asm
; ch03_hook/boot.asm - INT/IVT experiments in a boot sector
;
;   (1) Overwrite IVT[0x28] with our own handler and raise INT 0x28:
;       the IVT is just a RAM table, and anyone can register into it.
;   (2) Read IVT[0x10]: the INT 10h video handler that the BIOS itself
;       installed at boot (F000:xxxx points into the BIOS ROM).
;   (3) Wait for keys with INT 16h AH=00h. This works in `make run-gui`;
;       a headless run just sits here until the timeout kills QEMU.

cpu 8086
bits 16
org 0x7C00

; --- IVT layout: entry N is at N*4 (offset word, then segment word) ---
VEC_CUSTOM equ 0x28            ; our playground vector
VEC_VIDEO  equ 0x10            ; BIOS video services
KEY_ESC    equ 0x1B            ; ASCII code that ends the key demo

; --- COM1 16550 UART (same constants as ch02b) ---
COM1         equ 0x3F8
UART_DATA    equ COM1 + 0
UART_IER     equ COM1 + 1
UART_LCR     equ COM1 + 3
UART_LSR     equ COM1 + 5
LCR_8N1      equ 0x03
LCR_DLAB     equ 0x80
LSR_THRE     equ 0x20
BAUD_DIVISOR equ 1

    jmp short start             ; first byte 0xEB: real DOS floppies put the
start:                          ; BPB here, we keep the jump for make dump
    cld                         ; initialize forward string traversal
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7C00

    call uart_init
    mov si, msg_banner
    call puts

    ; --- (1) register our own INT 0x28 handler ---
    mov word [VEC_CUSTOM*4], int28_handler     ; offset part of IVT[0x28]
    mov ax, ds                                 ; our code lives at 0x0000:0x7Cxx
    mov word [VEC_CUSTOM*4 + 2], ax            ; segment part

    mov cx, 3                 ; raise INT 0x28 three times
.int28:
    int 0x28                  ; the handler prints '!'
    loop .int28
    call put_crlf

    ; --- (2) show the video vector the BIOS installed ---
    mov si, msg_ivt
    call puts
    mov ax, [VEC_VIDEO*4 + 2]                  ; segment part of IVT[0x10]
    call put_hex_word
    mov al, ':'
    call putchar
    mov ax, [VEC_VIDEO*4]                      ; offset part
    call put_hex_word
    call put_crlf

    ; --- (3) key input through INT 16h (GUI only) ---
    mov si, msg_key
    call puts
.key:
    mov ah, 0x00
    int 0x16                  ; wait for a key: AL = ASCII, AH = scan code
    mov dx, ax                ; keep the key in DX while printing
    mov si, msg_keyscan
    call puts
    mov al, dh
    call put_hex_byte         ; scan code
    mov si, msg_keyascii
    call puts
    mov al, dl
    call put_hex_byte         ; ASCII code
    cmp dl, 0x20              ; printable?
    jb .noprt
    cmp dl, 0x7F
    jae .noprt
    mov si, msg_keychar
    call puts
    mov al, dl
    call putchar
    mov al, 0x27              ; closing quote
    call putchar
.noprt:
    call put_crlf
    cmp dl, KEY_ESC
    jne .key

    mov si, msg_bye
    call puts
.halt:
    cli
    hlt
    jmp .halt

; --- INT 0x28 handler: print '!' and return with iret ---
int28_handler:
    push ax
    mov al, '!'
    call putchar
    pop ax
    iret

; ---- serial console helpers ----

uart_init:
    push ax
    push dx
    mov dx, UART_IER
    xor al, al
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_DLAB
    out dx, al
    mov dx, UART_DATA
    mov al, BAUD_DIVISOR & 0xFF
    out dx, al
    mov dx, UART_IER
    mov al, BAUD_DIVISOR >> 8
    out dx, al
    mov dx, UART_LCR
    mov al, LCR_8N1
    out dx, al
    pop dx
    pop ax
    ret

putchar:
    push dx
    push ax
    mov dx, UART_LSR
.wait:
    in al, dx
    test al, LSR_THRE
    jz .wait
    mov dx, UART_DATA
    pop ax
    out dx, al
    pop dx
    ret

puts:                         ; DS:SI = NUL-terminated string
    lodsb
    or al, al
    jz .done
    call putchar
    jmp puts
.done:
    ret

put_crlf:
    push ax
    mov al, 13
    call putchar
    mov al, 10
    call putchar
    pop ax
    ret

put_hex_byte:                 ; AL as two hex digits (AX preserved)
    push ax
    push cx
    mov cl, 4
    shr al, cl
    call put_hex_nibble
    pop cx
    pop ax
    and al, 0x0F
    ; fall through
put_hex_nibble:
    push bx
    mov bx, hex_table
    xlatb                     ; AL = hex_table[AL]
    call putchar
    pop bx
    ret

put_hex_word:                 ; AX as four hex digits (AX preserved)
    push ax
    mov al, ah
    call put_hex_byte
    pop ax
    call put_hex_byte
    ret

; ---- data ----
msg_banner   db "ch03: IVT hook demo", 13, 10, 0
msg_ivt      db "INT 10h -> ", 0
msg_key      db "key demo: press keys (ESC quits) - needs make run-gui", 13, 10, 0
msg_keyscan  db "key: scan=", 0
msg_keyascii db " ascii=", 0
msg_keychar  db " '", 0
msg_bye      db "bye", 13, 10, 0
hex_table    db "0123456789ABCDEF"

times 510-($-$$) db 0
dw 0xAA55
```

登録部分の本体はたった2行である。`org 0x7C00` のもとで `int28_handler` は0x7Cxxというoffsetに解決され、セグメントは `ds` (=0) をそのまま書き込む。これでIVT[0x28]は `0x0000:0x7Cxx`、すなわち自分のブートセクタ内を指す。

```asm
    mov word [VEC_CUSTOM*4], int28_handler     ; offset part of IVT[0x28]
    mov ax, ds                                 ; our code lives at 0x0000:0x7Cxx
    mov word [VEC_CUSTOM*4 + 2], ax            ; segment part
```

16進表示は `hex_table db "0123456789ABCDEF"` という16バイトの表を引く形である。`put_hex_nibble` は `xlatb` (AL ← DS:[BX+AL]) でニブルを文字に変換し、`put_hex_byte` は上位ニブル (`shr al, cl` の `mov cl, 4` は8086ではシフト数を即値でなくCLで指定するため) と下位ニブルを続けて出す。8ビット値を2桁、16ビット値を4桁として表示する最小限のヘルパであり、以降の章でも同じ形で使う。

実行する。実測は次のとおりである (最終行のpidは実行のたびに変わる)。

```text
$ make run S=ch03
ch03: IVT hook demo
!!!
INT 10h -> C000:5633
key demo: press keys (ESC quits) - needs make run-gui
qemu-system-i386: terminating on signal 15 from pid 21929 (<unknown process>)
```

`!!!` は `int 0x28` が3回、登録した自作ハンドラへ飛んだ証拠である。IVTは誰でも書けるRAMのテーブルであり、BIOSがAPIとして使っているのと同じ機構を自分で呼べた。

> [!note] 環境差: `C000:` 以降のオフセット
> `INT 10h -> C000:` の後ろのオフセットはSeaVGABIOSのバージョンで変わる。Debian版QEMU 10.0.13 (SeaVGABIOS 1.16.3-debian) での再現検証では `C000:5606` となった。セグメント`C000` (VGAオプションROMがINT 10hをフックしたという構造) は不変であり、debugconログの `Running option rom at c000:0003` と `Start SeaVGABIOS (version 1.16.3-debian-1.16.3-2)` で裏が取れる。検証はオフセット値ではなく構造で行うこと。

## C000:5633は誰が書いたか

次の出力 `INT 10h -> C000:5633` は、IVT[0x10]の実測値である。01章で見たメモリマップでは0xC0000台はBIOS ROM領域 (0xF0000-0xFFFFF) の直前、すなわちSeaBIOS本体ではなくオプションROMの領域である。SeaBIOSのdebugconログを取ると理由がそのまま出る。

```text
Scan for VGA option rom
Running option rom at c000:0003
Start SeaVGABIOS (version rel-1.17.0-0-gb52ca86e094d-prebuilt.qemu.org)
```

SeaBIOSはPOST中にVGA BIOS (SeaVGABIOS) を0xC0000へ置いて実行し、このオプションROMが「INT 10hのハンドラは自分が持つ」とIVT[0x10]をC000:xxxxへ書き換える。実測のC000:5633はそのSeaVGABIOS内のアドレスである。一方、07章のシェルで `dump 0x0` とIVT全体を観測すると、多くのベクタが同じ値 `F000:FF53` を指していることが分かる。これはSeaBIOS本体が多数のベクタに置いているダミーハンドラであり、たとえば実測ではIVT[0..4]は次の値だった。

| n | 実測値 | 実機の仕様での役割 |
| :--- | :--- | :--- |
| 0 | F000:FF53 | INT 00h (除算エラー) |
| 1 | F000:FF53 | INT 01h (トレース) |
| 2 | F000:E2C3 | INT 02h (NMI) |
| 3 | F000:FF53 | INT 03h (ブレークポイント) |
| 4 | F000:FF53 | INT 04h (オーバーフロー) |

つまり「BIOSがIVTを書く」の実態は、(a) SeaBIOSがダミーを多数のベクタに置き、(b) VGAオプションROMがINT 10hだけC000:xxxxへ差し替える、の2段である。01章のリセットエントリ (F000:FFF0) からIVTを通じてAPIに至るまで、どの値も「書いた者がいる」のである。

## GUIでキー入力を体感する

INT 16h AH=00hはキー入力を待つBIOS APIであり、戻るときALにASCIIコード、AHにスキャンコードが入る。キー入力はGUI (`make run-gui S=ch03`) で打鍵しないと発生しないため、headlessの `make run S=ch03` では `key demo:` の表示で止まり、timeoutまでhltせずに待ち続ける。GUIを開いて `a`、`Enter`、`Esc` と打つと、スキャンコードとASCIIが1キー1行で表示され、`Esc` (ASCII 0x1B) でデモが終わる。キーごとのスキャンコードは実機のPC/ATでscan code set 1と呼ばれる値であり、QEMUのPS/2キーボードも同じ値を返す。位置で決まるのが原則である。

| キー | スキャンコード | ASCII |
| :--- | :--- | :--- |
| Esc | 0x01 | 0x1B |
| 1 | 0x02 | 0x31 |
| Backspace | 0x0E | 0x08 |
| Tab | 0x0F | 0x09 |
| Q | 0x10 | 0x71 |
| Enter | 0x1C | 0x0D |
| A | 0x1E | 0x61 |
| Z | 0x2C | 0x7A |
| Space | 0x39 | 0x20 |

> [!warning] pushしたらpop、iretは3ワード戻す
> この教材の参照実装を作ったとき、実際にスタック均衡の破れで暴走したことがある。シェル (07章) のivtコマンドに対応するpopのない `push ax` が1個残っており、`ret` がスタックに残っていた値 — 直前にIVTから読んだセグメント部分 (F000) — をリターンアドレスとしてpopした。結果、CPUはセグメントF000、すなわちBIOS ROM領域のゼロ列 (00 00) を実行し始めた。`-d in_asm -D trace.log` で最後のまともな実行ブロックが `retw` であること、直後にセグメントF000内で `add %al,(%bx,%si)` (00 00をadd命令として解釈したもの) が回っていることを確認して特定できた。ハンドラを書く場合、`int n` がpushした3ワード (FLAGS・CS・IP) を `iret` がちょうど消費すること、ハンドラ内でpushしたものは自分でpopすること、そしてどちらも壊れると「それらしく動いた後に暴走する」ことを、この実例は示している。

## まとめ

- IVTは物理0x00000-0x003FFのRAM上のテーブルで、ベクタnはn×4番地のoffset+segment。電源投入時は不定で、BIOSがPOST中に書く
- `int n` はFLAGS・CS・IPをpushしてIVT[n]へfar jumpする機構であり、`iret` がその逆。IFはハードウェア割り込みの許可bitであり、ソフトウェアの `int n` には無関係
- 自作ハンドラはIVTへの2ワードの書き込みで登録できる。IVTは誰でも書けるRAMのテーブルであり、BIOSのAPIもその上に成り立つ
- IVT[0x10]の実測値C000:5633はSeaVGABIOSオプションROMが書いたものであり、多数のベクタにはSeaBIOS本体のダミーF000:FF53が置かれている
- 16進表示は `"0123456789ABCDEF"` の表を引くヘルパで作る。スタック均衡 (push/pop、iretの3ワード) の破れは静かな暴走になる

INTでBIOSのAPIを自由に呼べるようになった。[[04_ディスク読み込みと2段階ブート]]では、この仕組みを使ってディスク (INT 13h) からセクタを読み、512バイトの制約から抜ける2段階ブートを作る。

## 演習

1. 実験 (2) の `VEC_VIDEO equ 0x10` を `0x00` に変えて実行すると、IVT[0x00]の値が表示される。答え: 実測では `F000:FF53` であり、0番 (除算エラー) にはSeaBIOSのダミーハンドラが置かれていることを示す。
2. `int28_handler` に `inc cx` を1行追加すると `!!!` の個数はどうなるか予想してから実行する。答え: `loop .int28` はCXをデクリメントしてから判定するため、ハンドラ内の `inc cx` がそれを打ち消し、CXが0に届かず `!` が無限に出続ける。ハンドラが呼び出し側のレジスタを壊すと何が起きるかの実例である。
3. `int28_handler` に余分な `push ax` を足してpopを増やさずに実行し、挙動を観察する。答え: `iret` が3ワードではなく余計な値をCS/IPとして消費して飛び先が壊れ、QEMUを強制終了 (`timeout` のkill) するまで暴走する。警告calloutの実例を自分の手で再現する。
4. `int28_handler` の最後の `iret` を `ret` に変えるとどうなるか。答え: `ret` は1ワード (IP相当) しかpopしないため、スタックに残ったCS・FLAGSが次のリターンアドレスとして使われ、やはり暴走する。`int n` がpushする3ワードと `iret` の対応を確認する実験である。
