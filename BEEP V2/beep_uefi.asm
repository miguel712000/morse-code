; beep_uefi.asm — UEFI x86-64: imprime un mensaje y suena 2 beeps
; Ensamble:
;   nasm -f win64 beep_uefi.asm -o beep_uefi.obj
;   lld-link /subsystem:efi_application /entry:efi_main /out:BOOTX64.EFI beep_uefi.obj
;     (o) ld.lld -m i386pep -subsystem:efi_application -entry:efi_main -o BOOTX64.EFI beep_uefi.obj

BITS 64
default rel

section .text
global efi_main

; Convención UEFI x64 (Microsoft x64):
; RCX = ImageHandle, RDX = EFI_SYSTEM_TABLE*

efi_main:
    ; prólogo: marco + shadow space (32B) y alineación para CALL
    push rbp
    mov  rbp, rsp
    sub  rsp, 32

    ; ---- Imprime una línea para saber que corrió ----
    mov  rax, [rdx + 0x40]       ; ConOut*
    mov  rcx, rax
    lea  rdx, [rel msg]
    call [rax + 8]               ; ConOut->OutputString(this, CHAR16*)

    ; ---- Beep 440 Hz por ~200 ms ----
    mov  ecx, 440                ; RCX (32 bits) = frecuencia
    call pit_set_freq
    call speaker_on
    mov  ecx, 200                ; ~200 ms (ajustable)
    call delay_ms
    call speaker_off

    ; ---- Beep 880 Hz por ~200 ms ----
    mov  ecx, 880
    call pit_set_freq
    call speaker_on
    mov  ecx, 200
    call delay_ms
    call speaker_off

    ; return EFI_SUCCESS
    xor  eax, eax
    add  rsp, 32
    pop  rbp
    ret

; ----------------------------
; pit_set_freq(RCX=freq_hz)
; Programa el PIT canal 2 (modo 3) con divisor = 1193182 / freq
; ----------------------------
pit_set_freq:
    mov   eax, 1193182
    xor   edx, edx
    div   ecx                   ; EAX = divisor (32-bit), evita freq=0!
    ; Control word: canal 2, lobyte/hibyte, modo 3, binario
    mov   al, 0b10110110
    out   0x43, al
    ; Enviar divisor (low byte primero, luego high)
    mov   edx, eax              ; copia divisor
    mov   al, dl
    out   0x42, al
    mov   al, dh
    out   0x42, al
    ret

; ----------------------------
; speaker_on(): habilita bits 0 y 1 en puerto 0x61
; ----------------------------
speaker_on:
    in    al, 0x61
    or    al, 0b00000011
    out   0x61, al
    ret

; ----------------------------
; speaker_off(): apaga bits 0 y 1 en puerto 0x61
; ----------------------------
speaker_off:
    in    al, 0x61
    and   al, 0b11111100
    out   0x61, al
    ret

; ----------------------------
; delay_ms(RCX=millis) — busy-wait burdo (ajusta la constante si suena muy corto/largo)
; ----------------------------
delay_ms:
    mov   r8, rcx               ; r8 = ms (registro volátil, no hace falta preservarlo)
.outer:
    mov   ecx, 60000            ; <- constante “loops por ms” (ajústar)
.inner:
    dec   ecx
    jnz   .inner
    dec   r8
    jnz   .outer
    ret

section .data
msg: dw 'UEFI Beep demo',13,10,0
