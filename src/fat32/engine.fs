; Hardware FAT32 engine firmware (MEGA65/mega65-core#766).
; Assembled by src/tools/fat32asm / run by src/tools/fat32sim.py; design in
; docs/sdcard-native/fat32-engine.md.  Phase 1: read-only.
;
; Register conventions (kept across subroutines unless noted):
;   R5  drive in use (1..8)       R11 sectors per cluster  R13 log2 of it
;   R14 number of FATs            L4  root cluster          L5  FAT size
;   L6  FAT LBA (absolute)        L7  LBA of cluster 2 (absolute)
;   directory walk: L0 cluster, R3 sector in cluster, R4 entry in sector,
;   X the entry (in the engine sector)
;   R12 the error code (error)    R0-R2, R6-R10, L1-L3 are scratch

; ---- memory ----------------------------------------------------------------
.equ DRV,      $000      ; 8 drives x 32
.equ D_FLAGS,  0         ; bit 0 valid, bit 1 slot
.equ D_SPCL,   1
.equ D_NFATS,  2
.equ D_TYPE,   3
.equ D_PART,   4
.equ D_FAT,    8
.equ D_FATSZ,  12
.equ D_DATA,   16
.equ D_ROOT,   20
.equ D_NCL,    24
.equ D_SIZE,   28
.equ FD,       $100      ; 8 descriptors x 48
.equ F_FLAGS,  0         ; bit 0 open, 1 directory, 2 write, 3 append
.equ F_DRIVE,  1
.equ F_ATTR,   2
.equ F_FIRST,  4
.equ F_CUR,    8         ; a cluster of the file (files) / the directory walk (dirs)
.equ F_CIDX,   12        ; files: index of F_CUR in the chain; dirs: sector, entry
.equ F_POS,    16
.equ F_SIZE,   20
.equ F_DLBA,   24        ; the directory entry: sector (absolute)
.equ F_DOFF,   28        ;   and offset in it
.equ F_SLOT,   30
.equ CWD,      $280      ; 8 x 4: the current directory's cluster (0 = root)
.equ G_DRIVE,  $2A0      ; the current drive
.equ G_NDRV,   $2A1      ; drives found
.equ G_SYS,    $2A2      ; SYSTEM entries visible to programs
.equ G_PATHP,  $2A4      ; (2) the path being resolved
.equ G_DLBA,   $2A8      ; (4) the last entry found: sector
.equ G_DOFF,   $2AC      ; (2)   and offset
.equ G_CHILD,  $2B0      ; (4) getcwd: the directory being named
.equ G_PARENT, $2B4      ; (4)   its parent
.equ G_OUT,    $2B8      ; (2)   where the path starts (built backwards)
.equ ENT,      $2C0      ; (32) a copy of the last entry found
.equ NAME,     $300      ; 256: the path component
.equ LFN,      $400      ; 256: the long filename being assembled
.equ SHORT,    $500      ; 16: an 8.3 name as text
.equ PTBL,     $510      ; 64: the partition table being scanned
.equ SEC,      $800      ; the engine's sector
.equ REQ,      $E00      ; request / response block (the CPU's sector buffer)
.equ R_OP,     3
.equ R_FD,     4
.equ R_FLAGS,  5
.equ R_ARG0,   6
.equ R_ARG1,   10
.equ R_DATA,   16

; ---- error codes -------------------------------------------------------------
.equ E_NOENT,  1
.equ E_NOTDIR, 2
.equ E_ISDIR,  3
.equ E_BADFD,  4
.equ E_NFILE,  5
.equ E_NODRV,  6
.equ E_IO,     7
.equ E_END,    8
.equ E_ACCESS, 9
.equ E_BADREQ, 10
.equ E_LONG,   11
.equ E_ROFS,   15

; ==============================================================================
start:
        cmd r0
        cmpi r0, $70
        jz request
        cmpi r0, $71
        jz cmd_read
        cmpi r0, $74
        jz cmd_readsector
        fail E_BADREQ

; ---- $70: a request block ----------------------------------------------------
request:
        xset REQ
        ld r0, [x+0]
        cmpi r0, 'F'
        jnz bad_request
        ld r0, [x+1]
        cmpi r0, '3'
        jnz bad_request
        ld r0, [x+R_OP]
        cmpi r0, 1
        jz op_rescan
        cmpi r0, 2
        jz op_partitions
        cmpi r0, 3
        jz op_setdrive
        cmpi r0, $10
        jz op_opendir
        cmpi r0, $11
        jz op_readdir
        cmpi r0, $12
        jz op_chdir
        cmpi r0, $13
        jz op_getcwd
        cmpi r0, $20
        jz op_open
        cmpi r0, $22
        jz op_close
        cmpi r0, $23
        jz op_seek
        cmpi r0, $24
        jz op_stat
bad_request:
        ldi r12, E_BADREQ
        jmp error

; the response header, status R12 = 0
ok:
        ldi r12, 0
error:
        xset REQ
        ldi r0, 'F'
        st r0, [x+0]
        ldi r0, '3'
        st r0, [x+1]
        ldi r0, 1
        st r0, [x+2]
        st r12, [x+R_OP]
        cmpi r12, 0
        jnz error2
        done
error2:
        failr r12

; ==============================================================================
; rescan: the MBRs of the external card (slot 1), then the internal (slot 0);
; up to 4 FAT32 partitions each become drives 1.. (8 at most)
op_rescan:
        ldi r0, 0
        yset DRV
        ldi r1, 0
        fill r1                         ; 256 bytes: the drive table
        yset CWD
        ldi r1, 32
        fill r1
        ldi r5, 0                       ; drives so far
        ldi r9, 1                       ; slot
rs_slot:
        slot r9
        lldi l2, 0
        sread l2
        je rs_next_slot
        xset SEC+510
        ld r0, [x+0]
        cmpi r0, $55
        jnz rs_next_slot
        ld r0, [x+1]
        cmpi r0, $AA
        jnz rs_next_slot
        xset SEC+446                    ; keep the partition table
        yset PTBL
        ldi r1, 64
        copy r1
        ldi r8, 0                       ; entry
rs_entry:
        xset PTBL
        mov r0, r8
        shl r0
        shl r0
        shl r0
        shl r0
        xadd r0
        ld r0, [x+4]
        cmpi r0, $0B
        jz rs_fat32
        cmpi r0, $0C
        jz rs_fat32
        jmp rs_next_entry
rs_fat32:
        cmpi r5, 8
        jz rs_done
        mov r10, r0                     ; type
        lld l1, [x+8]                   ; partition LBA
        lld l3, [x+12]                  ; partition size
        sread l1
        je rs_next_entry
        xset SEC
        lldw l2, [x+11]                 ; bytes per sector
        lcmpi l2, 512
        jnz rs_next_entry
        lldw l2, [x+22]                 ; FAT16 size: 0 on FAT32
        lz l2
        jnz rs_next_entry
        ld r6, [x+16]                   ; FATs
        cmpi r6, 0
        jz rs_next_entry
        ld r0, [x+13]                   ; sectors per cluster -> log2
        cmpi r0, 0
        jz rs_next_entry
        ldi r7, 0
rs_log2:
        cmpi r0, 1
        jz rs_log2_done
        shr r0
        jc rs_next_entry                ; (not a power of 2)
        inc r7
        jmp rs_log2
rs_log2_done:
        ; the drive's record: Y = DRV + 32 * R5
        btol l2, r5
        lshl l2, 5
        laddi l2, DRV
        yl l2
        mov r0, r9
        shl r0
        ori r0, 1
        st r0, [y+D_FLAGS]
        st r7, [y+D_SPCL]
        st r6, [y+D_NFATS]
        st r10, [y+D_TYPE]
        lst l1, [y+D_PART]
        lst l3, [y+D_SIZE]
        lldw l2, [x+14]                 ; reserved sectors
        ladd l2, l1
        lst l2, [y+D_FAT]
        lld l0, [x+36]                  ; FAT size
        lst l0, [y+D_FATSZ]
rs_fats:
        ladd l2, l0                     ; + FATs x FAT size
        dec r6
        jnz rs_fats
        lst l2, [y+D_DATA]
        lld l0, [x+44]
        lst l0, [y+D_ROOT]
        lld l0, [x+32]                  ; clusters: (total - (data - part)) >> spcl + 2
        lsub l2, l1
        lsub l0, l2
        lshrr l0, r7
        laddi l0, 2
        lst l0, [y+D_NCL]
        inc r5
        ; (the MBR is in PTBL: the next entry needs no re-read)
rs_next_entry:
        inc r8
        cmpi r8, 4
        jnz rs_entry
rs_next_slot:
        cmpi r9, 0
        jz rs_done
        ldi r9, 0
        jmp rs_slot
rs_done:
        xset G_DRIVE
        st r5, [x+1]                    ; G_NDRV
        ldi r0, 0
        cmpi r5, 0
        jz rs_nodrive
        ldi r0, 1
rs_nodrive:
        st r0, [x+0]                    ; G_DRIVE
        xset REQ
        btol l0, r5
        lst l0, [x+R_ARG0]
        jmp ok

; partitions: R_ARG0 = count; 16 bytes each at R_DATA: drive, slot, type,
; log2 sectors per cluster, partition LBA, size, clusters
op_partitions:
        xset G_NDRV
        ld r5, [x+0]
        xset REQ
        btol l0, r5
        lst l0, [x+R_ARG0]
        ldi r1, 0
        yset REQ+R_DATA
pl_loop:
        cmp r1, r5
        jz ok
        btol l2, r1
        lshl l2, 5
        laddi l2, DRV
        xl l2
        mov r0, r1
        inc r0
        st r0, [y+0]
        ld r0, [x+D_FLAGS]
        shr r0
        st r0, [y+1]
        ld r0, [x+D_TYPE]
        st r0, [y+2]
        ld r0, [x+D_SPCL]
        st r0, [y+3]
        lld l0, [x+D_PART]
        lst l0, [y+4]
        lld l0, [x+D_SIZE]
        lst l0, [y+8]
        lld l0, [x+D_NCL]
        lst l0, [y+12]
        yaddi 16
        inc r1
        jmp pl_loop

; setdrive: R_ARG0 = drive (1..8)
op_setdrive:
        xset REQ
        ld r5, [x+R_ARG0]
        call usedrive
        xset G_DRIVE
        st r5, [x+0]
        jmp ok

; ==============================================================================
; usedrive: R5 = drive (0 = the current one) -> the registers of its FAT
usedrive:
        cmpi r5, 0
        jnz ud_have
        xset G_DRIVE
        ld r5, [x+0]
ud_have:
        cmpi r5, 0
        jz ud_bad
        cmpi r5, 9
        jnc ud_bad
        btol l2, r5
        laddi l2, -1
        lshl l2, 5
        laddi l2, DRV
        xl l2
        ld r0, [x+D_FLAGS]
        mov r1, r0
        andi r1, 1
        jz ud_bad
        shr r0
        slot r0
        ld r13, [x+D_SPCL]
        ld r14, [x+D_NFATS]
        lld l6, [x+D_FAT]
        lld l5, [x+D_FATSZ]
        lld l7, [x+D_DATA]
        lld l4, [x+D_ROOT]
        ldi r11, 1                      ; sectors per cluster
        mov r0, r13
ud_spc:
        cmpi r0, 0
        jz ud_ok
        shl r11
        dec r0
        jmp ud_spc
ud_ok:
        ret
ud_bad:
        ldi r12, E_NODRV
        jmp error

; L2 = the LBA of cluster L0, sector R3
clus2lba:
        lmov l2, l0
        laddi l2, -2
        lshlr l2, r13
        ladd l2, l7
        btol l1, r3
        ladd l2, l1
        ret

; ---- directory walk ------------------------------------------------------------
; dw_start: L0 = directory cluster (0 = root) -> the first entry
dw_start:
        lz l0
        jnz dws_have
        lmov l0, l4
dws_have:
        ldi r3, 0
        ldi r4, 0
dw_load:
        call clus2lba
        sread l2
        je io_error
        xset SEC
        btol l1, r4
        lshl l1, 5
        laddi l1, SEC
        xl l1
        ret
; dw_next: the next entry; Z set at the end of the chain
dw_next:
        inc r4
        cmpi r4, 16
        jz dwn_sector
        xaddi 32
        ldi r0, 1                       ; (Z = 0)
        ret
dwn_sector:
        ldi r4, 0
        inc r3
        cmp r3, r11
        jnz dwn_load
        ldi r3, 0
        fatnx l0
        jz dwn_end
dwn_load:
        call dw_load
        ldi r0, 1                       ; (Z = 0)
        ret
dwn_end:
        ldi r0, 0                       ; Z = 1
        ret

io_error:
        ldi r12, E_IO
        jmp error

; ---- names -----------------------------------------------------------------------
; fmt83: the 8.3 name of the entry at X as text at SHORT (X kept)
fmt83:
        lx l3
        yset SHORT
        ldi r1, 8
f83_base:
        ldx r0
        cmpi r0, ' '
        jz f83_base_end
        sty r0
        dec r1
        jnz f83_base
f83_base_end:
        xl l3
        xaddi 8
        ld r0, [x+0]
        cmpi r0, ' '
        jz f83_end
        ldi r0, '.'
        sty r0
        ldi r1, 3
f83_ext:
        ldx r0
        cmpi r0, ' '
        jz f83_end
        sty r0
        dec r1
        jnz f83_ext
f83_end:
        ldi r0, 0
        sty r0
        xl l3
        ret

; visible: C set if the entry at X may be seen (SYSTEM needs the hypervisor or
; system access)
visible:
        ld r0, [x+11]
        andi r0, $04
        jz vis_yes
        hyp
        jc vis_yes
        lx l3
        xset G_SYS
        ld r0, [x+0]
        xl l3
        cmpi r0, 0
        jnz vis_yes
        cmp r0, r0                      ; C = 0
        ret
vis_yes:
        ldi r0, 1
        cmpi r0, 2                      ; C = 1
        ret

; dir_search: the entry named NAME in directory L0 -> R0 = 1 found (ENT, G_DLBA,
; G_DOFF set; L3 = its first cluster, R10 its attributes), else R0 = 0
dir_search:
        call dw_start
        ldi r7, 0                       ; no long name yet
ds_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz ds_notfound
        cmpi r0, $E5
        jz ds_skip
        ld r1, [x+11]
        cmpi r1, $0F
        jz ds_lfn
        mov r2, r1
        andi r2, $08
        jnz ds_skip                     ; the volume label
        call visible
        jnc ds_skip
        cmpi r7, 0
        jz ds_short
        lfnsum r0
        cmp r0, r6
        jnz ds_short
        lx l3
        xset LFN
        yset NAME
        scmp
        xl l3
        jz ds_found
ds_short:
        call fmt83
        lx l3
        xset SHORT
        yset NAME
        scmp
        xl l3
        jz ds_found
ds_skip:
        ldi r7, 0
ds_next:
        call dw_next
        jz ds_notfound
        jmp ds_entry
ds_lfn:
        ld r0, [x+0]
        andi r0, $40
        jz ds_lfn_part
        lx l3                           ; the last part comes first: start again
        ldi r0, 0
        yset LFN
        ldi r1, 0
        fill r1
        xl l3
ds_lfn_part:
        ld r6, [x+13]
        yset LFN
        lfnput
        ldi r7, 1
        jmp ds_next
ds_found:
        lx l3                           ; keep the entry and where it is
        yset ENT
        ldi r1, 32
        copy r1
        xl l3
        call clus2lba
        lx l1
        landi l1, $1FF
        xset G_DLBA
        lst l2, [x+0]
        lst l1, [x+4]
        xset ENT
        ld r10, [x+11]
        lldw l3, [x+20]
        lshl l3, 16
        lldw l1, [x+26]
        lor l3, l1
        ldi r0, 1
        ret
ds_notfound:
        ldi r0, 0
        ret

; ---- paths ---------------------------------------------------------------------
; resolve: the path at REQ+R_DATA -> R10 attributes, L3 first cluster (a
; directory: 0 = root), R5 the drive (its registers loaded).  ENT holds the
; entry (none for the root: R9 = 0, else 1).
resolve:
        xset REQ+R_DATA
        ldi r5, 0
        ld r0, [x+1]                    ; "n:"?
        cmpi r0, ':'
        jnz rv_nodrive
        ld r0, [x+0]
        subi r0, '0'
        mov r5, r0
        xaddi 2
rv_nodrive:
        lx l1
        xset G_PATHP
        lstw l1, [x+0]
        call usedrive
        ldi r9, 0
        ldi r10, $10
        xset G_PATHP
        lldw l1, [x+0]
        xl l1
        ld r0, [x+0]
        cmpi r0, '/'
        jnz rv_relative
        xaddi 1
        lldi l3, 0
        jmp rv_loop_save
rv_relative:
        lx l1                           ; L3 = this drive's current directory
        btol l2, r5
        laddi l2, -1
        lshl l2, 2
        laddi l2, CWD
        xl l2
        lld l3, [x+0]
        xl l1
rv_loop_save:
        lx l1
        xset G_PATHP
        lstw l1, [x+0]
rv_loop:
        ; the next component into NAME
        xset G_PATHP
        lldw l1, [x+0]
        xl l1
        ld r0, [x+0]
        cmpi r0, 0
        jz rv_done
        yset NAME
        ldi r1, 0
rv_copy:
        ldx r0
        cmpi r0, 0
        jz rv_copied0
        cmpi r0, '/'
        jz rv_copied
        sty r0
        inc r1
        jz rv_long
        jmp rv_copy
rv_copied0:
        xaddi -1                        ; (stay on the terminator)
rv_copied:
        ldi r0, 0
        sty r0
        lx l1
        xset G_PATHP
        lstw l1, [x+0]
        cmpi r1, 0                      ; "//"
        jz rv_loop
        mov r0, r10
        andi r0, $10
        jz rv_notdir
        xset NAME                       ; "."
        ld r0, [x+0]
        cmpi r0, '.'
        jnz rv_search
        ld r0, [x+1]
        cmpi r0, 0
        jz rv_loop
        cmpi r0, '.'                    ; ".." at the root stays there
        jnz rv_search
        ld r0, [x+2]
        cmpi r0, 0
        jnz rv_search
        lz l3
        jz rv_loop
        lcmp l3, l4
        jz rv_root
rv_search:
        lmov l0, l3
        call dir_search
        cmpi r0, 0
        jz rv_noent
        ldi r9, 1
        jmp rv_loop
rv_root:
        lldi l3, 0
        ldi r9, 0
        jmp rv_loop
rv_done:
        lcmp l3, l4                     ; the root as 0
        jnz rv_ret
        lldi l3, 0
rv_ret:
        ret
rv_noent:
        ldi r12, E_NOENT
        jmp error
rv_notdir:
        ldi r12, E_NOTDIR
        jmp error
rv_long:
        ldi r12, E_LONG
        jmp error

; ---- descriptors -----------------------------------------------------------------
; fdptr: X = descriptor R2
fdptr:
        btol l1, r2
        lmov l2, l1
        lshl l1, 5
        lshl l2, 4
        ladd l1, l2
        laddi l1, FD
        xl l1
        ret

; fdalloc: R2 = a free descriptor (the one asked for if R_FLAGS bit 7)
fdalloc:
        xset REQ
        ld r0, [x+R_FLAGS]
        andi r0, $80
        jz fa_scan
        ld r2, [x+R_FD]
        cmpi r2, 8
        jnc fa_bad
        cmpi r2, 2
        jnc fa_check
        hyp                             ; 0 and 1: the hypervisor's
        jnc fa_access
fa_check:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jnz fa_full
        ret
fa_scan:
        ldi r2, 2
fa_next:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jz fa_ret
        inc r2
        cmpi r2, 8
        jnz fa_next
fa_full:
        ldi r12, E_NFILE
        jmp error
fa_bad:
        ldi r12, E_BADFD
        jmp error
fa_access:
        ldi r12, E_ACCESS
        jmp error
fa_ret:
        ret

; fdget: R2 = R0 (the descriptor), must be open -> X, R5 its drive (loaded)
fdget:
        mov r2, r0
        cmpi r2, 8
        jnc fa_bad
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jz fa_bad
        lx l1
        ld r5, [x+F_DRIVE]
        call usedrive
        call fdptr
        ret

; fdnew: fill descriptor R2 (X) for the object resolve found: R0 = flags
fdnew:
        st r0, [x+F_FLAGS]
        st r5, [x+F_DRIVE]
        st r10, [x+F_ATTR]
        lst l3, [x+F_FIRST]
        lst l3, [x+F_CUR]
        lldi l1, 0
        lst l1, [x+F_CIDX]
        lst l1, [x+F_POS]
        lx l0
        xset ENT
        lld l1, [x+28]
        xl l0
        lst l1, [x+F_SIZE]
        lx l0
        xset G_DLBA
        lld l1, [x+0]
        lld l2, [x+4]
        xl l0
        lst l1, [x+F_DLBA]
        lstw l2, [x+F_DOFF]
        ret

; ==============================================================================
; opendir(path) -> R_FD
op_opendir:
        call resolve
        mov r0, r10
        andi r0, $10
        jz od_notdir
        call fdalloc
        ldi r0, 3                       ; open, directory
        call fdnew
        xset REQ
        st r2, [x+R_FD]
        jmp ok
od_notdir:
        ldi r12, E_NOTDIR
        jmp error

; readdir(fd): the next entry -> R_DATA: attributes, 3 x 0, size, first
; cluster, time, date, the 8.3 name (13), the long name (at R_DATA+32)
op_readdir:
        xset REQ
        ld r0, [x+R_FD]
        call fdget
        ld r0, [x+F_FLAGS]
        andi r0, 2
        jz rd_notdir
        call fdptr                      ; L0 = the walk's cluster, R3/R4 position
        lld l0, [x+F_CUR]
        ld r3, [x+F_CIDX]
        ld r4, [x+F_CIDX+1]
        ld r0, [x+F_CIDX+2]             ; started?
        cmpi r0, 0
        jnz rd_resume
        call dw_start
        ldi r7, 0
        jmp rd_entry
rd_resume:
        lz l0
        jnz rd_load
        jmp rd_end                      ; the chain ended last time
rd_load:
        call dw_load
        ldi r7, 0
        call dw_next                    ; (past the entry returned last time)
        jz rd_end_mark
rd_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz rd_end_mark
        cmpi r0, $E5
        jz rd_skip
        ld r1, [x+11]
        cmpi r1, $0F
        jz rd_lfn
        mov r2, r1
        andi r2, $08
        jnz rd_skip
        call visible
        jnc rd_skip
        ; found: the response
        lx l3
        xset REQ
        ld r2, [x+R_FD]
        xl l3
        call rd_save
        call entry_out
        cmpi r7, 0
        jz rd_short_only
        lfnsum r0
        cmp r0, r6
        jnz rd_short_only
        xset LFN
        yset REQ+R_DATA+32
        ldi r1, 0
        copy r1
        jmp ok
rd_short_only:
        xset SHORT
        yset REQ+R_DATA+32
        ldi r1, 16
        copy r1
        jmp ok
rd_skip:
        ldi r7, 0
rd_next:
        call dw_next
        jz rd_end_mark
        jmp rd_entry
rd_lfn:
        ld r0, [x+0]
        andi r0, $40
        jz rd_lfn_part
        lx l3
        ldi r0, 0
        yset LFN
        ldi r1, 0
        fill r1
        xl l3
rd_lfn_part:
        ld r6, [x+13]
        yset LFN
        lfnput
        ldi r7, 1
        jmp rd_next
rd_end_mark:
        lldi l0, 0                      ; ended: remember that
        xset REQ
        ld r2, [x+R_FD]
        call fdptr
        lst l0, [x+F_CUR]
        ldi r0, 1
        st r0, [x+F_CIDX+2]
rd_end:
        ldi r12, E_END
        jmp error
rd_notdir:
        ldi r12, E_NOTDIR
        jmp error
; rd_save: the walk position into descriptor R2 (X kept)
rd_save:
        lx l3
        call fdptr
        lst l0, [x+F_CUR]
        st r3, [x+F_CIDX]
        st r4, [x+F_CIDX+1]
        ldi r0, 1
        st r0, [x+F_CIDX+2]
        xl l3
        ret

; entry_out: the entry at X into the response (and its 8.3 name at SHORT)
entry_out:
        call fmt83
        lx l3
        yset REQ+R_DATA
        ld r0, [x+11]
        sty r0
        ldi r0, 0
        sty r0
        sty r0
        sty r0
        lld l1, [x+28]
        lst l1, [y+0]
        lldw l1, [x+20]
        lshl l1, 16
        lldw l2, [x+26]
        lor l1, l2
        lst l1, [y+4]
        lld l1, [x+22]                  ; time, date
        lst l1, [y+8]
        xset SHORT
        yset REQ+R_DATA+16
        ldi r1, 13
        copy r1
        xl l3
        ret

; chdir(path)
op_chdir:
        call resolve
        mov r0, r10
        andi r0, $10
        jz od_notdir
        btol l2, r5
        laddi l2, -1
        lshl l2, 2
        laddi l2, CWD
        xl l2
        lst l3, [x+0]
        jmp ok

; getcwd(R_ARG0 = drive, 0 the current) -> the path at R_DATA.  Walks up
; through "..", naming each directory by finding its cluster in its parent;
; the path is built backwards from the end of the buffer.
op_getcwd:
        xset REQ
        ld r5, [x+R_ARG0]
        call usedrive
        btol l2, r5
        laddi l2, -1
        lshl l2, 2
        laddi l2, CWD
        xl l2
        lld l3, [x+0]
        lldi l1, $FFF
        xl l1
        ldi r0, 0
        st r0, [x+0]
        xset G_OUT
        lstw l1, [x+0]
gc_up:
        lz l3
        jz gc_done
        xset G_CHILD
        lst l3, [x+0]
        xset NAME                       ; the parent: ".."
        ldi r0, '.'
        st r0, [x+0]
        st r0, [x+1]
        ldi r0, 0
        st r0, [x+2]
        lmov l0, l3
        call dir_search
        cmpi r0, 0
        jz io_error                     ; (a directory without "..")
        xset G_PARENT
        lst l3, [x+0]
        lmov l0, l3
        call dir_findcl
        cmpi r0, 0
        jz io_error
        ; prepend "/" and the name at L3
        xl l3
        ldi r1, 0
gc_len:
        ldx r0
        jz gc_have_len
        inc r1
        jmp gc_len
gc_have_len:
        xset G_OUT
        lldw l1, [x+0]
        btol l2, r1
        lsub l1, l2
        lsubi l1, 1
        lcmpi l1, $F00
        jc gc_long
        lstw l1, [x+0]
        yl l1
        ldi r0, '/'
        sty r0
        xl l3
        cmpi r1, 0
        jz gc_named
        copy r1
gc_named:
        xset G_PARENT
        lld l3, [x+0]
        lz l3
        jz gc_done
        lcmp l3, l4
        jnz gc_up
gc_done:
        xset G_OUT
        lldw l1, [x+0]
        lcmpi l1, $FFF
        jnz gc_out
        laddi l1, -1                    ; the root: "/"
        xl l1
        ldi r0, '/'
        st r0, [x+0]
gc_out:
        xl l1
        lldi l2, $1000
        lsub l2, l1
        ltob r1, l2, 0
        yset REQ+R_DATA
        copy r1
        jmp ok
gc_long:
        ldi r12, E_LONG
        jmp error

; dir_findcl: the name of the entry in directory L0 whose first cluster is
; G_CHILD -> R0 = 1 and L3 = the name (LFN or SHORT), else R0 = 0
dir_findcl:
        call dw_start
        ldi r7, 0
fc_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz ds_notfound
        cmpi r0, $E5
        jz fc_skip
        ld r1, [x+11]
        cmpi r1, $0F
        jz fc_lfn
        andi r1, $08
        jnz fc_skip
        lldw l1, [x+20]
        lshl l1, 16
        lldw l2, [x+26]
        lor l1, l2
        lx l3
        xset G_CHILD
        lld l2, [x+0]
        xl l3
        lcmp l1, l2
        jnz fc_skip
        cmpi r7, 0
        jz fc_short
        lfnsum r0
        cmp r0, r6
        jnz fc_short
        lldi l3, LFN
        ldi r0, 1
        ret
fc_short:
        call fmt83
        lldi l3, SHORT
        ldi r0, 1
        ret
fc_skip:
        ldi r7, 0
fc_next:
        call dw_next
        jz ds_notfound
        jmp fc_entry
fc_lfn:
        ld r0, [x+0]
        andi r0, $40
        jz fc_lfn_part
        lx l3
        ldi r0, 0
        yset LFN
        ldi r1, 0
        fill r1
        xl l3
fc_lfn_part:
        ld r6, [x+13]
        yset LFN
        lfnput
        ldi r7, 1
        jmp fc_next

; stat(path) -> R_DATA as readdir
op_stat:
        call resolve
        cmpi r9, 0
        jz st_root
        xset ENT
        call entry_out
        xset SHORT
        yset REQ+R_DATA+32
        ldi r1, 16
        copy r1
        jmp ok
st_root:
        ldi r0, 0
        yset REQ+R_DATA
        ldi r1, 48
        fill r1
        ldi r0, $10
        xset REQ+R_DATA
        st r0, [x+0]
        ldi r0, '/'
        st r0, [x+16]
        st r0, [x+32]
        jmp ok

; open(path; R_FLAGS bit 0 write, bit 1 append, bit 7 the descriptor in R_FD)
op_open:
        xset REQ
        ld r0, [x+R_FLAGS]
        andi r0, 3
        jnz op_rofs                     ; (phase 1: read only)
        call resolve
        cmpi r9, 0
        jz op_isdir
        mov r0, r10
        andi r0, $10
        jnz op_isdir
        call fdalloc
        ldi r0, 1
        call fdnew
        xset REQ
        st r2, [x+R_FD]
        jmp ok
op_isdir:
        ldi r12, E_ISDIR
        jmp error
op_rofs:
        ldi r12, E_ROFS
        jmp error

; close(fd)
op_close:
        xset REQ
        ld r0, [x+R_FD]
        mov r2, r0
        cmpi r2, 8
        jnc fa_bad
        call fdptr
        ldi r0, 0
        st r0, [x+F_FLAGS]
        jmp ok

; seek(fd, R_ARG0 offset, R_FLAGS 0 from the start, 1 the position, 2 the end)
op_seek:
        xset REQ
        ld r0, [x+R_FD]
        call fdget
        lx l0
        xset REQ
        lld l1, [x+R_ARG0]
        ld r1, [x+R_FLAGS]
        xl l0
        cmpi r1, 1
        jz sk_cur
        cmpi r1, 2
        jz sk_end
        jmp sk_set
sk_cur:
        lld l2, [x+F_POS]
        ladd l1, l2
        jmp sk_set
sk_end:
        lld l2, [x+F_SIZE]
        ladd l1, l2
sk_set:
        lst l1, [x+F_POS]
        lx l0
        xset REQ
        lst l1, [x+R_ARG0]
        xl l0
        jmp ok

; ==============================================================================
; locate: the file of descriptor R2 (X) at position L1 -> L2 its sector (LBA),
; R1 the offset in it; C set past the end of the file.  Follows the chain from
; the cluster kept in the descriptor (or from the start).
locate:
        lld l2, [x+F_SIZE]
        lcmp l1, l2
        jnc lc_past
        lmov l3, l1                     ; L3 = cluster index
        lshr l3, 9
        lshrr l3, r13
        lld l0, [x+F_CIDX]
        lcmp l3, l0
        jnc lc_from_cur
        lld l0, [x+F_FIRST]             ; behind: from the start
        lldi l2, 0
        jmp lc_walk
lc_from_cur:
        lmov l2, l0
        lld l0, [x+F_CUR]
lc_walk:
        lcmp l2, l3
        jz lc_here
        fatnx l0
        jz lc_past                      ; (the chain is shorter than the size)
        laddi l2, 1
        jmp lc_walk
lc_here:
        lst l0, [x+F_CUR]
        lst l3, [x+F_CIDX]
        lmov l2, l1                     ; sector in the cluster, offset
        lshr l2, 9
        ltob r3, l2, 0
        mov r0, r11
        dec r0
        and r3, r0
        ltob r1, l1, 0                  ; (offset: low 9 bits; R1 = low 8, R9 bit 8)
        ltob r9, l1, 1
        andi r9, 1
        call clus2lba
        ldi r0, 1
        cmpi r0, 0                      ; C = 0
        ret
lc_past:
        ldi r0, 0
        cmpi r0, 1                      ; C = 1
        ret

; $71 read(fd = $D684, n = $D681-$D682 <= 512) -> the bytes at $E00, the count
; in $D681-$D682 (0 at the end of the file)
cmd_read:
        arg l0
        ltob r0, l0, 3
        lshl l0, 16                     ; n (16 bits)
        lshr l0, 16
        lmov l3, l0
        xset G_PATHP                    ; (keep n)
        lst l3, [x+0]
        call fdget
        ld r0, [x+F_FLAGS]
        andi r0, 2
        jnz rdc_bad
        xset G_PATHP
        lld l3, [x+0]
        lldi l0, 512
        lcmp l3, l0
        jnc rdc_bad2
rdc_ok_n:
        call fdptr
        lld l1, [x+F_POS]               ; at most size - position
        lld l2, [x+F_SIZE]
        lcmp l1, l2
        jnc rdc_zero
        lsub l2, l1
        lcmp l2, l3
        jnc rdc_n
        lmov l3, l2
rdc_n:
        xset G_DLBA                     ; L3 = the count: keep it
        lst l3, [x+0]
        lldi l0, 0
        lst l0, [x+4]                   ; bytes done
rdc_loop:
        xset G_DLBA
        lld l3, [x+0]
        lld l0, [x+4]
        lcmp l0, l3
        jz rdc_done
        call fdptr
        lld l1, [x+F_POS]
        call locate
        jc rdc_done
        sread l2
        je io_error
        ; chunk = min(512 - offset, count - done)
        lldi l0, 512
        btol l1, r1
        btol l2, r9
        lshl l2, 8
        lor l1, l2                      ; L1 = offset
        lsub l0, l1
        xset G_DLBA
        lld l3, [x+0]
        lld l2, [x+4]
        lsub l3, l2
        lcmp l3, l0
        jnc rdc_chunk
        lmov l0, l3
rdc_chunk:
        ; copy L0 bytes from SEC + L1 to REQ + done
        lmov l3, l1
        laddi l3, SEC
        xl l3
        laddi l2, REQ
        yl l2
        lmov l3, l0
rdc_copy:
        lz l3                           ; (copy: at most 256 a time)
        jz rdc_copied
        ltob r1, l3, 1
        cmpi r1, 0
        jz rdc_copy_last
        ldi r1, 0
        copy r1
        lsubi l3, 256
        jmp rdc_copy
rdc_copy_last:
        ltob r1, l3, 0
        copy r1
rdc_copied:
        xset G_DLBA                     ; done += chunk; position += chunk
        lld l2, [x+4]
        ladd l2, l0
        lst l2, [x+4]
        call fdptr
        lld l1, [x+F_POS]
        ladd l1, l0
        lst l1, [x+F_POS]
        jmp rdc_loop
rdc_done:
        xset G_DLBA
        lld l0, [x+4]
        setarg l0
        done
rdc_zero:
        lldi l0, 0
        setarg l0
        done
rdc_bad:
        fail E_ISDIR
rdc_bad2:
        jz rdc_ok_n                     ; (exactly 512 is fine)
        fail E_BADREQ

; $74 read exactly 512 bytes at file sector k ($D681-$D683) of fd ($D684)
cmd_readsector:
        arg l0
        ltob r0, l0, 3
        lshl l0, 8                      ; k (24 bits)
        lshr l0, 8
        lmov l3, l0
        xset G_PATHP
        lst l3, [x+0]
        call fdget
        xset G_PATHP
        lld l3, [x+0]
        call fdptr                      ; (L1, L2 scratch)
        lmov l1, l3
        lshl l1, 9                      ; the position
        lmov l3, l1                     ; the whole sector must be in the file
        laddi l3, 511
        lld l2, [x+F_SIZE]
        lcmp l3, l2
        jnc rsec_past
        call locate
        jc rsec_past
        dread l2
        je rsec_io
        done
rsec_past:
        fail E_END
rsec_io:
        fail E_IO
