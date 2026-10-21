; Hardware FAT32 engine firmware (MEGA65/mega65-core#766).
; Assembled and simulated by src/tools/fat32sim.py (the ROM: fat32_rom.vhdl);
; design in docs/sdcard-native/fat32-engine.md.
;
; Register conventions (kept across subroutines unless noted):
;   R5  drive in use (1..8)       R11 sectors per cluster  R13 log2 of it
;   R14 number of FATs            L4  root cluster          L5  FAT size
;   L6  FAT LBA (absolute)        L7  LBA of cluster 2 (absolute)
;   directory walk: L0 cluster, R3 sector in cluster, R4 entry in sector,
;   X the entry (in the engine sector)
;   R12 the error code (error)    R0-R2, R6-R10, L1-L3 are scratch
;   R15 scratch of the small helpers (drvaddr, fdptr)

; ---- memory ($000-$7FF of the sector buffer; the freezer saves it) --------------
.equ DRV,      $000      ; 8 drives x 48
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
.equ D_SERIAL, 32        ; the volume serial number (thaw checks it)
.equ D_FSINFO, 36        ; the FSInfo sector (absolute; 0 = none)
.equ D_FREE,   40        ; free clusters ($FFFFFFFF = unknown)
.equ D_HINT,   44        ; where to look for a free cluster
.equ FD,       $180      ; 10 descriptors x 32: H0, H1 (hypervisor), user 0-7
.equ F_FLAGS,  0         ; bit 0 open, 1 directory, 2 write, 3 append, 7 stale
.equ F_DRIVE,  1
.equ F_ATTR,   2
.equ F_FIRST,  4
.equ F_CUR,    8         ; a cluster of the file (files) / the directory walk (dirs)
.equ F_CIDX,   12        ; files: index of F_CUR in the chain; dirs: sector, entry
.equ F_POS,    16
.equ F_SIZE,   20
.equ F_DLBA,   24        ; the directory entry: sector (absolute)
.equ F_DOFF,   28        ;   and offset in it
.equ CWD,      $2C0      ; 8 x 4: the current directory's cluster (0 = root)
.equ G_DRIVE,  $2E0      ; the current drive
.equ G_NDRV,   $2E1      ; drives found
.equ G_SYS,    $2E2      ; SYSTEM entries visible to programs
.equ G_RO,     $2E3      ; programs may not modify the file system
.equ G_PATHP,  $2E4      ; (2) the path being resolved
.equ G_DLBA,   $2E8      ; (4) the last entry found: sector
.equ G_DOFF,   $2EC      ; (4)   and offset
.equ G_CHILD,  $2F0      ; (4) getcwd: the directory being named
.equ G_PARENT, $2F4      ; (4)   its parent
.equ G_OUT,    $2F8      ; (2)   where the path starts (built backwards)
.equ ENT,      $320      ; (32) a copy of the last entry found
.equ SHORT,    $340      ; 16: an 8.3 name as text
.equ NAME,     $380      ; 256: the path component (UTF-8)
.equ LFN,      $480      ; 256: the long filename being assembled (UTF-8)
.equ UCS,      $580      ; 520: a long filename's UCS-2 characters, as stored
.equ PTBL,     $580      ; 64: the partition table being scanned (rescan only)
.equ G_WPOS,   $788      ; (4) write: the position
.equ G_WN,     $78C      ; (4)   the count
.equ G_WDONE,  $790      ; (4)   bytes done
.equ G_PREV,   $794      ; (4) alloc: the cluster to link from
.equ G_PREVC,  $798      ; (4) locate_w: the cluster before
.equ G_IDX,    $79C      ; (4)   the index reached
.equ G_TGT,    $7A0      ; (4)   the index wanted
.equ G_FSTART, $7A4      ; (4) find_free: where the search started
.equ G_RUN,    $7A8      ; (7) a directory entry's run: cluster, sector, entry, count
.equ G_PARDIR, $7B0      ; (4) the parent directory (create, mkdir, rename)
.equ G_TIME,   $7B4      ; (4) the time stamp: FAT time, date (0: 2026-01-01)
.equ G_NEWCL,  $7B8      ; (4) mkdir: the new directory's cluster
.equ G_FSDIRTY, $7BC     ; FSInfo needs writing
.equ G_ALLVIS, $7BD      ; every entry is visible (existence checks)
.equ G_BASELEN, $7BE     ; alias: the length of the base
.equ G_CUTC,   $7BF      ; resolve_parent: the character cut, where (2), the
                         ;   name's length (G_CUTC+3)
.equ G_PBASE,  $7F4      ; (2) the path resolve reads
.equ G_ONERR,  $7F6      ; a descriptor whose entry an error must still write
.equ G_ERR,    $7F7      ;   (the error meanwhile)
.equ G_MAGIC,  $7FE      ; (2) "F3": the area is initialised (else: cleared first)
.equ G_SAVRUN, $7C4      ; (8) rename: the old entry's run
.equ G_SAVENT, $7CC      ; (32) rename: the old entry; truncate: the length
.equ G_DIRCL,  $7EC      ; (4) rename: the directory's cluster
.equ G_LEN,    $7F0      ; (4) truncate: the new length
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
.equ E_EXIST,  12
.equ E_NOTEMPTY, 13
.equ E_NOSPC,  14
.equ E_ROFS,   15
.equ E_STALE,  16
.equ E_BUSY,   17
.equ E_FRAG,   18

; ==============================================================================
start:
        xset G_MAGIC                    ; cold: the whole area cleared (no
        ld r0, [x+0]                    ; drives, no descriptors, defaults)
        cmpi r0, 'F'
        jnz cold
        ld r0, [x+1]
        cmpi r0, '3'
        jz warm
cold:
        ldi r0, 0
        yset $000
        ldi r1, 0
        fill r1
        fill r1
        fill r1
        fill r1
        fill r1
        fill r1
        fill r1
        fill r1
        xset G_MAGIC
        ldi r0, 'F'
        st r0, [x+0]
        ldi r0, '3'
        st r0, [x+1]
warm:
        xset G_ONERR
        ldi r0, $FF
        st r0, [x+0]
        xset G_ALLVIS                   ; (an error may have left it set)
        ldi r0, 0
        st r0, [x+0]
        cmd r0
        cmpi r0, $70
        jz request
        cmpi r0, $71
        jz cmd_read
        cmpi r0, $72
        jz cmd_write
        cmpi r0, $73
        jz cmd_append
        cmpi r0, $74
        jz cmd_readsector
        cmpi r0, $75
        jz cmd_writesector
        cmpi r0, $76
        jz cmd_qread
        cmpi r0, $77
        jz cmd_qread
        cmpi r0, $78
        jz cmd_qwrite
        cmpi r0, $79
        jz cmd_qwrite
        fail E_BADREQ

; ---- $70: a request block ----------------------------------------------------
request:
        lldi l0, REQ+R_DATA
        xset G_PBASE
        lstw l0, [x+0]
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
        cmpi r0, 4
        jz op_policy
        cmpi r0, 5
        jz op_sysaccess
        cmpi r0, 6
        jz op_settime
        cmpi r0, 7
        jz op_thaw
        cmpi r0, 8
        jz op_mount
        cmpi r0, $14
        jz op_mkdir
        cmpi r0, $15
        jz op_rmdir
        cmpi r0, $21
        jz op_create
        cmpi r0, $25
        jz op_delete
        cmpi r0, $26
        jz op_rename
        cmpi r0, $27
        jz op_setattr
        cmpi r0, $28
        jz op_truncate
        cmpi r0, $29
        jz op_flush
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
        xset G_ONERR                    ; a file grown part way: its entry
        ld r2, [x+0]
        cmpi r2, $FF
        jz error_resp
        ldi r0, $FF
        st r0, [x+0]
        xset G_ERR
        st r12, [x+0]
        call dirent_update
        call fsinfo_sync
        xset G_ERR
        ld r12, [x+0]
error_resp:
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
        call rescan
        xset REQ
        btol l0, r5
        lst l0, [x+R_ARG0]
        jmp ok

; rescan: the drive table built again (current directories: the roots) -> R5
; the drives found
rescan:
        ldi r0, 0
        yset DRV
        ldi r1, 0
        fill r1                         ; the drive table (384 bytes)
        ldi r1, 128
        fill r1
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
        ; the drive's record
        mov r0, r5
        call drvaddr
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
        lld l0, [x+67]
        lst l0, [y+D_SERIAL]
        lldw l0, [x+48]                 ; FSInfo: read below
        lst l0, [y+D_FSINFO]
        lld l0, [x+32]                  ; clusters: (total - (data - part)) >> spcl + 2
        lsub l2, l1
        lsub l0, l2
        lshrr l0, r7
        laddi l0, 2
        lst l0, [y+D_NCL]
        ; FSInfo: the free count and the hint, if its signatures are right
        lldi l0, 0
        lsubi l0, 1
        lst l0, [y+D_FREE]
        lldi l0, 2
        lst l0, [y+D_HINT]
        lld l0, [y+D_FSINFO]
        lz l0
        jz rs_counted
        ladd l0, l1
        lst l0, [y+D_FSINFO]
        sread l0
        je rs_nofsinfo
        xset SEC                        ; "RRaA" ... "rrAa"
        ld r0, [x+0]
        cmpi r0, 'R'
        jnz rs_nofsinfo
        ld r0, [x+1]
        cmpi r0, 'R'
        jnz rs_nofsinfo
        ld r0, [x+2]
        cmpi r0, 'a'
        jnz rs_nofsinfo
        ld r0, [x+3]
        cmpi r0, 'A'
        jnz rs_nofsinfo
        xset SEC+484
        ld r0, [x+0]
        cmpi r0, 'r'
        jnz rs_nofsinfo
        ld r0, [x+1]
        cmpi r0, 'r'
        jnz rs_nofsinfo
        ld r0, [x+2]
        cmpi r0, 'A'
        jnz rs_nofsinfo
        ld r0, [x+3]
        cmpi r0, 'a'
        jnz rs_nofsinfo
        lld l0, [x+4]
        lst l0, [y+D_FREE]
        lld l0, [x+8]
        lcmpi l0, 2
        jc rs_counted
        lst l0, [y+D_HINT]
        jmp rs_counted
rs_nofsinfo:
        lldi l0, 0
        lst l0, [y+D_FSINFO]
rs_counted:
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
        ret

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
        mov r0, r1
        call drvaddr
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
        mov r0, r5
        dec r0
        call drvaddr
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

; drvaddr: L2 = the record of drive R0 + 1 (R15 scratch)
drvaddr:
        mov r15, r0
        shl r15
        add r15, r0
        btol l2, r15
        lshl l2, 4
        laddi l2, DRV
        ret

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
        lx l3
        xset G_ALLVIS
        ld r0, [x+0]
        xl l3
        cmpi r0, 0
        jnz vis_yes
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

; lfn_part: the long-filename entry at X into UCS (the last part comes
; first: it starts the name again); R6 = its checksum, R7 = 1
lfn_part:
        ld r0, [x+0]
        andi r0, $40
        jz lp_part
        lx l3
        xset G_RUN                      ; where the run starts
        lst l0, [x+0]
        st r3, [x+4]
        st r4, [x+5]
        ldi r7, 0
        ldi r0, 0                       ; (520 bytes)
        yset UCS
        ldi r1, 0
        fill r1
        fill r1
        ldi r1, 8
        fill r1
        xl l3
lp_part:
        ld r6, [x+13]
        yset UCS
        lfnput
        inc r7
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
        xset UCS
        yset LFN
        utf8
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
        call lfn_part
        jmp ds_next
ds_found:
        lx l3                           ; the run: the long name's, or this entry
        cmpi r7, 0
        jz dsf_single
        lfnsum r0
        cmp r0, r6
        jnz dsf_single
        inc r7
        xset G_RUN+6
        st r7, [x+0]
        jmp dsf_copy
dsf_single:
        xset G_RUN
        lst l0, [x+0]
        st r3, [x+4]
        st r4, [x+5]
        ldi r0, 1
        st r0, [x+6]
dsf_copy:
        xl l3                           ; keep the entry and where it is
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
        xset G_PBASE
        lldw l1, [x+0]
        xl l1
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
; Two name spaces: the hypervisor's H0 and H1 (internal 0, 1: disk images) and
; the programs' 0-7 (internal 2-9).  In hypervisor mode a descriptor number
; with bit 7 set means the programs' one (the freezer, cleaning up).

; fdptr: X = descriptor R2 (internal); R15 scratch, nothing else
fdptr:
        mov r15, r2
        shl r15
        shl r15
        shl r15
        shl r15
        xset FD
        xadd r15
        xadd r15
        ret

; fdmap: R0 = a descriptor number -> R2 = internal (bad: error)
fdmap:
        hyp
        jnc fm_user
        mov r2, r0
        andi r2, $80
        jnz fm_hyp_user
        mov r2, r0
        cmpi r2, 2
        jnc fa_bad
        ret
fm_hyp_user:
        mov r2, r0
        andi r2, $7F
        jmp fm_check
fm_user:
        mov r2, r0
fm_check:
        cmpi r2, 8
        jnc fa_bad
        addi r2, 2
        ret

; fdnum: R0 = the number of internal descriptor R2 (for the caller)
fdnum:
        mov r0, r2
        cmpi r0, 2
        jc fn_ret
        subi r0, 2
        hyp
        jnc fn_ret
        ori r0, $80
fn_ret:
        ret

; fdalloc: R2 = a free descriptor: the one in R_FD if R_FLAGS bit 7, else the
; first free one of the caller's (in hypervisor mode, R_FD bit 7: the programs')
fdalloc:
        xset REQ
        ld r0, [x+R_FLAGS]
        andi r0, $80
        jz fa_scan
        ld r0, [x+R_FD]
        call fdmap
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jnz fa_full
        ret
