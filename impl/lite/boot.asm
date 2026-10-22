bits 16                       ; NASMに16ビット用の機械語を生成させる指定（CPUへの命令ではない）
org  0x7C00                   ; RAMの0x7C00に配置される前提でラベルの値を計算する

start:
	cli                          ; マスク可能な外部割り込みを禁止する（INT命令は禁止されない）
	mov ax, 0                 ; AXに0を入れる
	mov  ss, ax                  ; SS=0。スタックのセグメント基準を物理アドレス0にする
	mov  sp, 0x7C00              ; スタックの初期位置。PUSHやINTで使用する領域はここから下へ伸びる
	mov  ds, ax                  ; DS=0。文字列や変数の物理アドレスはDS×16+オフセットで求める
	mov  es, ax                  ; ES=0。ディスク読込み先ES:BXのセグメント部分を設定する
	sti                          ; 外部割り込みを許可する。SS:SP設定後にBIOSサービスを利用する
	mov  [boot_drive], dl        ; BIOSがDLで渡した起動ドライブ番号をメモリの変数へ保存する
	mov  si, boot_message        ; SIに表示文字列の先頭位置を入れる（文字そのものではない）
	call puts                    ; 戻り先をスタックへ保存し、文字列表示処理putsへ移る

	mov ax, 0x0201               ; AH=02hはセクタ読込み機能、AL=01hは読み込むセクタ数
	mov bx, 0x8000               ; ES:BX=0000:8000。512バイトをRAMの0x8000から格納する
	mov cx, 0x0002               ; CH=0はシリンダ0、CL=2はセクタ2（セクタ番号は1から始まる）
	mov dh, 0                 ; DH=0。フロッピーのヘッド0を指定する
	mov dl, [boot_drive]         ; 保存した起動ドライブ番号をDLへ戻し、読むドライブを指定する
	int 0x13                     ; BIOSのディスク処理を呼ぶ。読込み後は次の命令へ戻る
	jc  disk_error               ; BIOSがCF=1を返した場合は読込み失敗としてエラー処理へ移る
	jmp 0x0000:0x8000            ; CS=0、IP=0x8000に設定し、読み込んだStage 2の実行を始める

disk_error:
	mov  si, error_message       ; 読込み失敗を知らせる文字列の先頭位置をSIへ入れる
	call puts                    ; 戻り先をスタックへ保存し、文字列表示処理putsへ移る

.halt:
	cli                          ; マスク可能な外部割り込みを禁止する（INT命令は禁止されない）
	hlt                          ; CPUを待機させる。QEMUの終了命令ではない
	jmp .halt                    ; 停止処理へ戻り、待機を繰り返す

puts:
	mov al, [si]              ; DS:SIが指す1バイトをALへ読む
	inc si                    ; SIを1増やし、次の文字を指す
	cmp al, 0                 ; ALを文字列終端の0と比較する。ALの値は変えない
	je   .done                   ; AL=0（文字列終端）なら呼出し元へ戻る処理へ移る
	mov  ah, 0x0E                ; BIOS画面出力の機能番号。ALに入っている1文字を出力する
	mov  bx, 0x0007              ; BH=0で表示ページ0。BL=7はグラフィックスモード用で、ここでは使われない
	int  0x10                    ; BIOSの画面処理を呼ぶ。AH=0EhなのでALの1文字を表示する
	jmp  puts                    ; putsの先頭へ戻って次の文字を処理する（CALLと違い戻り先は積まない）

.done:
	ret                          ; CALLがスタックに保存した戻り先を取り出し、呼出し元へ戻る

boot_message  db 'Booting...', 13, 10, 0 ; 起動メッセージ。13と10は復帰・改行、0は文字列終端
error_message db 'Disk read failed', 13, 10, 0 ; 読込み失敗時のメッセージをバイト列として配置する
boot_drive    db 0            ; 起動ドライブ番号を保存する1バイトの領域（初期値は0）

times 510-($-$$) db 0         ; 現在までの長さ($-$$)を510バイトから引き、残りを0で埋める
dw    0xAA55                  ; 署名を2バイトで配置する。リトルエンディアンなので順序は55 AA
