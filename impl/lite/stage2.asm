bits 16                       ; NASMに16ビット用の機械語を生成させる指定（CPUへの命令ではない）
org  0x8000                   ; Stage 1が読み込むRAMの位置0x8000にラベルの基準を合わせる

start:
	mov ax, 0                 ; AXに0を入れる
	mov ds, ax                   ; DS=0。文字列や変数の物理アドレスはDS×16+オフセットで求める
	mov si, message              ; SIに表示文字列の先頭位置を入れ、DS:SIで先頭の文字を指す

.next:
	mov al, [si]              ; DS:SIが指す1バイトをALへ読む
	inc si                    ; SIを1増やし、次の文字を指す
	cmp al, 0                 ; ALを文字列終端の0と比較する。ALの値は変えない
	je   .halt                   ; AL=0（文字列終端）なら表示を終え、停止処理へ移る
	mov  ah, 0x0E                ; BIOS画面出力の機能番号。ALに入っている1文字を出力する
	mov  bx, 0x0007              ; BH=0で表示ページ0。BL=7はグラフィックスモード用で、ここでは使われない
	int  0x10                    ; BIOSの画面処理を呼ぶ。AH=0EhなのでALの1文字を表示する
	jmp  .next                   ; 次の文字を読み出すため、文字列処理ループの先頭へ戻る

.halt:
	cli                          ; マスク可能な外部割り込みを禁止する（INT命令は禁止されない）
.wait:
	hlt                          ; CPUを待機させる。QEMUの終了命令ではない
	jmp .wait                    ; 待機から復帰した場合も、HLTへ戻って待機を繰り返す

message db 'Hello from Stage 2!', 13, 10, 0 ; Stage 2の文字列。最後の0は表示せず、ループを終える目印にする