fa_scan:
        ldi r2, 2                       ; programs: 2-9
        ldi r1, 10
        hyp
        jnc fa_next
        ld r0, [x+R_FD]
        andi r0, $80
        jnz fa_next
        ldi r2, 0                       ; the hypervisor: 0-1
        ldi r1, 2
fa_next:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jz fa_ret
        inc r2
        cmp r2, r1
        jnz fa_next
fa_full:
        ldi r12, E_NFILE
        jmp error
fa_bad:
        ldi r12, E_BADFD
        jmp error
fa_ret:
        ret

; fdget: R0 = a descriptor number, open -> R2, X, R5 its drive (loaded)
fdget:
        call fdmap
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jz fa_bad
        ld r0, [x+F_FLAGS]
        andi r0, $80
        jnz fd_stale
        ld r5, [x+F_DRIVE]
        call usedrive
        call fdptr
        ret
fd_stale:
        ldi r12, E_STALE
        jmp error

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
        call fdnum
        xset REQ
        st r0, [x+R_FD]
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
        ld r0, [x+R_FD]
        call fdmap
        xl l3
        call rd_save
        call entry_out
        cmpi r7, 0
        jz rd_short_only
        lfnsum r0
        cmp r0, r6
        jnz rd_short_only
        xset UCS
        yset REQ+R_DATA+32
        utf8
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
        call lfn_part
        jmp rd_next
rd_end_mark:
        lldi l0, 0                      ; ended: remember that
        xset REQ
        ld r0, [x+R_FD]
        call fdmap
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
        xset UCS
        yset LFN
        utf8
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
        call lfn_part
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
        jz op_open_r
        call need_rw
op_open_r:
        call resolve
        cmpi r9, 0
        jz op_isdir
        mov r0, r10
        andi r0, $10
        jnz op_isdir
        xset REQ                        ; write: not a read-only file
        ld r8, [x+R_FLAGS]
        andi r8, 3
        jz op_open_ok
        mov r0, r10
        andi r0, $01
        jnz op_access
        ldi r6, $0C                     ; one writer at a time (else one could
        call busy_mask                  ;   free clusters the other still uses)
op_open_ok:
        call fdalloc
        ldi r0, 1                       ; open; bit 0 write -> 2, bit 1 append -> 3
        shl r8
        shl r8
        or r0, r8
        call fdnew
        call fdnum
        xset REQ
        st r0, [x+R_FD]
        jmp ok
