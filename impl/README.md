# TinyPC本編の配布実装

第2〜7章と第9章に対応する8種類のフロッピーイメージをビルドする。第1章のリセット観測は検証スクリプトに含む。第8章は復習である。Liteは `lite/` のMakefileで独立して動き、本編から参照しない。

## 必要なもの

NASM、QEMU（SeaBIOSを使える `qemu-system-i386`）、LLVMの `ld.lld`、Python 3、make、dd、GNU timeout。ホストのCコンパイラ、mtools、ディスクのマウントは不要。

macOSの導入例:

```sh
brew install nasm qemu llvm coreutils python
```

Debian/Ubuntuの導入例（今回の再検証はmacOSのみ）:

```sh
sudo apt-get install nasm qemu-system-x86 lld python3 make coreutils
```

各コマンドがPATHにあることを確認する。HomebrewのLLVMがPATHにない場合は `make LK="$(brew --prefix llvm)/bin/ld.lld"` のように指定する。

## 実行

このREADMEと同じディレクトリで実行する。

```sh
make all
make verify
printf 'help\necho hi\nq\n' | make run S=ch06
printf 'ls\nload HELLO.TXT\ndump 600 e\nq\n' | make run S=ch09
make run-gui S=ch02a
make dump S=ch07
```

`make run` は5秒で観測を終える。`TIMEOUT=10`などで変更できる。ゲストの `q` はCPUを停止するがQEMUを終了しない。headless実行はGNU timeoutで終了させ、その終了コード124を許容する。その他のQEMUエラーは隠さない。GUIではウィンドウを閉じて終了する。

第6章以降のシェルはCOM1を接続した端末から操作する。GUIでもシェル入力先は端末であり、QEMUのVGAウィンドウではない。第3章のBIOSキー入力実験はVGAウィンドウから行う。

| `S=` | ディレクトリ | 確認するもの |
| :--- | :--- | :--- |
| ch02a | ch02a_int10 | BIOS INT 10hの文字列表示（VGA画面） |
| ch02b | ch02b_serial | UARTの文字列表示（端末） |
| ch03 | ch03_hook | 自作INTハンドラ、IVT、BIOSキー入力 |
| ch04 | ch04_stage2 | LBA 1〜32を0x8000へ読む2段階ブート |
| ch05 | ch05_kernel | ELF32オブジェクトのリンク、crt0、BSS、main |
| ch06 | ch06_shell | getline、トークン分割、help/echo/cls/q |
| ch07 | ch07_shellcmds | peek/dump/poke/ivt/mem/ticks/vga/reboot |
| ch09 | ch09_fat12 | KERNEL.BINの名前によるロード、ls/load |

`NASM=...`、`LK=...`、`QEMU=...`、`PYTHON=...`でツールを指定できる。`make clean`は本編の生成物だけを削除し、ソース・Lite・検証ログは残す。

## 実装の境界

すべての本編アセンブリは `cpu 8086` と `bits 16` を指定する。QEMU自体のCPUやSeaBIOSを8086へ制限するものではない。第4〜7章のブートはドライブA・1.44MBのCHSに限定する。UARTはポーリングで、自作IRQハンドラは実装しない。

各章のコードは比較しやすいように章ごとのディレクトリへ置く。第9章だけは、予約領域ローダとカーネルが同じ `common/fat12.s` を別々にリンクする。

第9章の起動経路:

```text
SeaBIOS → boot.asm (0x7C00)
          → LBA 1..7のloader.bin (0x2000)
            → FAT12のKERNEL.BIN (0x8000)
              → crt0 → main → shell
```

第9章の固定BPBは予約8セクタ・FAT 2個×9セクタ・ルート224件・512バイト/セクタ・1セクタ/クラスタ・総2880セクタ・CHS 18×2である。rootはLBA 26、データはLBA 40から始まる。一般的な予約1セクタの媒体とは配置が異なる。

`mkfat12.py`がブート、予約領域ローダ、FAT、ディレクトリ、ファイルを配置する。書込み、サブディレクトリ、長い名前、任意のBPB、FAT複製からの復旧には対応しない。シェルのロード先は0x0600〜0x6FFF、スタック用に0x7000〜0x7BFFを残す。カーネル上限はBSSを含めて0xC000未満までとし、リンカも検査する。

`fat_load`はファイルサイズをセクタ単位へ丸めて容量と照合し、チェーン長の厳密な一致を要求する。失敗時の転送済みデータは巻き戻さない。呼出し側はCF=1の内容を使わない。

## 自動検証と証拠

`make verify` は8イメージをビルドして `verify.py` を実行する。検証の終了コードは、いずれか失敗なら非0である。

- 署名・サイズ、8086指定、リンク時の `_start` の位置、リセットトレース。
- VGAメモリの文字、UART、INT/IVT、Stage 2、BSS、シェル。
- BSSをA5で汚した後のクリアと、クリアを除去した対照実験。
- 空行、CRLF、Backspace、行長と引数の上限、不正な16進数と範囲外の値。
- メモリ操作、BIOS表示、再起動時のQEMU自発終了。
- FAT12の通常ファイル、空ファイル、断片化、奇数・偶数エントリのセクタ境界、次セクタのディレクトリ。
- 不正チェーン、容量超過、未対応BPB、媒体取出し後のI/O失敗。
- 断片化したカーネルの起動、不正・過大なカーネルでの停止。

`transcripts/summary.json` に各項目のPASS/FAIL、個別 `.txt` にQEMUコマンド・出力・終了理由を保存する。異常系のコピーとVGA・モニタ確認用のログも同ディレクトリを使う。生成物とログはGit対象外である。

検証スクリプトは停止したゲストをSIGTERMで終了させる。QEMUがこのシグナルを処理して終了コード0を返す環境もあるため、終了コードだけで正常終了と判定しない。タイムアウトによる停止理由と必要な出力を確認する。`reboot`はハーネスが止める前にQEMUが自発的に終了することを別に確認する。

GUIの目視、実機PC、長期稼働、Linuxでの今回の再実行は未検証。現時点の結果は [VERIFICATION.md](VERIFICATION.md) を参照する。
