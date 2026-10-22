# TinyPC本編の検証記録（2026-10-22）

## 結果

`impl/` で `make clean all verify` を実行し、終了コード0、**30/30 PASS**を確認した。全8イメージを生成物なしから再ビルドした。すべての本編ソースに `cpu 8086` と `bits 16` を指定している。

検証環境:

```text
NASM version 3.02 compiled on Jun 29 2026
QEMU emulator version 11.1.2
Homebrew LLD 23.1.4 (compatible with GNU linkers)
Python 3.15.0
host: macOS / Apple Silicon
```

## シナリオ

| 検証 | 結果 |
| :--- | :--- |
| `structures` | PASS |
| `reset` | PASS |
| `ch02-vga` | PASS |
| `ch02-uart` | PASS |
| `no-signature` | PASS |
| `ch03-ivt` | PASS |
| `ch04-stage2` | PASS |
| `ch05-bss` | PASS |
| `bss-poison-clear` | PASS |
| `bss-poison-control` | PASS |
| `ch06-shell` | PASS |
| `ch06-input-bounds` | PASS |
| `ch07-memory` | PASS |
| `ch07-invalid-hex` | PASS |
| `ch07-vga` | PASS |
| `ch07-reboot` | PASS |
| `ch09-files` | PASS |
| `fat-free` | PASS |
| `fat-reserved` | PASS |
| `fat-bad` | PASS |
| `fat-out-of-range` | PASS |
| `fat-early-eoc` | PASS |
| `fat-cycle` | PASS |
| `fat-capacity` | PASS |
| `fat-boot-cycle` | PASS |
| `fat-unsupported-bpb` | PASS |
| `fat-fragmented-kernel` | PASS |
| `fat-root-second-sector` | PASS |
| `fat-disk-error` | PASS |
| `fat-oversized-kernel` | PASS |

`bss-poison-clear`はBSSをA5で汚した後に00となること、`bss-poison-control`はクリア処理を外した対照イメージでA5が残ることを確認する。新規RAMが偶然0だったことだけをBSSクリアの証拠にしない。

VGAの文字はテキストメモリを読み出して確認した。自動化で画面の目視確認を代用したとは扱わない。媒体I/Oエラーは、シェルのプロンプト到達後にQEMUモニタからフロッピーを取り出して発生させた。終了したゲスト、ハーネスがSIGTERMで停止したゲスト、rebootでQEMU自体が終了したケースを個別ログに区別して残す。

## 追加照合

- 公開入口 `make run S=ch09 TIMEOUT=1` へコマンドをパイプし、読込み結果とmakeの終了コード0を確認。
- 存在しないQEMU実行パスを渡した場合はmakeが非0で失敗することを確認。
- 最終FAT12イメージの4ファイル（KERNEL.BIN、HELLO.TXT、EDGE.BIN、EMPTY.TXT）をmtoolsの `mcopy` で別ディレクトリへ読み戻し、元のバイト列と完全一致を確認。
- 第2〜7章の完全掲載コードと配布ソースの一致、Markdownの相対リンク、対象Markdown lint、差分チェックを確認。

## 生成物

すべてのディスクイメージは1,474,560バイトで、先頭セクタは512バイト・末尾署名55 AAである。

| ディレクトリ | Stage 2 / kernel.binのサイズ |
| :--- | :--- |
| `ch02a_int10` | ブートセクタのみ |
| `ch02b_serial` | ブートセクタのみ |
| `ch03_hook` | ブートセクタのみ |
| `ch04_stage2` | 136バイト |
| `ch05_kernel` | 417バイト |
| `ch06_shell` | 917バイト |
| `ch07_shellcmds` | 1888バイト |
| `ch09_fat12` | 2825バイト |

第9章loader.bin: 904バイト（予約領域の上限3,584バイト）。

## 証拠と未検証範囲

再現手順は [README.md](README.md)、各実行ログと変形イメージは `transcripts/`、集計は `transcripts/summary.json` にある。生成物とログはGit対象外。再実行時に現在の配布ソースから作成する。

今回の対象はmacOSのQEMU + SeaBIOSである。Linuxでの再実行、GUIの目視、実機PC、長期稼働、任意のBPBや他媒体との互換性は未検証。

Vaultルートで実行した `make verify` は、Go・同期制御等のテストは通ったが、既存のKnowledge索引のリンク切れ26件により入口strict監査が失敗した。TinyPCの `impl/` における `make verify` とは別の検証であり、今回その索引は変更していない。