op_isdir:
        ldi r12, E_ISDIR
        jmp error
op_rofs:
        ldi r12, E_ROFS
        jmp error
op_access:
        ldi r12, E_ACCESS
        jmp error

; close(fd)
op_close:
        xset REQ
        ld r0, [x+R_FD]
        call fdmap
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, $91                    ; open and dirty: the entry first
        cmpi r0, $11                    ;   (not when stale: it may be another's)
        jnz cl_clean
        ld r5, [x+F_DRIVE]
        call usedrive
        call dirent_update
cl_clean:
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
cmd_read_l0:
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

; ==============================================================================
; WRITING
; Every modification is written before the command completes: data, both FATs,
; the directory entry, then FSInfo.  Descriptor flags: bit 2 write, bit 3
; append, bit 4 the directory entry needs updating (after $75).

; need_rw: programs may modify the file system? (else E_ROFS)
need_rw:
        hyp
        jc nr_ok
        xset G_RO
        ld r0, [x+0]
        cmpi r0, 0
        jnz nr_ro
nr_ok:
        ret
nr_ro:
        ldi r12, E_ROFS
        jmp error

; drec: X = the record of drive R5
drec:
        mov r0, r5
        dec r0
        call drvaddr
        xl l2
        ret

; ---- clusters ------------------------------------------------------------------
; find_free: L0 = a free cluster, from the drive's hint on (E_NOSPC: none); the
; hint and the free count move on
find_free:
        call drec
        lld l3, [x+D_NCL]
        lld l0, [x+D_HINT]
        lcmpi l0, 2
        jc ff_low
        lcmp l0, l3
        jc ff_start
ff_low:
        lldi l0, 2
ff_start:
        xset G_FSTART
        lst l0, [x+0]
ff_sector:
        lmov l1, l0                     ; the FAT sector, X at the entry
        lshr l1, 7
        ladd l1, l6
        sread l1
        je io_error
        ltob r0, l0, 0
        andi r0, $7F
        btol l1, r0
        lshl l1, 2
        laddi l1, SEC
        xl l1
ff_entry:
        lld l2, [x+0]
        lshl l2, 4                      ; (28 bits)
        jz ff_found
        laddi l0, 1
        xaddi 4
        ldi r1, 0
        lcmp l0, l3
        jnz ff_nowrap
        lldi l0, 2
        ldi r1, 1
ff_nowrap:
        lx l2
        xset G_FSTART
        lld l1, [x+0]
        xl l2
        lcmp l0, l1
        jz ff_full
        cmpi r1, 0
        jnz ff_sector
        ltob r0, l0, 0
        andi r0, $7F
        jz ff_sector
        jmp ff_entry
ff_found:
        call drec
        lmov l1, l0
        laddi l1, 1
        lst l1, [x+D_HINT]
        lld l1, [x+D_FREE]
        lmov l2, l1
        laddi l2, 1                     ; (unknown: $FFFFFFFF)
        jz ff_dirty
        lsubi l1, 1
        lst l1, [x+D_FREE]
ff_dirty:
        xset G_FSDIRTY
        ldi r0, 1
        st r0, [x+0]
        ret
ff_full:
        ldi r12, E_NOSPC
        jmp error

; alloc: L1 = the cluster to link from (0: none) -> L0 = a new cluster, the
; end of its chain
alloc:
        xset G_PREV
        lst l1, [x+0]
        call find_free
        lldi l2, 0                      ; end of chain
        lsubi l2, 1
        lshr l2, 4
        fatset l0, l2
        je io_error
        xset G_PREV
        lld l1, [x+0]
        lz l1
        jz al_ret
        fatset l1, l0
        je io_error
al_ret:
        ret

; free_chain: free the chain from L0 (< 2: nothing)
free_chain:
        lcmpi l0, 2
        jc fch_ret
        lmov l1, l0
        fatnx l0
        jz fch_last
        jc fch_last                     ; (a broken chain: stop there)
        call free_one
        jmp free_chain
fch_last:
        call free_one
fch_ret:
        ret
; free_one: free cluster L1
free_one:
        lldi l2, 0
        fatset l1, l2
        je io_error
        call drec
        lld l2, [x+D_FREE]
        lmov l3, l2
        laddi l3, 1
        jz fo_dirty
        laddi l2, 1
        lst l2, [x+D_FREE]
fo_dirty:
        xset G_FSDIRTY
        ldi r0, 1
        st r0, [x+0]
        ret

; fsinfo_sync: the free count and hint into FSInfo, if they changed
fsinfo_sync:
        xset G_FSDIRTY
        ld r0, [x+0]
        cmpi r0, 0
        jz fs_ret
        ldi r0, 0
        st r0, [x+0]
        call drec
        lld l0, [x+D_FSINFO]
        lz l0
        jz fs_ret
        lld l1, [x+D_FREE]
        lld l3, [x+D_HINT]
        sread l0
        je io_error
        xset SEC+488
        lst l1, [x+0]
        lst l3, [x+4]
        swrite l0
        je io_error
fs_ret:
        ret

; zero_sec: SEC = 0
zero_sec:
        ldi r0, 0
        yset SEC
        ldi r1, 0
        fill r1
        fill r1
        ret

; zero_cluster: cluster L0 = 0 (SEC is left 0)
zero_cluster:
        call zero_sec
        ldi r3, 0
zc_loop:
        call clus2lba
        swrite l2
        je io_error
        inc r3
        cmp r3, r11
        jnz zc_loop
        ret

; ---- directory entries -----------------------------------------------------------
; dw_flush: write back the directory walk's sector
dw_flush:
        call clus2lba
        swrite l2
        je io_error
        ret

; stamp: the time stamp into the entry at X: modified, accessed (R8 = 1: and
; created)
stamp:
        lx l3
        xset G_TIME
        lld l2, [x+0]
        xl l3
        lz l2
        jnz st_have
        lldi l2, $5C2                   ; 2026-01-01 00:00 ($5C21 << 16)
        lshl l2, 4
        laddi l2, 1
        lshl l2, 16
st_have:
        lstw l2, [x+22]                 ; modified
        cmpi r8, 1
        jnz st_noc
        lstw l2, [x+14]                 ; created
st_noc:
        lshr l2, 16
        lstw l2, [x+24]
        lstw l2, [x+18]                 ; accessed
        cmpi r8, 1
        jnz st_ret
        lstw l2, [x+16]
st_ret:
        ret

; dir_free_run: R8 free entries in a row in directory L0 (0: root) -> G_RUN;
; the directory grows (zeroed clusters) if it has to
dir_free_run:
        call dw_start
        ldi r9, 0
dfr_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz dfr_free
        cmpi r0, $E5
        jz dfr_free
        ldi r9, 0
        jmp dfr_next
dfr_free:
        cmpi r9, 0
        jnz dfr_more
        lx l1
        xset G_RUN
        lst l0, [x+0]
        st r3, [x+4]
        st r4, [x+5]
        xl l1
dfr_more:
        inc r9
        cmp r9, r8
        jz dfr_ret
dfr_next:
        lmov l3, l0
        call dw_next
        jnz dfr_entry
        lmov l1, l3                     ; the end: a new cluster
        call alloc
        call zero_cluster
        ldi r3, 0
        ldi r4, 0
        call dw_load
        jmp dfr_entry
dfr_ret:
        ret

; dir_write_run: R8 entries from G_RUN: R8 - 1 long-name entries (UCS, checksum
; R6), then ENT; G_DLBA/G_DOFF = where ENT went
dir_write_run:
        xset G_RUN
        lld l0, [x+0]
        ld r3, [x+4]
        ld r4, [x+5]
        call dw_load
        ldi r9, 0
dwr_entry:
        mov r0, r8
        dec r0
        cmp r9, r0
        jz dwr_short
        sub r0, r9                      ; sequence: R8 - 1 - i (+ $40 first)
        cmpi r9, 0
        jnz dwr_seq
        ori r0, $40
dwr_seq:
        mov r10, r0
        lx l1
        yl l1
        xset UCS
        lfnmake r10, r6
        xl l1
        inc r9
        cmpi r4, 15
        jnz dwr_nf
        call dw_flush
dwr_nf:
        call dw_next
        jmp dwr_entry
dwr_short:
        lx l1
        yl l1
        xset ENT
        ldi r1, 32
        copy r1
        xl l1
        call clus2lba
        lx l1
        landi l1, $1FF
        xset G_DLBA
        lst l2, [x+0]
        lst l1, [x+4]
        call dw_flush
        ret

; mark_run: the run in G_RUN deleted ($E5)
mark_run:
        xset G_RUN
        lld l0, [x+0]
        ld r3, [x+4]
        ld r4, [x+5]
        ld r8, [x+6]
        call dw_load
mr_loop:
        ldi r0, $E5
        st r0, [x+0]
        dec r8
        jz mr_end
        cmpi r4, 15
        jnz mr_nf
        call dw_flush
mr_nf:
        call dw_next
        jmp mr_loop
mr_end:
        call dw_flush
        ret

; dir_find11: R0 = 1 if directory L0 has an entry with the 8.3 name in ENT
dir_find11:
        call dw_start
df_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz df_no
        cmpi r0, $E5
        jz df_next
        ld r1, [x+11]
        cmpi r1, $0F
        jz df_next
        lx l1
        yset ENT
        ncmp 11
        xl l1
        jz df_yes
df_next:
        call dw_next
        jnz df_entry
df_no:
        ldi r0, 0
        ret
df_yes:
        ldi r0, 1
        ret

; ---- names -----------------------------------------------------------------------
; make_alias: the 8.3 name for NAME into ENT[0..10] -> R7 = 1 if a long name is
; needed, R8 = 1 if the 8.3 name is NAME's own (no ~n)
make_alias:
        ldi r0, ' '
        yset ENT
        ldi r1, 11
        fill r1
        xset NAME                       ; R1 = the length, R9 = after the last '.'
        ldi r1, 0
        ldi r9, 0
ma_dot:
        ldx r0
        jz ma_dot_done
        inc r1
        cmpi r0, '.'
        jnz ma_dot
        mov r9, r1
        jmp ma_dot
ma_dot_done:
        cmpi r9, 1                      ; (".name": no extension)
        jnz ma_d2
        ldi r9, 0
ma_d2:
        ldi r7, 0
        ldi r8, 1
        mov r2, r1                      ; the base ends at R2
        cmpi r9, 0
        jz ma_b0
        mov r2, r9
        dec r2
ma_b0:
        xset NAME
        yset ENT
        ldi r10, 0
        ldi r3, 0
ma_base:
        cmp r10, r2
        jz ma_base_end
        ldx r0
        inc r10
        call ma_char
        cmpi r0, 0
        jz ma_base
        cmpi r3, 8
        jz ma_blong
        sty r0
        inc r3
        jmp ma_base
ma_blong:
        ldi r8, 0
        ldi r7, 1
        jmp ma_base
ma_base_end:
        cmpi r3, 0
        jnz ma_base_ok
        ldi r0, '_'
        sty r0
        inc r3
        ldi r8, 0
        ldi r7, 1
ma_base_ok:
        xset G_BASELEN
        st r3, [x+0]
        cmpi r9, 0
        jz ma_ext_end
        xset NAME
        xadd r9
        yset ENT+8
        ldi r3, 0
        mov r10, r9
ma_ext:
        cmp r10, r1
        jz ma_ext_end
        ldx r0
        inc r10
        call ma_char
        cmpi r0, 0
        jz ma_ext
        cmpi r3, 3
        jz ma_elong
        sty r0
        inc r3
        jmp ma_ext
ma_elong:
        ldi r8, 0
        ldi r7, 1
        jmp ma_ext
ma_ext_end:
        cmpi r8, 0
        jnz ma_ret
        ldi r7, 1
ma_ret:
        ret

; ma_char: R0 as an 8.3 character (0: left out); R7/R8 updated
ma_char:
        cmpi r0, 'a'
        jc mc_upper
        cmpi r0, 'z'+1
        jnc mc_upper
        subi r0, 32                     ; lower case: kept in the long name
        ldi r7, 1
        ret
mc_upper:
        cmpi r0, 'A'
        jc mc_digit
        cmpi r0, 'Z'+1
        jc mc_ok
mc_digit:
        cmpi r0, '0'
        jc mc_special
        cmpi r0, '9'+1
        jc mc_ok
mc_special:
        cmpi r0, '$'
        jz mc_ok
        cmpi r0, '%'
        jz mc_ok
        cmpi r0, $27                    ; '
        jz mc_ok
        cmpi r0, '-'
        jz mc_ok
        cmpi r0, '_'
        jz mc_ok
        cmpi r0, '@'
        jz mc_ok
        cmpi r0, '~'
        jz mc_ok
        cmpi r0, '!'
        jz mc_ok
        cmpi r0, '#'
        jz mc_ok
        cmpi r0, '&'
        jz mc_ok
        cmpi r0, '('
        jz mc_ok
        cmpi r0, ')'
        jz mc_ok
        ldi r8, 0                       ; not 8.3
        ldi r7, 1
        cmpi r0, ' '
        jz mc_skip
        cmpi r0, '.'
        jz mc_skip
        mov r1, r0                      ; UTF-8: one '_' per character
        andi r1, $C0
        cmpi r1, $80
        jz mc_skip_r1
        ldi r0, '_'
        ret
mc_skip_r1:
        ldi r1, 0
mc_skip:
        ldi r0, 0
mc_ok:
        ret

; ma_unique: ENT's base gets "~n", the first n not in directory G_PARDIR
ma_unique:
        ldi r9, 1
mu_try:
        ; the base: at most 8 - (2 or 3) characters, then ~n
        xset G_BASELEN
        ld r2, [x+0]
        ldi r1, 6
        cmpi r9, 10
        jc mu_len
        ldi r1, 5
mu_len:
        cmp r2, r1
        jc mu_short
        mov r2, r1
mu_short:
        yset ENT
        yadd r2
        ldi r0, '~'
        sty r0
        cmpi r9, 10
        jc mu_units
        mov r0, r9                      ; tens
        ldi r1, '0'
mu_tens:
        cmpi r0, 10
        jc mu_tens_done
        subi r0, 10
        inc r1
        jmp mu_tens
mu_tens_done:
        sty r1
        addi r0, '0'
        sty r0
        jmp mu_pad
mu_units:
        mov r0, r9
        addi r0, '0'
        sty r0
mu_pad:
        ldi r0, ' '
mu_pad_loop:
        ly l1                           ; up to ENT+8
        lcmpi l1, ENT+8
        jnc mu_check
        sty r0
        jmp mu_pad_loop
mu_check:
        xset G_PARDIR
        lld l0, [x+0]
        call dir_find11
        cmpi r0, 0
        jz mu_ret
        inc r9
        cmpi r9, 100
        jnz mu_try
        ldi r12, E_EXIST
        jmp error
mu_ret:
        ret

; name_check: NAME may be created (else E_BADREQ): not "." or "..", none of
; " * / : < > ? \ | or control characters, not ending in ' ' or '.'
name_check:
        xset NAME
        ld r0, [x+0]
        cmpi r0, 0
        jz nc_bad
        ldi r2, 0                       ; the last character
nc_loop:
        ldx r0
        jz nc_end
        mov r2, r0
        cmpi r0, ' '
        jc nc_bad
        cmpi r0, '"'
        jz nc_bad
        cmpi r0, '*'
        jz nc_bad
        cmpi r0, '/'
        jz nc_bad
        cmpi r0, ':'
        jz nc_bad
        cmpi r0, '<'
        jz nc_bad
        cmpi r0, '>'
        jz nc_bad
        cmpi r0, '?'
        jz nc_bad
        cmpi r0, $5C                    ; backslash
        jz nc_bad
        cmpi r0, '|'
        jz nc_bad
        jmp nc_loop
nc_end:
        cmpi r2, ' '
        jz nc_bad
        cmpi r2, '.'
        jz nc_bad
        ret
nc_bad:
        ldi r12, E_BADREQ
        jmp error

; resolve_parent: the path at G_PBASE -> its directory (L3 cluster, also in
; G_PARDIR; R5 the drive) and its last component in NAME (checked)
resolve_parent:
        xset G_PBASE
        lldw l1, [x+0]
        xl l1
        ldi r1, 0                       ; R1 = the length, R2 = after the last '/'
        ldi r2, 0
rp_scan:
        ldx r0
        jz rp_end
        inc r1
        jz rp_long
        cmpi r0, '/'
        jnz rp_scan
        mov r2, r1
        jmp rp_scan
rp_end:
        cmpi r2, 0                      ; no '/': after "n:"
        jnz rp_have
        xl l1
        ld r0, [x+1]
        cmpi r0, ':'
        jnz rp_have
        ldi r2, 2
rp_have:
        cmp r2, r1
        jz nc_bad                       ; (no name)
        sub r1, r2                      ; R1 = the name's length
        xl l1                           ; the directory: cut the path after R2
        xadd r2
        lx l2
        ld r0, [x+0]
        xset G_CUTC
        st r0, [x+0]
        lstw l2, [x+1]
        st r1, [x+3]
        xl l2
        ldi r0, 0
        st r0, [x+0]
        call resolve                    ; (NAME is its scratch)
        xset G_CUTC                     ; the path again; the name into NAME
        ld r0, [x+0]
        ld r3, [x+3]
        lldw l2, [x+1]
        xl l2
        st r0, [x+0]
        yset NAME
        inc r3
        copy r3
        mov r0, r10
        andi r0, $10
        jz rv_notdir
        xset G_PARDIR
        lst l3, [x+0]
        call name_check
        ret
rp_long:
        ldi r12, E_LONG
        jmp error

; not_exists: NAME is not in directory G_PARDIR, hidden or not (else E_EXIST)
not_exists:
        xset G_ALLVIS
        ldi r0, 1
        st r0, [x+0]
        xset G_PARDIR
        lld l0, [x+0]
        call dir_search
        xset G_ALLVIS
        mov r1, r0
        ldi r0, 0
        st r0, [x+0]
        cmpi r1, 0
        jnz ne_exists
        ret
ne_exists:
        ldi r12, E_EXIST
        jmp error

; make_entry: NAME into directory G_PARDIR, ENT[11..31] as prepared: its
; 8.3 name, the long name if one is needed
make_entry:
        call make_alias
        cmpi r8, 0
        jnz me_alias_ok
        call ma_unique
        ldi r7, 1
me_alias_ok:
        ldi r8, 1                       ; entries
        cmpi r7, 0
        jz me_place
        xset NAME
        yset UCS
        ucs2
        jc nc_bad
        ldi r9, 0                       ; R9 = ceil(R0 / 13)
me_div:
        inc r9
        cmpi r0, 14
        jc me_div_done
        subi r0, 13
        jmp me_div
me_div_done:
        mov r8, r9
        inc r8
        xset ENT
        lfnsum r6
me_place:
        xset G_PARDIR
        lld l0, [x+0]
        call dir_free_run
        call dir_write_run
        ret

; ent_new: ENT[11..31] for a new entry: attributes R10, first cluster L0, size 0
ent_new:
        ldi r0, 0
        yset ENT+11
        ldi r1, 21
        fill r1
        xset ENT
        st r10, [x+11]
        lstw l0, [x+26]
        lshr l0, 16
        lstw l0, [x+20]
        ldi r8, 1
        call stamp
        ret

; busy: E_BUSY if a descriptor is open on the entry at G_DLBA/G_DOFF
busy:
        ldi r6, 1
; busy_mask: as busy, counting only descriptors with a flag of R6 (open for
; writing: $0C)
busy_mask:
        ldi r2, 0
bz_loop:
        call fdptr
        ld r0, [x+F_FLAGS]
        and r0, r6
        jz bz_next
        lld l1, [x+F_DLBA]
        lldw l2, [x+F_DOFF]
        lx l0
        xset G_DLBA
        lld l3, [x+0]
        lcmp l1, l3
        jnz bz_next_x
        lldw l3, [x+4]
        lcmp l2, l3
        jz bz_busy
bz_next_x:
        xl l0
bz_next:
        inc r2
        cmpi r2, 10
        jnz bz_loop
        ret
bz_busy:
        ldi r12, E_BUSY
        jmp error

; dirent_update: descriptor R2's size and first cluster into its entry, the
; archive bit and the time stamp set; its dirty flag cleared
dirent_update:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, $EF
        st r0, [x+F_FLAGS]
        lld l0, [x+F_DLBA]
        lld l3, [x+F_FIRST]
        lld l2, [x+F_SIZE]
        lldw l1, [x+F_DOFF]
        sread l0
        je io_error
        laddi l1, SEC
        xl l1
        lst l2, [x+28]
        lstw l3, [x+26]
        lshr l3, 16
        lstw l3, [x+20]
        ld r0, [x+11]
        ori r0, $20
        st r0, [x+11]
        ldi r8, 0
        call stamp
        swrite l0
        je io_error
        ret

; ==============================================================================
; hypervisor: policy (R_ARG0 bit 0: programs read-only), SYSTEM access for
; programs (bit 0), the time stamp (R_ARG0 = FAT time | date << 16)
op_policy:
        lldi l1, G_RO
        jmp op_hyp_flag
op_sysaccess:
        lldi l1, G_SYS
op_hyp_flag:
        hyp
        jnc op_access
        xset REQ
        ld r0, [x+R_ARG0]
        andi r0, 1
        xl l1
        st r0, [x+0]
        jmp ok
op_settime:
        hyp
        jnc op_access
        xset REQ
        lld l0, [x+R_ARG0]
        xset G_TIME
        lst l0, [x+0]
        jmp ok

; create(path; R_ARG0 attributes: read-only, hidden, system, archive; R_FLAGS
; bit 7 the descriptor in R_FD) -> R_FD, open for writing
op_create:
        call need_rw
        call resolve_parent
        call not_exists
        xset REQ
        ld r10, [x+R_ARG0]
        andi r10, $07
        ori r10, $20
        call sys_ok
        lldi l0, 0
        call ent_new
        call make_entry
        call fsinfo_sync
        call fdalloc
        lldi l3, 0
        ldi r0, 5                       ; open, write
        call fdnew
        call fdnum
        xset REQ
        st r0, [x+R_FD]
        jmp ok

; sys_ok: attributes R10 with SYSTEM need the hypervisor or SYSTEM access
sys_ok:
        mov r0, r10
        andi r0, $04
        jz so_ok
        hyp
        jc so_ok
        xset G_SYS
        ld r0, [x+0]
        cmpi r0, 0
        jz op_access
so_ok:
        ret

; mkdir(path)
op_mkdir:
        call need_rw
        call resolve_parent
        call not_exists
        lldi l1, 0                      ; its cluster, "." and ".."
        call alloc
        xset G_NEWCL
        lst l0, [x+0]
        call zero_cluster
        ldi r0, ' '
        yset SEC
        ldi r1, 11
        fill r1
        yset SEC+32
        ldi r1, 11
        fill r1
        ldi r0, '.'
        xset SEC
        st r0, [x+0]
        st r0, [x+32]
        st r0, [x+33]
        ldi r0, $10
        st r0, [x+11]
        st r0, [x+43]
        lmov l1, l0
        lstw l1, [x+26]
        lshr l1, 16
        lstw l1, [x+20]
        ldi r8, 1
        call stamp
        xset G_PARDIR
        lld l1, [x+0]
        xset SEC+32
        lstw l1, [x+26]
        lshr l1, 16
        lstw l1, [x+20]
        call stamp
        ldi r3, 0
        call clus2lba
        swrite l2
        je io_error
        xset G_NEWCL                    ; its entry in the parent
        lld l0, [x+0]
        ldi r10, $10
        call ent_new
        call make_entry
        call fsinfo_sync
        jmp ok

; delete(path): a file
op_delete:
        call need_rw
        call resolve
        cmpi r9, 0
        jz op_isdir
        mov r0, r10
        andi r0, $10
        jnz op_isdir
        call busy
        lmov l0, l3
        call free_chain
        call mark_run
        call fsinfo_sync
        jmp ok

; rmdir(path): an empty directory, no one's current directory
op_rmdir:
        call need_rw
        call resolve
        cmpi r9, 0
        jz op_access                    ; (the root)
        mov r0, r10
        andi r0, $10
        jz rv_notdir
        xset G_DIRCL
        lst l3, [x+0]
        ldi r2, 0                       ; a current directory, or open?
rd_cwd:
        btol l1, r2
        lshl l1, 2
        laddi l1, CWD
        xl l1
        lld l1, [x+0]
        lcmp l1, l3
        jz bz_busy
        inc r2
        cmpi r2, 8
        jnz rd_cwd
        call busy
        lmov l0, l3                     ; empty?
        call dw_start
rme_entry:
        ld r0, [x+0]
        cmpi r0, 0
        jz rme_empty
        cmpi r0, $E5
        jz rme_next
        cmpi r0, '.'
        jz rme_next                     ; ("." and "..": no name starts with '.' in 8.3)
        ld r1, [x+11]
        cmpi r1, $0F
        jz rme_next
        ldi r12, E_NOTEMPTY
        jmp error
rme_next:
        call dw_next
        jnz rme_entry
rme_empty:
        xset G_DIRCL
        lld l0, [x+0]
        call free_chain
        call mark_run
        call fsinfo_sync
        jmp ok

; rename(old path, new path after the old one's terminator): on one drive
op_rename:
        call need_rw
        call resolve
        cmpi r9, 0
        jz op_access
        call busy
        xset G_RUN                      ; keep the old entry, its run, its drive
        yset G_SAVRUN
        ldi r1, 7
        copy r1
        st r5, [y+0]
        xset ENT
        yset G_SAVENT
        ldi r1, 32
        copy r1
        xset G_PBASE                    ; the new path
        lldw l1, [x+0]
        xl l1
rn_skip:
        ldx r0
        jnz rn_skip
        lx l1
        xset G_PBASE
        lstw l1, [x+0]
        call resolve_parent
        xset G_SAVRUN+7
        ld r0, [x+0]
        cmp r0, r5
        jnz bad_request                 ; (another drive)
        call not_exists
        xset G_SAVENT                   ; the entry, under its new name
        yset ENT
        ldi r1, 32
        copy r1
        call make_entry
        xset G_SAVRUN                   ; the old one goes
        yset G_RUN
        ldi r1, 7
        copy r1
        call mark_run
        xset G_SAVENT+11                ; a directory: ".." is the new parent
        ld r0, [x+0]
        andi r0, $10
        jz rn_done
        xset G_SAVENT
        lldw l0, [x+20]
        lshl l0, 16
        lldw l1, [x+26]
        lor l0, l1
        ldi r3, 0
        call clus2lba
        sread l2
        je io_error
        xset G_PARDIR
        lld l1, [x+0]
        xset SEC+32
        lstw l1, [x+26]
        lshr l1, 16
        lstw l1, [x+20]
        swrite l2
        je io_error
rn_done:
        call fsinfo_sync
        jmp ok

; setattr(path, R_ARG0: read-only, hidden, system, archive)
op_setattr:
        call need_rw
        call resolve
        cmpi r9, 0
        jz op_access
        xset REQ
        ld r1, [x+R_ARG0]
        andi r1, $27
        mov r0, r10                     ; SYSTEM changing?
        xor r0, r1
        andi r0, $04
        jz sa_ok
        ldi r10, $04
        call sys_ok
sa_ok:
        xset G_DLBA
        lld l0, [x+0]
        lldw l1, [x+4]
        sread l0
        je io_error
        laddi l1, SEC
        xl l1
        ld r0, [x+11]
        andi r0, $D8
        or r0, r1
        st r0, [x+11]
        swrite l0
        je io_error
        jmp ok

; truncate(fd, R_ARG0 length): shorter frees clusters; longer allocates them
; (contiguous where it can) and fills with zeros
op_truncate:
        xset REQ
        ld r0, [x+R_FD]
        call fdget
        call fd_writable
        call on_error_update
        xset REQ
        lld l0, [x+R_ARG0]
        xset G_LEN
        lst l0, [x+0]
        call fdptr
        lld l1, [x+F_SIZE]
        lcmp l0, l1
        jc tr_shrink
        jz tr_done
        ; longer: from the old size, a sector at a time
tr_grow:
        call fdptr
        lld l1, [x+F_SIZE]
        xset G_LEN
        lld l0, [x+0]
        lcmp l1, l0
        jnc tr_done
        xset G_WPOS
        lst l1, [x+0]
        call fdptr
        call locate_w                   ; L2 sector, R1/R9 offset
        btol l1, r1
        btol l3, r9
        lshl l3, 8
        lor l1, l3
        lz l1
        jz tr_whole
        sread l2                        ; part of a sector: zeros after the offset
        je io_error
        lmov l3, l1
        laddi l3, SEC
        yl l3
        ldi r0, 0
tr_zero:
        sty r0
        ly l3
        lcmpi l3, SEC+512
        jnz tr_zero
        jmp tr_write
tr_whole:
        lx l3
        lmov l3, l2
        call zero_sec
        lmov l2, l3
tr_write:
        swrite l2
        je io_error
        call fdptr                      ; the size: to the end of this sector
        lld l1, [x+F_SIZE]
        lldi l3, 511
        lor l1, l3
        laddi l1, 1
        xset G_LEN
        lld l0, [x+0]
        lcmp l1, l0
        jc tr_size
        lmov l1, l0
tr_size:
        call fdptr
        lst l1, [x+F_SIZE]
        jmp tr_grow
tr_shrink:
        ; clusters kept: ceil(length / cluster size)
        lmov l3, l0
        lldi l1, 1
        lshl l1, 9
        lshlr l1, r13
        lsubi l1, 1
        ladd l3, l1
        lshr l3, 9
        lshrr l3, r13
        call fdptr
        lld l0, [x+F_FIRST]
        lz l3
        jnz tr_keep
        lldi l1, 0                      ; none: the whole chain goes
        lst l1, [x+F_FIRST]
        call free_chain
        jmp tr_shrunk
tr_keep:
        lsubi l3, 1                     ; to the last cluster kept
tr_walk:
        lz l3
        jz tr_cut
        fatnx l0
        jz tr_shrunk                    ; (shorter already)
        lsubi l3, 1
        jmp tr_walk
tr_cut:
        lmov l1, l0
        fatnx l0                        ; the rest
        jz tr_shrunk
        lldi l2, 0
        lsubi l2, 1
        lshr l2, 4
        fatset l1, l2
        je io_error
        call free_chain
tr_shrunk:
        call fdptr
        xset G_LEN
        lld l0, [x+0]
        call fdptr
        lst l0, [x+F_SIZE]
        lld l0, [x+F_FIRST]
        lst l0, [x+F_CUR]
        lldi l0, 0
        lst l0, [x+F_CIDX]
tr_done:
        call dirent_update
        call fsinfo_sync
        jmp ok

; flush(fd): the directory entry, if it is out of date
op_flush:
        xset REQ
        ld r0, [x+R_FD]
        call fdget
        ld r0, [x+F_FLAGS]
        andi r0, $10
        jz ok
        call dirent_update
        jmp ok

; on_error_update: an error from here on still writes descriptor R2's entry
on_error_update:
        lx l1
        xset G_ONERR
        st r2, [x+0]
        xl l1
        ret

; fd_writable: descriptor R2 (X) open for writing, and writing allowed
fd_writable:
        ld r0, [x+F_FLAGS]
        andi r0, $0C
        jz op_access
        call need_rw
        call fdptr
        ret

; locate_w: as locate, for writing: the chain grows as far as the position
; G_WPOS needs -> L2 the sector, R1/R9 the offset (descriptor R2)
locate_w:
        call fdptr
        lld l0, [x+F_FIRST]
        lz l0
        jnz lw_have
        lldi l1, 0                      ; empty: its first cluster
        call alloc
        call fdptr
        lst l0, [x+F_FIRST]
        lst l0, [x+F_CUR]
        lldi l1, 0
        lst l1, [x+F_CIDX]
lw_have:
        xset G_WPOS
        lld l3, [x+0]
        lshr l3, 9
        lshrr l3, r13
        xset G_TGT
        lst l3, [x+0]
        call fdptr
        lld l0, [x+F_CIDX]
        lcmp l3, l0
        jnc lw_from_cur
        lld l0, [x+F_FIRST]
        lldi l2, 0
        jmp lw_walk
lw_from_cur:
        lmov l2, l0
        lld l0, [x+F_CUR]
lw_walk:
        xset G_TGT
        lld l3, [x+0]
        lcmp l2, l3
        jz lw_here
        xset G_PREVC
        lst l0, [x+0]
        xset G_IDX
        lst l2, [x+0]
        fatnx l0
        jz lw_extend
        jc io_error                     ; (a broken chain)
        xset G_IDX
        lld l2, [x+0]
        laddi l2, 1
        jmp lw_walk
lw_extend:
        xset G_PREVC
        lld l1, [x+0]
        call alloc
        xset G_IDX
        lld l2, [x+0]
        laddi l2, 1
        jmp lw_walk
lw_here:
        call fdptr
        lst l0, [x+F_CUR]
        lst l2, [x+F_CIDX]
        xset G_WPOS
        lld l1, [x+0]
        lmov l2, l1
        lshr l2, 9
        ltob r3, l2, 0
        mov r0, r11
        dec r0
        and r3, r0
        ltob r1, l1, 0
        ltob r9, l1, 1
        andi r9, 1
        call clus2lba
        ret

; $72 write(fd = $D684, n = $D681-$D682 <= 512): the bytes at $E00 at the
; position; $73 append: at the end
cmd_append:
        ldi r8, 1
        jmp cw_go
cmd_write:
        ldi r8, 0
cw_go:
        arg l0
cw_l0:
        ltob r0, l0, 3
        lshl l0, 16
        lshr l0, 16
        lldi l1, 512
        lcmp l1, l0
        jc cw_bad
        xset G_WN
        lst l0, [x+0]
        call fdget
        call fd_writable
        call on_error_update
        ld r0, [x+F_FLAGS]              ; appending (the command or the descriptor)
        andi r0, $08
        jz cw_where
        ldi r8, 1
cw_where:
        cmpi r8, 0
        jz cw_pos
        lld l1, [x+F_SIZE]
        lst l1, [x+F_POS]
cw_pos:
        lldi l0, 0
        xset G_WDONE
        lst l0, [x+0]
cw_loop:
        xset G_WN
        lld l3, [x+0]
        xset G_WDONE
        lld l0, [x+0]
        lcmp l0, l3
        jz cw_done
        call fdptr
        lld l1, [x+F_POS]
        xset G_WPOS
        lst l1, [x+0]
        call locate_w                   ; L2 sector, R1/R9 offset
        lldi l0, 512                    ; chunk = min(512 - offset, n - done)
        btol l1, r1
        btol l3, r9
        lshl l3, 8
        lor l1, l3
        lsub l0, l1
        xset G_WN
        lld l3, [x+0]
        xset G_WDONE
        lld l1, [x+0]
        lsub l3, l1
        lcmp l3, l0
        jnc cw_chunk
        lmov l0, l3
cw_chunk:
        lcmpi l0, 512                   ; a whole sector from $E00: straight out
        jnz cw_rmw
        dwrite l2
        je io_error
        jmp cw_advance
cw_rmw:
        sread l2
        je io_error
        btol l1, r1                     ; copy L0 bytes: $E00 + done -> SEC + offset
        btol l3, r9
        lshl l3, 8
        lor l1, l3
        laddi l1, SEC
        yl l1
        xset G_WDONE
        lld l1, [x+0]
        laddi l1, REQ
        xl l1
        lmov l3, l0
cw_copy:
        lz l3
        jz cw_copied
        ltob r1, l3, 1
        cmpi r1, 0
        jz cw_copy_last
        ldi r1, 0
        copy r1
        lsubi l3, 256
        jmp cw_copy
cw_copy_last:
        ltob r1, l3, 0
        copy r1
cw_copied:
        swrite l2
        je io_error
cw_advance:
        xset G_WDONE                    ; done, position, size
        lld l1, [x+0]
        ladd l1, l0
        lst l1, [x+0]
        call fdptr
        lld l1, [x+F_POS]
        ladd l1, l0
        lst l1, [x+F_POS]
        lld l3, [x+F_SIZE]
        lcmp l3, l1
        jnc cw_loop
        lst l1, [x+F_SIZE]
        jmp cw_loop
cw_done:
        call dirent_update
        call fsinfo_sync
        xset G_WN
        lld l0, [x+0]
        setarg l0
        done
cw_bad:
        fail E_BADREQ

; $75 write exactly 512 bytes from $E00 at file sector k ($D681-$D683) of fd
; ($D684), inside the file; the entry is updated at flush / close
cmd_writesector:
        arg l0
        ltob r0, l0, 3
        lshl l0, 8
        lshr l0, 8
        lmov l3, l0
        xset G_PATHP
        lst l3, [x+0]
        call fdget
        call fd_writable
        xset G_PATHP
        lld l3, [x+0]
        call fdptr
        lmov l1, l3
        lshl l1, 9
        lmov l3, l1
        laddi l3, 511
        lld l2, [x+F_SIZE]
        lcmp l3, l2
        jnc rsec_past
        call locate
        jc rsec_past
        dwrite l2
        je rsec_io
        call fdptr
        ld r0, [x+F_FLAGS]
        ori r0, $10
        st r0, [x+F_FLAGS]
        done

; ==============================================================================
; $76/$77 read the next 512 bytes of fd 0/1, $78/$79 write them: the caller's
; 0/1 (H0/H1 in hypervisor mode, a program's own otherwise).  The count comes
; back as for $71/$72.  A whole sector inside the file at an aligned position
; goes straight between the card and $E00 (writes: the entry is updated at
; flush or close, as for $75); anything else is $71/$72 with n = 512.
cmd_qread:
        call quick_fast
        jc qr_slow
        dread l2
        je io_error
        jmp quick_done
qr_slow:
        call quick_arg
        jmp cmd_read_l0

cmd_qwrite:
        call quick_fd
        call fd_writable
        ld r0, [x+F_FLAGS]              ; (append: always at the end)
        andi r0, $08
        jnz qw_slow
        call quick_fast
        jc qw_slow
        dwrite l2
        je io_error
        call fdptr
        ld r0, [x+F_FLAGS]
        ori r0, $10
        st r0, [x+F_FLAGS]
        jmp quick_done
qw_slow:
        call quick_arg
        ldi r8, 0
        jmp cw_l0

; quick_fd: the command's descriptor (bit 0) -> R2, X, its drive loaded
quick_fd:
        cmd r0
        andi r0, 1
        call fdget
        ret

; quick_fast: a file open, its position aligned and a whole sector inside it
; -> L2 the sector; else C set
quick_fast:
        call quick_fd
        ld r0, [x+F_FLAGS]
        andi r0, 2
        jnz rdc_bad
        lld l1, [x+F_POS]
        ltob r0, l1, 0
        cmpi r0, 0
        jnz qf_no
        ltob r0, l1, 1
        andi r0, 1
        jnz qf_no
        lmov l3, l1
        laddi l3, 512
        lld l2, [x+F_SIZE]
        lcmp l2, l3
        jc qf_no
        call locate
        ret
qf_no:
        ldi r0, 0
        cmpi r0, 1                      ; C = 1
        ret

; quick_done: the position advanced by a sector, the count 512
quick_done:
        call fdptr
        lld l1, [x+F_POS]
        laddi l1, 512
        lst l1, [x+F_POS]
        lldi l0, 512
        setarg l0
        done

; quick_arg: L0 = the $71/$72 argument: the descriptor, n = 512
quick_arg:
        cmd r0
        andi r0, 1
        btol l0, r0
        lshl l0, 24
        lldi l1, 512
        lor l0, l1
        ret

; ==============================================================================
; $07 thaw (hypervisor), after the freezer has put $000-$7FF back: the cards
; are scanned again, each drive is found again by its volume (serial number,
; partition start and size: the card may have been changed, or its partitions
; found in another order), then every open descriptor is checked against the
; card.  A file's entry must still be in use at the same place with the same
; first cluster (its size is taken from it, its place in the chain restarts);
; a directory's first sector must still be its own "." entry.  One that fails
; becomes stale.  Current directories that fail fall back to the root.
; -> R_ARG0: the descriptors made stale (bits 0-1 H0/H1, 2-9 the programs'
; 0-7), R_ARG1: drives found
.equ T_DRV,    NAME      ; (384) the frozen drive table
.equ T_CWD,    $500      ; (32) the frozen current directories
.equ T_DRIVE,  $520      ;   and current drive
.equ T_STALE,  $522      ; (2) the mask being built
op_thaw:
        hyp
        jnc op_access
        xset DRV
        yset T_DRV
        ldi r1, 0
        copy r1
        ldi r1, 128
        copy r1
        xset CWD
        yset T_CWD
        ldi r1, 33
        copy r1
        xset T_STALE
        ldi r0, 0
        st r0, [x+0]
        st r0, [x+1]
        call rescan
        ; the current directories
        ldi r6, 1
th_cwd:
        btol l0, r6
        laddi l0, -1
        lshl l0, 2
        laddi l0, T_CWD
        xl l0
        lld l0, [x+0]
        lz l0
        jz th_cwd_next
        xset G_PREV                     ; (keep it)
        lst l0, [x+0]
        call th_find
        cmpi r5, 0
        jz th_cwd_next
        call usedrive
        xset G_PREV
        lld l0, [x+0]
        call dir_ok
        jnz th_cwd_next
        btol l2, r5
        laddi l2, -1
        lshl l2, 2
        laddi l2, CWD
        xl l2
        xset G_PREV
        lld l0, [x+0]
        xl l2
        lst l0, [x+0]
th_cwd_next:
        inc r6
        cmpi r6, 9
        jnz th_cwd
        xset T_DRIVE                    ; the current drive
        ld r6, [x+0]
        call th_find
        cmpi r5, 0
        jz th_fds
        xset G_DRIVE
        st r5, [x+0]
th_fds:
        ldi r2, 0
th_fd:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 1
        jz th_next
        ld r0, [x+F_FLAGS]
        andi r0, $80
        jnz th_next
        ld r6, [x+F_DRIVE]
        call th_find
        cmpi r5, 0
        jz th_stale
        call fdptr
        st r5, [x+F_DRIVE]
        call usedrive
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, 2
        jnz th_dir
        lld l0, [x+F_DLBA]              ; a file: its entry
        sread l0
        je th_stale
        lldw l1, [x+F_DOFF]
        laddi l1, SEC
        lld l2, [x+F_FIRST]
        xl l1
        ld r0, [x+0]
        cmpi r0, 0
        jz th_stale
        cmpi r0, $E5
        jz th_stale
        ld r0, [x+11]
        andi r0, $18
        jnz th_stale
        lldw l0, [x+20]
        lshl l0, 16
        lldw l3, [x+26]
        lor l0, l3
        lcmp l0, l2
        jnz th_stale
        lld l3, [x+28]
        call fdptr
        lst l3, [x+F_SIZE]
        lst l2, [x+F_CUR]
        lldi l0, 0
        lst l0, [x+F_CIDX]
        jmp th_next
th_dir:
        lld l0, [x+F_FIRST]
        call dir_ok
        jz th_next
th_stale:
        call fdptr
        ld r0, [x+F_FLAGS]
        ori r0, $80
        st r0, [x+F_FLAGS]
        xset T_STALE                    ; bit R2 of the mask
        mov r1, r2
        cmpi r1, 8
        jc th_bit
        xaddi 1
        subi r1, 8
th_bit:
        ldi r0, 1
th_shift:
        cmpi r1, 0
        jz th_set
        shl r0
        dec r1
        jmp th_shift
th_set:
        ld r1, [x+0]
        or r1, r0
        st r1, [x+0]
th_next:
        inc r2
        cmpi r2, 10
        jnz th_fd
        xset T_STALE
        lldw l0, [x+0]
        xset REQ
        lst l0, [x+R_ARG0]
        xset G_NDRV
        ld r0, [x+0]
        btol l0, r0
        xset REQ
        lst l0, [x+R_ARG1]
        jmp ok

; th_find: frozen drive R6 (1..8) -> R5 the drive its volume is now (0: gone).
; The same number first, then any.
th_find:
        cmpi r6, 0
        jz tf_none
        cmpi r6, 9
        jnc tf_none
        mov r0, r6
        dec r0
        call drvaddr
        laddi l2, T_DRV-DRV
        xl l2
        ld r0, [x+D_FLAGS]
        andi r0, 1
        jz tf_none
        mov r5, r6
        call tf_same
        jz tf_ret
        ldi r5, 1
tf_loop:
        call tf_same
        jz tf_ret
        inc r5
        cmpi r5, 9
        jnz tf_loop
tf_none:
        ldi r5, 0
tf_ret:
        ret
; tf_same: drive R5 holds the volume of frozen record X? (Z set if so)
tf_same:
        mov r0, r5
        dec r0
        call drvaddr
        yl l2
        ld r0, [y+D_FLAGS]
        andi r0, 1
        jz tf_no
        lld l0, [x+D_SERIAL]
        lld l1, [y+D_SERIAL]
        lcmp l0, l1
        jnz tf_ret2
        lld l0, [x+D_PART]
        lld l1, [y+D_PART]
        lcmp l0, l1
        jnz tf_ret2
        lld l0, [x+D_SIZE]
        lld l1, [y+D_SIZE]
        lcmp l0, l1
tf_ret2:
        ret
tf_no:
        ldi r0, 1                       ; (Z = 0)
        ret

; dir_ok: is cluster L0 (0 = the root) a directory of the drive in use?  Its
; first entry must be "." naming it.  -> Z set if so
dir_ok:
        lz l0
        jz do_ret
        ldi r3, 0
        call clus2lba
        lmov l3, l0
        sread l2
        je do_no
        xset SEC
        ld r0, [x+0]
        cmpi r0, '.'
        jnz do_ret
        ld r0, [x+1]
        cmpi r0, ' '
        jnz do_ret
        ld r0, [x+11]
        andi r0, $10
        jz do_no
        lldw l0, [x+20]
        lshl l0, 16
        lldw l1, [x+26]
        lor l0, l1
        lcmp l0, l3
do_ret:
        ret
do_no:
        ldi r0, 1                       ; (Z = 0)
        ret

; ==============================================================================
; $08 mountimage (hypervisor): descriptor R_FD (open; bit 7 a program's) as an
; F011 disk image.  The F011 reads and writes the card itself, at the image's
; start + the track/sector offset, so the file must be one run of clusters
; (else E_FRAG).  Open for writing, its entry gets the archive bit and the
; time now (the F011's writes go around the engine).
; -> R_ARG0 the start sector (for $D68C), R_ARG1 the size in sectors,
; R_FLAGS the card (1 external: select it before writing $D68C)
op_mount:
        hyp
        jnc op_access
        xset REQ
        ld r0, [x+R_FD]
        call fdget
        ld r0, [x+F_FLAGS]
        andi r0, 2
        jnz op_isdir
        lld l0, [x+F_FIRST]
        lz l0
        jz mt_frag
        xset G_PREV
        lst l0, [x+0]
mt_walk:
        lmov l3, l0
        laddi l3, 1
        fatnx l0
        jz mt_end
        jc io_error
        lcmp l0, l3
        jnz mt_frag
        jmp mt_walk
mt_end:
        call fdptr
        ld r0, [x+F_FLAGS]
        andi r0, $0C
        jz mt_out
        call dirent_update
mt_out:
        xset G_PREV
        lld l0, [x+0]
        ldi r3, 0
        call clus2lba
        xset REQ
        lst l2, [x+R_ARG0]
        call fdptr
        lld l1, [x+F_SIZE]
        lshr l1, 9
        lld l3, [x+F_SIZE]              ; (rounded up)
        ltob r1, l3, 0
        ltob r6, l3, 1
        andi r6, 1
        or r1, r6
        cmpi r1, 0
        jz mt_size
        laddi l1, 1
mt_size:
        xset REQ
        lst l1, [x+R_ARG1]
        mov r0, r5
        dec r0
        call drvaddr
        xl l2
        ld r0, [x+D_FLAGS]
        shr r0
        andi r0, 1
        xset REQ
        st r0, [x+R_FLAGS]
        jmp ok
mt_frag:
        ldi r12, E_FRAG
        jmp error
