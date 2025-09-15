; hello_uefi.asm — UEFI x86-64 "Hola mundo" en puro ensamblador (NASM)

BITS 64
default rel

section .text
global efi_main                 ; punto de entrada UEFI

; Convención UEFI x64 (Microsoft x64):
; RCX = EFI_HANDLE ImageHandle
; RDX = EFI_SYSTEM_TABLE* SystemTable

efi_main:
    ; prólogo: marco + shadow space (32B) y alineación
    push rbp
    mov  rbp, rsp
    sub  rsp, 32

    ; RDX = SystemTable*
    ; En x86-64, SystemTable->ConOut está a offset 0x40
    mov  rax, [rdx + 0x40]       ; rax = ConOut*

    ; OutputString(this, CHAR16*)
    mov  rcx, rax                ; RCX = this (ConOut)
    lea  rdx, [rel hello_msg]    ; RDX = &cadena UTF-16
    call [rax + 8]               ; ConOut->OutputString

    ; retorno EFI_SUCCESS (0)
    xor  eax, eax
    add  rsp, 32
    pop  rbp
    ret

section .data
; Cadena en CHAR16 (UTF-16), terminada en 0. CRLF = 13,10
hello_msg: dw 'H','o','l','a',' ','d','e','s','d','e',' ','U','E','F','I','!',13,10,0
