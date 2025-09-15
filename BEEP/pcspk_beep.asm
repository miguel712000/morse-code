; pcspk_beep.asm — BOOT SECTOR educativo (NO usar para la entrega UEFI)
; Ensambla: nasm -f bin pcspk_beep.asm -o pcspk_beep.bin
; Correr en QEMU: qemu-system-i386 -drive file=pcspk_beep.bin,format=raw -audiodev pa,id=snd0 -machine pcspk-audiodev=snd0

BITS 16
ORG 0x7C00

start:
    ; configurar PIT canal 2 en modo 3 (square wave generator)
    mov al, 0b10110110       ; canal 2, lobyte/hibyte, modo 3, binario
    out 0x43, al

    ; ---- beep 440 Hz (~La4) ----
    mov bx, 2712             ; 1193182 / 440 ≈ 2712
    mov al, bl
    out 0x42, al             ; low byte
    mov al, bh
    out 0x42, al             ; high byte

    ; habilitar speaker (bits 0 y 1 de 0x61)
    in  al, 0x61
    mov ah, al
    or  al, 0b00000011
    out 0x61, al

    ; pequeña espera ~200 ms (delay burdo por software)
    call delay_200ms

    ; ---- beep 880 Hz ----
    mov al, 0b10110110
    out 0x43, al
    mov bx, 1356             ; 1193182 / 880 ≈ 1356
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al
    in  al, 0x61
    or  al, 0b00000011
    out 0x61, al
    call delay_200ms

    ; apagar speaker (limpiar bits 0 y 1)
    in  al, 0x61
    and al, 0b11111100
    out 0x61, al

hang:
    jmp hang

; ---- delay aproximado (muy burdo) ----
delay_200ms:
    ; Este bucle consume tiempo en una PC emulada típica.
    ; Ajusta CX/loops si te suena muy corto/largo en tu QEMU.
    mov cx, 0xFFFF
.delay_outer:
    mov dx, 0x2000
.delay_inner:
    dec dx
    jnz .delay_inner
    loop .delay_outer
    ret

; Firma de boot sector
times 510-($-$$) db 0
dw 0xAA55
