;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

dos_and_process_trap:

        ;; XXX - Machine is being updated to automatically disable IRQs on trapping
        ;; to hypervisor, but for now, we need to do this explicitly.
        ;; Should be able to be removed after 20160103
        ;; BG: cannot confirm removal of the instruction below. Dated 20160902
        sei

        ;; XXX - We have just added a fix for this in the CPU, to CLEAR DECIMAL MODE
        ;; on entry to the hypervisor. But I'm not taking any chances just now.
        ;;
        cld

        ;; Sub-function is selected by A.
        ;; Bits 6-1 are the only ones used.
        ;; Mask out bit 0 so that indirect jmp's are valid.
        ;;
        and #$7E
        tax
        jmp (dos_and_process_trap_table,x)

;;         ========================

dos_and_process_trap_table:

        ;; $00 - $0E
        ;;
        !16 trap_dos_getversion
        !16 trap_dos_getdefaultdrive
        !16 trap_dos_getcurrentdrive
        !16 trap_dos_selectdrive
        !16 trap_dos_getdisksize              
        !16 trap_dos_getcwd
        !16 trap_dos_chdir
        !16 trap_dos_mkdir                    

        ;; $10 - $1E
        ;;
        !16 trap_dos_rmdir                    
        !16 trap_dos_opendir
        !16 trap_dos_readdir
        !16 trap_dos_closedir
        !16 trap_dos_openfile
        !16 trap_dos_readfile
        !16 trap_dos_writefile
        !16 trap_dos_mkfile                   

        ;; $20 - $2E
        ;;
        !16 trap_dos_closefile
        !16 trap_dos_closeall
        !16 trap_dos_seekfile                 
        !16 trap_dos_rmfile
        !16 trap_dos_fstat                    
        !16 trap_dos_rename                   
        !16 trap_dos_filedate                 ;; not currently implemented
        !16 trap_dos_setname

        ;; $30 - $3E
        ;;
        !16 trap_dos_findfirst
        !16 trap_dos_findnext
        !16 trap_dos_findfile
        !16 trap_dos_loadfile
        !16 trap_dos_geterrorcode
        !16 trap_dos_setup_transfer_area
        !16 trap_dos_cdrootdir
        !16 trap_dos_loadfile_attic

        ;; $40 - $4E
        ;;
        !16 trap_dos_d81attach0               ;; DOS 1.2 compatibility - DEPRECATED in favor of trap_dos_attach
        !16 trap_dos_d81detach                ;; DOS 1.2 compatibility - DEPRECATED in favor of trap_dos_attach
        !16 trap_dos_d81write_en
        !16 trap_dos_d81attach1               ;; DOS 1.2 compatibility - DEPRECATED in favor of trap_dos_attach
        !16 trap_dos_get_proc_desc
        !16 trap_dos_attach
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $50 - $5E
        ;;
        !16 trap_dos_gettasklist              ;; not currently implemented
        !16 trap_dos_sendmessage              ;; not currently implemented
        !16 trap_dos_receivemessage           ;; not currently implemented
        !16 trap_dos_writeintotask            ;; not currently implemented
        !16 trap_dos_readoutoftask            ;; not currently implemented
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 invalid_subfunction

        ;; $60 - $6E
        ;;
        !16 trap_dos_terminateothertask       ;; not currently implemented
        !16 trap_dos_create_task_native       ;; not currently implemented
        !16 trap_dos_load_into_task           ;; not currently implemented
        !16 trap_dos_create_task_c64          ;; not currently implemented
        !16 trap_dos_create_task_c65          ;; not currently implemented
        !16 trap_dos_exit_and_switch_to_task  ;; not currently implemented
        !16 trap_dos_switch_to_task           ;; not currently implemented
        !16 trap_dos_exit_task                ;; not currently implemented

        ;; $70 - $7E
        ;;
        !16 trap_task_toggle_rom_writeprotect
        !16 trap_task_toggle_force_4502
        !16 trap_task_get_mapping
        !16 trap_task_set_mapping
        !16 invalid_subfunction
        !16 invalid_subfunction
        !16 trap_serial_monitor_write
        !16 reset_entry

trap_serial_monitor_write:
        sty hypervisor_write_char_to_serial_monitor
        jmp return_from_trap_with_success

;; ============================================================
;; TRAP HANDLERS
;; ============================================================

;; ---- trap_dos_getversion ----

trap_dos_getversion:

        ;; Return OS and DOS version.
        ;; A.X = OS Version major/minor
        ;; Y.Z = DOS Version major/minor

        lda #<os_version
        sta hypervisor_x
        lda #>os_version
        sta hypervisor_a
        lda #>dos_version
        sta hypervisor_y
        lda #<dos_version
        sta hypervisor_z
        jmp return_from_trap_with_success

;; ---- trap_dos_getdefaultdrive ----

trap_dos_getdefaultdrive:

        lda dos_default_disk
        sta hypervisor_a
        jmp return_from_trap_with_success

;; ---- trap_dos_getcurrentdrive ----

trap_dos_getcurrentdrive:

        lda dos_disk_current_disk
        sta hypervisor_a
        jmp return_from_trap_with_success

;; ---- trap_dos_selectdrive ----

trap_dos_selectdrive:

        ldx hypervisor_x
        jsr dos_set_current_disk

return_from_trap_with_carry_flag:
        lbcc return_from_trap_with_failure
+       jmp return_from_trap_with_success

trap_dos_closeall:

        jsr dos_clear_filedescriptors
        jmp return_from_trap_with_success


;; Clear all file descriptors.
;; This just consists of setting the drive number to $ff,
;; which indicates "no such drive"
;; Drive number field is first byte of file descriptor for convenience

dos_clear_filedescriptors:

        ;; XXX - This doesn't close the underlying file descriptors!

        lda #$ff
        sta currenttask_filedescriptor0
        sta currenttask_filedescriptor1
        sta currenttask_filedescriptor2
        sta currenttask_filedescriptor3

        ;; XXX - Doesn't flush any files open for write
        jsr dos_clear_all_filedescriptors

        sec
        rts

;; ---- trap_dos_getdisksize ----

trap_dos_getdisksize:
        ;; Returns the size of the currently selected drive (SD card
        ;; partition). Free space is not reported: nothing in the codebase
        ;; currently counts free clusters (a full-FAT scan), so this only
        ;; exposes the fields already tracked in dos_disk_table.
        ;;
        ;; Y: MSB of destination area (same convention as get_proc_desc).
        ;; Output, starting at $YY00:
        ;;   $00 dword  total sector count of the partition
        ;;   $04 byte   sectors per cluster
        ;;   $05 dword  total cluster count of the partition
        ;;
        ;; Example:
        ;;   LDY #$80             ; destination page for the result
        ;;   LDA #$08 : STA $D640 : CLV : BCC error
        jsr hypervisor_setup_copy_region
        bcs gds_havearea
        +Checkpoint "trap_dos_getdisksize <failure>"
        bra return_from_trap_with_carry_flag
gds_havearea:

        ldx dos_disk_table_offset
        ldy #0

        lda dos_disk_table + fs_sector_count + 0,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_sector_count + 1,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_sector_count + 2,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_sector_count + 3,x
        sta (<hypervisor_userspace_copy_vector),y
        iny

        lda dos_disk_table + fs_fat32_sectors_per_cluster,x
        sta (<hypervisor_userspace_copy_vector),y
        iny

        lda dos_disk_table + fs_fat32_cluster_count + 0,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_fat32_cluster_count + 1,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_fat32_cluster_count + 2,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda dos_disk_table + fs_fat32_cluster_count + 3,x
        sta (<hypervisor_userspace_copy_vector),y

        +Checkpoint "trap_dos_getdisksize <success>"
        sec
        bra return_from_trap_with_carry_flag

;; ---- trap_dos_getcwd ----

trap_dos_getcwd:
        ;; Returns the current working directory as a path string
        ;; (e.g. "/FOO/BAR"), resolved on demand by walking cwd up to
        ;; root (no persistent path tracking - always correct
        ;; regardless of how cwd got there). Each level's name is found
        ;; by reading its own ".." entry for the parent cluster, then
        ;; scanning the parent for the entry whose cluster matches.
        ;; Assumes a well-formed filesystem - a cyclic ".." chain would
        ;; loop forever, same trust level as the rest of Hyppo's FAT32
        ;; handling.
        ;;
        ;; A level contributes its long name where it has one and long
        ;; names are enabled; otherwise its 8.3 short name. That makes a
        ;; segment up to 64 characters rather than 12, so the path can
        ;; outgrow the 255-byte area at about four levels of long names,
        ;; and the call then fails with dos_errorcode_path_too_long
        ;; rather than running back over the two bytes below.
        ;;
        ;; Y: MSB of destination area.
        ;; Output, starting at $YY00:
        ;;   $00 byte   current disk number
        ;;   $01 byte   offset (within this same $YY00 area) of the
        ;;              null-terminated path string, e.g. "/FOO/BAR"
        ;;
        ;; Example:
        ;;   LDY #$80             ; destination page for the result
        ;;   LDA #$0A : STA $D640 : CLV : BCC error
        jsr hypervisor_setup_copy_region
        bcs gcwd_havearea
        +Checkpoint "trap_dos_getcwd <failure>"
        bra return_from_trap_with_carry_flag
gcwd_havearea:

        ;; Save the real cwd (restored before every return below).
        jsr rmdir_save_cwd

        jsr gcwd_cwd_to_zptempv32   ;; cur_cluster, walked up to root

        ldy #255
        lda #0
        sta (<hypervisor_userspace_copy_vector),y  ;; nul terminator
        sty <zptempp2               ;; cursor (grows backward from 255)

gcwd_loop:
        ;; cur_cluster == this disk's real root cluster? then we're done.
        jsr dos_cluster_is_root
        bcs gcwd_finish

        ;; Not root - find its parent, then scan the parent for the
        ;; entry matching cur_cluster.
        jsr dos_find_parent_of_cluster
        ldx #3
-       lda <zptempv32,x
        sta dos_dfdcbc_target,x
        dex
        bpl -
        jsr dos_find_dirent_in_cwd_by_cluster
        bcs gcwd_checkentry
gcwd_toolong:
        lda #dos_errorcode_path_too_long
        sta dos_error_code
gcwd_fail:
        jsr rmdir_restore_cwd
        +Checkpoint "trap_dos_getcwd <failure>"
        jmp return_from_trap_with_failure

gcwd_checkentry:
        ;; Found it - prepend "/" and its name to the path buffer,
        ;; growing backward from the cursor. dos_readdir has already put
        ;; the long name in dos_dirent_longfilename if the entry has one
        ;; and long names are enabled; otherwise it leaves the length at
        ;; zero and the 8.3 name is derived instead.
        lda dos_dirent_longfilename_length
        bne gcwd_havesegment
        jsr dos_derive_dotted_shortname
        lda dos_dirent_longfilename_length
gcwd_havesegment:
        sta <dos_scratch_byte_2      ;; this segment's char count

        ;; Long names make a segment up to 64 characters, so the buffer
        ;; can genuinely run out now - bytes 0 and 1 hold the drive and
        ;; the path offset and must not be overwritten.
        lda <zptempp2
        sec
        sbc <dos_scratch_byte_2
        bcc gcwd_toolong
        sbc #1
        bcc gcwd_toolong
        cmp #2
        bcc gcwd_toolong
        sta <zptempp2
        tay
        lda #'/'
        sta (<hypervisor_userspace_copy_vector),y
        iny
        ldx #0
gcwd_namecopy:
        cpx <dos_scratch_byte_2
        beq gcwd_namecopy_done
        lda dos_dirent_longfilename,x
        sta (<hypervisor_userspace_copy_vector),y
        iny
        inx
        bra gcwd_namecopy
gcwd_namecopy_done:
        ;; dos_find_dirent_in_cwd_by_cluster already closed the FD.

        ;; cur_cluster = the parent we just resolved a name for.
        jsr gcwd_cwd_to_zptempv32
        bra gcwd_loop

gcwd_finish:
        jsr rmdir_restore_cwd

        ;; Root itself (depth == 0, nothing prepended) still needs a "/".
        lda <zptempp2
        cmp #255
        bne gcwd_havepath
        dec <zptempp2
        ldy <zptempp2
        lda #'/'
        sta (<hypervisor_userspace_copy_vector),y
gcwd_havepath:

        ldy #0
        lda dos_disk_current_disk
        sta (<hypervisor_userspace_copy_vector),y
        iny
        lda <zptempp2
        sta (<hypervisor_userspace_copy_vector),y

        +Checkpoint "trap_dos_getcwd <success>"
        sec
        jmp return_from_trap_with_carry_flag

gcwd_cwd_to_zptempv32:
        ldx #3
-	lda dos_disk_cwd_cluster,x
        sta <zptempv32,x
        dex
        bpl -
        rts

;; ---- trap_dos_chdir ----

trap_dos_chdir:

        ;; Opens file in current dirent structure
        ;; XXX - This means we must preserve the dirent struct when
        ;; context-switching to avoid a race-condition

        jsr dos_chdir
        bcc tdcd1

        +Checkpoint "trap_dos_chdir <success>"

        jmp return_from_trap_with_success_and_zero_accumulator

tdcd1:
        +Checkpoint "trap_dos_chdir <failure>"

        jmp generic_fail_from_error_code

;; ---- trap_dos_mkdir ----

trap_dos_mkdir:
        ;; Creates a sub-directory in the current directory.
        ;;
        ;; Precondition: filename already set via hyppo_setname.
        ;; Errors: dos_errorcode_file_exists if a file or sub-directory
        ;; already exists with that name.
        ;;
        ;; Example:
        ;;   ; Set the new directory's name first via hyppo_setname (A=$2E).
        ;;   LDA #$0E : STA $D640 : CLV : BCC error

        ;; 1. Existence check (mirrors trap_dos_mkfile).
        jsr dos_findfile
        bcc mkdir_notfound
        lda #dos_errorcode_file_exists
        +Checkpoint "trap_dos_mkdir <failure>"
        jmp mkfile_fail_with_a
mkdir_notfound:

        ;; Build the short name and work out how many LFN pieces it needs.
        jsr dos_analyze_name_or_fail

        ;; 2. Find a single free cluster for the new directory's own
        ;; data. Unlike mkfile (which needs a whole *empty FAT sector*
        ;; of contiguous clusters, since files need contiguous storage),
        ;; a directory only ever needs exactly one cluster here, so this
        ;; scans for the first individually-free cluster anywhere,
        ;; rather than requiring 128 consecutive free ones.
        ;;
        ;; Must start sector-aligned (a multiple of 128), not at cluster
        ;; 2: mkdir_found_free_cluster adds the scan's in-sector delta
        ;; (0-127) straight onto this value, so starting at 2 would mislabel
        ;; every found cluster as 2 higher than the one actually checked/
        ;; allocated. Clusters 0/1's reserved FAT entries are never zero
        ;; on a valid volume, so including them in the scan is harmless.
        jsr sd_map_sectorbuffer

        lda #0
        sta <(zptempv32+0)
        sta <(zptempv32+1)
        sta <(zptempv32+2)
        sta <(zptempv32+3)

mkdir_find_free_cluster_loop:
        jsr dos_copy_zptempv32_and_read_fat_sector

        ldx #0
        ldy #0
mkdir_scan_firsthalf:
        lda sd_sectorbuffer,y
        ora sd_sectorbuffer+1,y
        ora sd_sectorbuffer+2,y
        ora sd_sectorbuffer+3,y
        beq mkdir_found_free_cluster
        inx
        iny : iny : iny : iny
        cpx #64
        bne mkdir_scan_firsthalf

        ldy #0
mkdir_scan_secondhalf:
        lda sd_sectorbuffer+$100,y
        ora sd_sectorbuffer+$101,y
        ora sd_sectorbuffer+$102,y
        ora sd_sectorbuffer+$103,y
        beq mkdir_found_free_cluster
        inx
        iny : iny : iny : iny
        cpx #128
        bne mkdir_scan_secondhalf

        ;; This whole FAT sector (128 clusters) is fully allocated -
        ;; move on to the next one.
        ;; XXX Check that we haven't hit the end of the file system
        ;; (same known limitation as mkfile's own free-space search).
        lda #$80
        jsr dos_add_a_to_zptempv32
        bra mkdir_find_free_cluster_loop

mkdir_found_free_cluster:
        ;; X = entry delta (0-127) of the free cluster within this FAT
        ;; sector; zptempv32 is the sector's base cluster number.
        txa
        jsr dos_add_a_to_zptempv32

        ;; zptempv32 now holds the newly allocated cluster's number.

        ;; 3. Zero every sector of the new cluster before writing
        ;; anything into it. This matters, not just cosmetics: readdir's
        ;; scan treats a $00 first dirent byte as "skip this entry, keep
        ;; scanning", not "end of directory" - leftover garbage from a
        ;; previously-deleted file/dir occupying this cluster could
        ;; otherwise present as phantom entries later.
        ;;
        ;; Each sector of the cluster is written exactly once: sector 0
        ;; gets '.'/'..' built into it in memory before its single write
        ;; (rather than zero-filling it, writing it, then overwriting it
        ;; again with the real content), and any remaining sectors are
        ;; written zeroed.
        jsr dos_copy_zptempv32_and_cluster_to_sector

        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
        sta <dos_scratch_byte_1         ;; sectors-per-cluster loop counter

        jsr dos_zero_sectorbuffer

        ;; 4. Build '.' and '..' into what will become sector 0, still
        ;; only in memory - sd_sectorbuffer is all-zero from the fill
        ;; above, so only the two dirents themselves need populating.
        ;;
        ;; '.' entry at offset 0: name padded with spaces, then '.' in
        ;; the first byte; cluster = the new directory's own cluster.
        ldx #10
-	lda #$20
        sta sd_sectorbuffer,x
        dex
        bpl -
        lda #$2e
        sta sd_sectorbuffer+0
        lda #fs_fat32_attribute_isdirectory
        sta sd_sectorbuffer+fs_fat32_dirent_offset_attributes
        lda <(zptempv32+0)
        sta sd_sectorbuffer+fs_fat32_dirent_offset_clusters_low
        lda <(zptempv32+1)
        sta sd_sectorbuffer+fs_fat32_dirent_offset_clusters_low+1
        lda <(zptempv32+2)
        sta sd_sectorbuffer+fs_fat32_dirent_offset_clusters_high
        lda <(zptempv32+3)
        sta sd_sectorbuffer+fs_fat32_dirent_offset_clusters_high+1

        ;; '..' entry at offset 32: same, but two dots, and cluster =
        ;; the *parent's* cluster (the current dos_disk_cwd_cluster) -
        ;; using the "0 = root" convention dos_chdir already relies on.
        ldx #10
-	lda #$20
        sta sd_sectorbuffer+32,x
        dex
        bpl -
        lda #$2e
        sta sd_sectorbuffer+32+0
        sta sd_sectorbuffer+32+1
        lda #fs_fat32_attribute_isdirectory
        sta sd_sectorbuffer+32+fs_fat32_dirent_offset_attributes
        lda dos_disk_cwd_cluster+0
        sta sd_sectorbuffer+32+fs_fat32_dirent_offset_clusters_low
        lda dos_disk_cwd_cluster+1
        sta sd_sectorbuffer+32+fs_fat32_dirent_offset_clusters_low+1
        lda dos_disk_cwd_cluster+2
        sta sd_sectorbuffer+32+fs_fat32_dirent_offset_clusters_high
        lda dos_disk_cwd_cluster+3
        sta sd_sectorbuffer+32+fs_fat32_dirent_offset_clusters_high+1

        ;; Write sector 0 (with '.'/'..') exactly once.
        jsr write_non_mbr_sector
        jsr sd_wait_for_ready

        ;; Any remaining sectors in the cluster are written zeroed, each
        ;; exactly once.
        dec <dos_scratch_byte_1
        beq mkdir_cluster_written
        lda #1 : ldx #0 : ldy #0 : ldz #0
        jsr sdsector_add_uint32

        jsr dos_zero_sectorbuffer

mkdir_zero_rest_loop:
        jsr write_non_mbr_sector
        jsr sd_wait_for_ready
        dec <dos_scratch_byte_1
        beq mkdir_cluster_written
        lda #1 : ldx #0 : ldy #0 : ldz #0
        jsr sdsector_add_uint32
        bra mkdir_zero_rest_loop

mkdir_cluster_written:

        ;; 5. Mark the new cluster as an end-of-chain in both FATs,
        ;; before the dirent write below. The sector buffer is free at
        ;; this point (last used for '.'/'..' in step 4), so read the
        ;; FAT sector fresh.
        jsr dos_copy_zptempv32_and_read_fat_sector

        lda <(zptempv32+0)
        and #$7f
        sta <dos_scratch_byte_1         ;; entry index within the FAT sector, 0-127
        and #$3f
        asl
        asl
        tay                             ;; Y = byte offset within the chosen half
        lda <dos_scratch_byte_1
        and #$40
        beq mkdir_fatpatch_firsthalf

        lda #$f8
        sta sd_sectorbuffer+$100,y
        lda #$ff
        sta sd_sectorbuffer+$101,y
        sta sd_sectorbuffer+$102,y
        lda #$0f
        sta sd_sectorbuffer+$103,y
        bra mkdir_fatpatch_done

mkdir_fatpatch_firsthalf:
        lda #$f8
        sta sd_sectorbuffer,y
        lda #$ff
        sta sd_sectorbuffer+1,y
        sta sd_sectorbuffer+2,y
        lda #$0f
        sta sd_sectorbuffer+3,y

mkdir_fatpatch_done:
        jsr dos_write_sector_and_fat2_mirror

        ;; 6. Find free dirent slots in the parent directory and write
        ;; the new sub-directory's entry (attribute = directory, length 0).
        jsr dos_find_n_free_dirents
        bcs mkdir_havedirent
        +Checkpoint "trap_dos_mkdir <failure>"
        jmp generic_fail_from_error_code

mkdir_havedirent:
        jsr dos_write_lfn_and_shortentry

        ;; dirent: attributes/cluster/length, commit - shared with mkfile.
        lda #fs_fat32_attribute_isdirectory
        ldx #0
        jsr dos_write_dirent_common

        +Checkpoint "trap_dos_mkdir <success>"
        jmp return_from_trap_with_success

;; Zeroes the whole 512-byte sd_sectorbuffer.
dos_zero_sectorbuffer:
        ldy #0
-	lda #0
        sta sd_sectorbuffer,y
        sta sd_sectorbuffer+$100,y
        iny
        bne -
        rts

;; ---- trap_dos_rmdir ----

trap_dos_rmdir:
        ;; Removes an empty sub-directory from the current directory.
        ;;
        ;; Precondition: filename already set via hyppo_setname.
        ;; Errors: dos_errorcode_not_a_directory if the named entry isn't
        ;; a directory; dos_errorcode_directory_not_empty if it contains
        ;; anything besides '.' and '..'.
        ;;
        ;; Example:
        ;;   ; Set the target directory's name first via hyppo_setname (A=$2E).
        ;;   LDA #$10 : STA $D640 : CLV : BCC error
        jsr dos_findfile
        bcs rmdir_gotfile
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp generic_fail_from_error_code

rmdir_gotfile:
        lda dos_dirent_type_and_attribs
        and #fs_fat32_attribute_isdirectory
        bne rmdir_is_a_directory
        lda #dos_errorcode_not_a_directory
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp mkfile_fail_with_a

rmdir_is_a_directory:
        ;; Temporarily point "cwd" at the target directory so the
        ;; existing dos_opendir/dos_readdir machinery can scan it for
        ;; emptiness.
        jsr rmdir_save_cwd

        lda dos_dirent_cluster+0
        sta dos_disk_cwd_cluster+0
        lda dos_dirent_cluster+1
        sta dos_disk_cwd_cluster+1
        lda dos_dirent_cluster+2
        sta dos_disk_cwd_cluster+2
        lda dos_dirent_cluster+3
        sta dos_disk_cwd_cluster+3

        jsr dos_opendir_save_current_fd
        jsr dos_opendir
        bcs rmdir_target_opened
        jsr dos_opendir_restore_current_fd
        jsr rmdir_restore_cwd
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp return_from_trap_with_failure

rmdir_target_opened:
rmdir_scanloop:
        jsr dos_readdir
        bcs rmdir_gotentry

        ;; readdir failed: per its documented error table, $85 invalid
        ;; cluster means "read past the end of the directory" - i.e.
        ;; genuinely empty (not dos_errorcode_eof, which is a different,
        ;; file-read-oriented code). Anything else is a real error that
        ;; must be propagated (not silently treated as "empty, ok to
        ;; delete").
        lda dos_error_code
        cmp #dos_errorcode_invalid_cluster
        beq rmdir_scan_done
        pha
        jsr rmdir_close_and_restore
        pla
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp mkfile_fail_with_a

rmdir_gotentry:
        ;; dos_dirent_shortfilename is the raw, space-padded 11-byte
        ;; on-disk short name, distinct from the reconstructed
        ;; dos_dirent_longfilename: '.' is ".          " and '..' is
        ;; "..         ".
        lda dos_dirent_shortfilename+0
        cmp #$2e
        bne rmdir_notempty
        lda dos_dirent_shortfilename+1
        cmp #$2e
        beq rmdir_scanloop
        cmp #$20
        beq rmdir_scanloop

rmdir_notempty:
        jsr rmdir_close_and_restore
        lda #dos_errorcode_directory_not_empty
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp mkfile_fail_with_a

rmdir_scan_done:
        jsr rmdir_close_and_restore

        ;; Empty - re-find the target in the (now-restored) parent
        ;; directory. dos_requested_filename is untouched by the scan
        ;; above (dos_readdir doesn't do name matching), so this locates
        ;; the same entry and freshly populates dos_direntstart_* ready
        ;; for removal. Marking a directory's own dirent deleted and
        ;; freeing its cluster chain is mechanically identical to
        ;; removing a file's, so this just reuses dos_rmfile directly.
        jsr dos_findfile
        bcs rmdir_relocated
        +Checkpoint "trap_dos_rmdir <failure>"
        jmp return_from_trap_with_failure

rmdir_relocated:
        jsr dos_rmfile
        +Checkpoint "trap_dos_rmdir <success or failure - see carry>"
        jmp return_from_trap_with_carry_flag

rmdir_close_and_restore:
        jsr dos_closefile_and_restore_current_fd
        jmp rmdir_restore_cwd

;; ---- trap_dos_opendir ----

trap_dos_opendir:

        ;; X = File descriptor
        ;; Y = Page of memory to write dirent into

        ;; Open the current working directory for iteration.
        ;;
        jsr dos_opendir
        bcs tdod1

        ;; Something has gone wrong. Assume dos_opendir will
        ;; have set error code
        ;;
generic_fail_from_error_code:
        lda dos_error_code
        jmp return_from_trap_with_failure

tdod1:
        ;; Directory opened ok.
        ;;
        jmp return_from_trap_with_success_and_file_descriptor_in_a

;; ---- trap_dos_readdir ----

trap_dos_readdir:

        ;; Read next directory entry from file descriptor $XX
        ;; Return dirent structure to $YY00
        ;; in first 32KB of mapped address space

        +Checkpoint "trap_dos_readdir"

        jsr sd_map_sectorbuffer

        ;; Get offset to current file descriptor
        ;; (we can't use X register, as has been clobbered in the jump
        ;; table dispatch code)
        ;;
        ldx hypervisor_x
        stx dos_current_file_descriptor

        jsr dos_get_file_descriptor_offset
        bcc tdrd1
        sta dos_current_file_descriptor_offset

        jsr dos_readdir
        bcc tdrd1

        ;; Read the directory entry, now copy it to userland
        ;;
        jsr hypervisor_setup_copy_region
        bcc tdrd1

        ;; We can now copy the bytes of the dirent to user-space
        ;;
        ldy #dos_dirent_structure_length-1
tdrd2:
        ;; This loop actually copies the whole dirent.
        ;; XXX dos_dirent_longfilename must be first in the dirent structure
        lda dos_dirent_longfilename,y
        sta (<hypervisor_userspace_copy_vector),y
        dey
        bpl tdrd2

        +Checkpoint "trap_dos_readdir <success>"

        jmp return_from_trap_with_success

;;         ========================

tdrd1:
        +Checkpoint "trap_dos_readdir <failure>"

        bra generic_fail_from_error_code

;; ---- trap_dos_closedir ----

trap_dos_closedir:
        jmp trap_dos_closefile

;; ---- trap_dos_openfile ----


trap_dos_openfile:

        ;; Opens file in current dirent structure
        ;; XXX - This means we must preserve the dirent struct when
        ;; context-switching to avoid a race-condition

        jsr dos_openfile
        bcc tdof1

        +Checkpoint "trap_dos_openfile <success>"

        jmp return_from_trap_with_success_and_file_descriptor_in_a

tdof1:
        +Checkpoint "trap_dos_openfile <failure>"

        bra generic_fail_from_error_code

;; ---- trap_dos_readfile ----

trap_dos_readfile:
        jsr dos_readfile
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_writefile ----

trap_dos_writefile:
        jsr dos_writefile
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_mkfile ----

trap_dos_mkfile:

        ;; XXX Filename must already be set.
        ;; XXX Must be a file in the current directory only.
        ;; XXX Can only create normal files, not directories
        ;;     (change attribute after).
        ;; XXX Allocates 512KB at a time, i.e., a full FAT sector's
        ;;     worth of clusters.
        ;; XXX Allocates a contiguous block, so that D81s etc can
        ;;     be created, and guaranteed contiguous on the storage,
        ;;     so that they can be mounted.
        ;; XXX Size of file specified in $ZZYYXX, i.e., limit of 16MB.
        ;; XXX Doesn't handle full file systems (or ones without enough space
        ;;     free properly. Should check candidate cluster number is not too
        ;;     high, and abort if it is.

        ;; First, make sure the file doesn't already exist
        jsr dos_findfile
        bcc +
        ;; File exists, so abort
        lda #dos_errorcode_file_exists
        jmp mkfile_fail_with_a
+

        ;; Build the short name and work out how many LFN pieces (if
        ;; any) it needs, before allocating anything.
        jsr dos_analyze_name_or_fail

        ;; We need 1 FAT sector per 512KB of data.
        ;; I.e., shift ZZ right by three bits to get number
        ;; of empty FAT sectors we need to indicate sufficient space.
        lda hypervisor_z
        lsr
        lsr
        lsr
        clc
        adc #$01
        sta <dos_scratch_byte_1

        ;; Now go looking for empty FAT sectors
        ;; Start at cluster 128, and add 128 each time to step through
        ;; them.
        ;; This skips the first sector of FAT, which always has some used
        ;; bits, and ensures we can allocate on a whole sector basis.
        lda #128
        sta <(zptempv32+0)
        lda #$00
        sta <(zptempv32+1)
        sta <(zptempv32+2)
        sta <(zptempv32+3)

        ;; Initially 0 empty pages found
        lda #0
        sta <dos_scratch_byte_2

        jsr sd_map_sectorbuffer

find_empty_fat_page_loop:

        jsr dos_copy_zptempv32_to_current_cluster

        jsr read_fat_sector_for_cluster

        ;; Is the page empty
        ldx #0
-	lda sd_sectorbuffer,x
        bne +
        lda sd_sectorbuffer+$100,x
        bne +

        inx
        bne -
+

        ;; Z=1 if FAT sector all unallocated, Z=0 otherwise
        beq fat_sector_is_empty

        ;; Reset empty FAT sector counter
        lda #0
        sta <dos_scratch_byte_2
        jmp +

fat_sector_is_empty:
        inc <dos_scratch_byte_2
        lda <dos_scratch_byte_2
        cmp <dos_scratch_byte_1
        beq found_enough_contiguous_free_space
+
        ;; Need to find another
        lda #$80
        jsr dos_add_a_to_zptempv32

mkfile_check_end_of_fs:
        ;; Stop when the search reaches the end of the file system.
        ;;
        ;; Without this the loop runs off the end of the FAT, reads
        ;; whatever follows it, accepts the first sectors that happen to
        ;; read as blank, and allocates clusters that do not exist. The
        ;; file is then created at its full length with a chain that
        ;; cannot be attached, and writing to it puts data outside the
        ;; file system altogether - so the failure is silent at creation
        ;; and destructive afterwards.
        ;;
        ;; Unsigned 32-bit compare: cluster >= cluster_count means we are
        ;; past the end. Testing equality alone, as the check in
        ;; dos_write.asm does, is not enough here because this walks 128
        ;; clusters at a stride and can step straight over the last one.
        ;;
        ;; dos_disk_table_offset is already valid: dos_findfile above and
        ;; read_fat_sector_for_cluster in the loop both work through the
        ;; current disk.
        ldx dos_disk_table_offset
        sec
        lda <(zptempv32+0)
        sbc dos_disk_table + fs_fat32_cluster_count + 0,x
        lda <(zptempv32+1)
        sbc dos_disk_table + fs_fat32_cluster_count + 1,x
        lda <(zptempv32+2)
        sbc dos_disk_table + fs_fat32_cluster_count + 2,x
        lda <(zptempv32+3)
        sbc dos_disk_table + fs_fat32_cluster_count + 3,x
        bcc +
        lda #dos_errorcode_no_space
        jmp mkfile_fail_with_a
+

        bra find_empty_fat_page_loop

found_enough_contiguous_free_space:

        ;; Space begins <dos_scratch_byte_2 FAT sectors before here,
        ;; so rewind back to there by taking $80 away for each count.
        dec <dos_scratch_byte_2

-	lda <dos_scratch_byte_2
        beq +
        lda <(zptempv32+0)
        sec
        sbc #$80
        sta <(zptempv32+0)
        lda <(zptempv32+1)
        sbc #0
        sta <(zptempv32+1)
        lda <(zptempv32+2)
        sbc #0
        sta <(zptempv32+2)
        lda <(zptempv32+3)
        sbc #0
        sta <(zptempv32+3)
        dec <dos_scratch_byte_2
        jmp -
+
        ;; zptempv32 now contains the starting cluster for our file

        ;; Find (N+1) consecutive free dirent slots: N LFN pieces
        ;; (zptempv32b+0) plus the short entry itself.
        jsr dos_find_n_free_dirents
        bcs +
        ;; Couldn't find enough free dirents, so return whatever error
        ;; we have been indicated.
        rts
+

        ;; Save the directory sector's address - the dirent write is
        ;; deferred until after the FAT-chain loop below, which reuses
        ;; the same sector buffer for FAT reads/writes.
        ldx #3
-	lda $d681,x
        sta <zptempv2,x
        dex
        bpl -

        ;; Update both FATs to make the allocation

        ;; Work out how many sectors full of incrementing clusters
        ;; we need.
        lda <dos_scratch_byte_1
        sta <dos_scratch_byte_2

        ;; Save the starting cluster too - the loop below walks the
        ;; chain in place, so zptempv32 ends up holding the last
        ;; cluster, not the first. Relocate zptempv32b+0 (the LFN piece
        ;; count, needed again after this loop) into <dos_scratch_byte_1
        ;; first, freeing zptempv32b as the save slot.
        lda <zptempv32b
        sta <dos_scratch_byte_1
        ldx #3
-	lda <zptempv32,x
        sta <zptempv32b,x
        dex
        bpl -
mkfile_fat_write_loop:
        ;; Get the (currently empty) sector
        jsr dos_copy_zptempv32_and_read_fat_sector

        ;; Update cluster number and write it into the field
        ldy #0
-
        lda #1 : jsr dos_add_a_to_zptempv32
        lda <(zptempv32+0) : sta sd_sectorbuffer,y : iny
        lda <(zptempv32+1) : sta sd_sectorbuffer,y : iny
        lda <(zptempv32+2) : sta sd_sectorbuffer,y : iny
        lda <(zptempv32+3) : sta sd_sectorbuffer,y : iny
        bne -
-
        lda #1 : jsr dos_add_a_to_zptempv32
        lda <(zptempv32+0) : sta sd_sectorbuffer+$100,y : iny
        lda <(zptempv32+1) : sta sd_sectorbuffer+$100,y : iny
        lda <(zptempv32+2) : sta sd_sectorbuffer+$100,y : iny
        lda <(zptempv32+3) : sta sd_sectorbuffer+$100,y : iny
        bne -

        ;; If the last FAT sector for this file, then
        ;; the last cluster entry should be $0FFFFFF8 to mark
        ;; end of file.
        lda <dos_scratch_byte_2
        cmp #1
        bne +
        lda #$F8
        sta $dffc
        lda #$FF
        sta $dffd
        sta $dffe
        lda #$0F
        sta $dfff
+
        ;; Write FAT sector to FAT1, then mirror to FAT2.
        jsr dos_write_sector_and_fat2_mirror

        ;; More FAT sectors to go?
        dec <dos_scratch_byte_2
        beq +
        bra mkfile_fat_write_loop
+

        ;; Restore the starting cluster and directory sector address,
        ;; and re-read that sector fresh before writing the new dirent.
        ldx #3
-	lda <zptempv32b,x
        sta <zptempv32,x
        dex
        bpl -
        lda <dos_scratch_byte_1
        sta <zptempv32b

        ldx #3
-	lda <zptempv2,x
        sta $d681,x
        dex
        bpl -
        jsr sd_readsector

        ;; Write the LFN pieces (if any) and the short entry's name
        ;; field. dos_scratch_vector ends up pointing at the short
        ;; entry's slot, ready for the attribute/cluster/length fields.
        jsr dos_write_lfn_and_shortentry

        ;; dirent: attributes/cluster/length, commit - shared with mkdir
        lda #$20 ;; Archive bit set
        ldx #1
        jsr dos_write_dirent_common

        ;; All done: File has been created.
        jmp return_from_trap_with_success

;; ---- trap_dos_closefile ----

trap_dos_closefile:

        ldx hypervisor_x
        stx dos_current_file_descriptor

        jsr dos_get_file_descriptor_offset
        bcc tdcf1
        sta dos_current_file_descriptor_offset
        jsr dos_closefile
        bcc tdcf1

        +Checkpoint "trap_dos_closefile <success>"

        jmp return_from_trap_with_success
tdcf1:
        +Checkpoint "trap_dos_closefile <failure>"

        jmp generic_fail_from_error_code

;; ---- trap_dos_seekfile ----


;;         ========================

trap_dos_seekfile:
        ;; Seeks to a given sector within the currently open file.
        ;;
        ;; Precondition: a file is currently open (hyppo_openfile) - same
        ;; implicit "current file" convention as hyppo_readfile /
        ;; hyppo_writefile (no FD register input; operates on whichever
        ;; file was last opened).
        ;;
        ;; Inputs: X/Y/Z = 24-bit target sector number within the file
        ;; (LSB/mid/MSB), matching hyppo_mkfile's $ZZYYXX convention.
        ;;
        ;; Narrow contract, not a general random-access primitive: FAT32
        ;; cluster chains are singly-linked, so this always walks forward
        ;; from the start of the file, sector by sector. There is no
        ;; per-file-descriptor length tracking, so this does not
        ;; bounds-check against the file's real length - seeking past
        ;; the end fails naturally when the cluster chain runs out,
        ;; rather than with a dedicated end-of-file error.
        ;;
        ;; Example:
        ;;   ; Assume the file is already open (hyppo_openfile).
        ;;   LDX #$05             ; sector count, LSB
        ;;   LDY #$00             ; sector count, middle byte
        ;;   LDZ #$00             ; sector count, MSB
        ;;   LDA #$24 : STA $D640 : CLV : BCC error

        ;; Save the 24-bit target sector count in zptempv2/zptempp.
        stx <zptempv2
        sty <(zptempv2+1)
        stz <zptempp

        jsr dos_open_current_file
        bcs seekfile_atstart
        +Checkpoint "trap_dos_seekfile <failure>"
        jmp return_from_trap_with_carry_flag

seekfile_atstart:
seekfile_loop:
        lda <zptempv2
        ora <(zptempv2+1)
        ora <zptempp
        beq seekfile_done

        jsr dos_file_advance_to_next_sector
        bcs seekfile_decrement
        +Checkpoint "trap_dos_seekfile <failure>"
        jmp return_from_trap_with_carry_flag

seekfile_decrement:
        lda <zptempv2
        sec
        sbc #1
        sta <zptempv2
        lda <(zptempv2+1)
        sbc #0
        sta <(zptempv2+1)
        lda <zptempp
        sbc #0
        sta <zptempp
        bra seekfile_loop

seekfile_done:
        +Checkpoint "trap_dos_seekfile <success>"
        jmp return_from_trap_with_success

;; ---- trap_dos_rmfile ----

trap_dos_rmfile:
        jsr dos_rmfile
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_fstat ----

trap_dos_fstat:
        ;; Returns raw dirent info (short name, attributes, length, dates)
        ;; for the currently-located file.
        ;;
        ;; Precondition: hyppo_setname + hyppo_findfile first, to make the
        ;; target the "current" match.
        ;; Y: MSB of destination area for the raw 32-byte dirent.
        ;;
        ;; Example:
        ;;   ; Assume setname+findfile already located the target.
        ;;   LDY #$80             ; destination page for the result
        ;;   LDA #$28 : STA $D640 : CLV : BCC error
        jsr dos_fstat
        +Checkpoint "trap_dos_fstat <success or failure - see carry>"
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_rename ----

trap_dos_rename:
        ;; Renames an already-open file, or the currently-open directory
        ;; (an FD from hyppo_opendir - not an arbitrary named
        ;; subdirectory). A new name that fits 8.3 is written in place;
        ;; one that needs VFAT long-name pieces is relocated to fresh
        ;; free slots elsewhere in the directory instead (see
        ;; rename_lfn below), reusing the same LFN writer mkfile/mkdir
        ;; use. Either way the entry's attributes/dates/cluster/length
        ;; are preserved untouched - only the name changes.
        ;;
        ;; Precondition: like hyppo_writefile, this operates on an
        ;; already-open file descriptor: X = the FD (from hyppo_openfile,
        ;; or hyppo_opendir to rename the directory itself). Y = page of
        ;; a null-terminated buffer holding the new name (same
        ;; convention hyppo_setname itself uses for its input). For a
        ;; FILE FD specifically, cwd must still be whatever directory
        ;; it was opened from - files carry no ".." of their own, so
        ;; (unlike a directory FD) there's no way to re-derive their
        ;; parent if cwd has since changed.
        ;;
        ;; Errors: dos_errorcode_invalid_file_descriptor if X isn't an
        ;; open FD; dos_errorcode_file_exists if the new name already
        ;; exists; dos_errorcode_name_too_long if the new name is empty
        ;; or too long to ever reassemble (more than 5 LFN pieces, i.e.
        ;; over 65 characters); dos_errorcode_directory_full if it needs
        ;; LFN pieces and there's no room left for them; dos_errorcode_
        ;; file_not_found if asked to rename the root directory (it has
        ;; no entry of its own to rename), or if the FD's own entry can
        ;; no longer be located (e.g. a file whose cwd precondition
        ;; above wasn't met).
        ;;
        ;; Example:
        ;;   ; Assume the file is already open (hyppo_openfile) with its FD in X.
        ;;   LDX openfile_fd
        ;;   LDY #$80             ; page of a nul-terminated new-name buffer
        ;;   LDA #$2A : STA $D640 : CLV : BCC error

        ;; Pull the new name out of userland into dos_requested_filename,
        ;; via the exact same safety-checked path hyppo_setname uses.
        jsr dos_setname_from_userspace
        lbcc rename_fail_alreadyset
rename_have_name:

        ;; Save the real cwd - restored before every return below (we
        ;; temporarily repoint it at the parent directory we need to
        ;; search, reusing the existing dos_opendir/dos_readdir
        ;; machinery on it, same trick hyppo_getcwd/hyppo_rmdir use).
        ldx #3
-       lda dos_disk_cwd_cluster,x
        sta <dos_rename_saved_cwd,x
        dex
        bpl -

        ldx hypervisor_x
        stx dos_current_file_descriptor
        jsr dos_get_fd_offset_or_fail

        ;; Stash the FD's mode in Z (survives the loop below, unlike
        ;; X) - cheaper than calling dos_get_fd_offset_or_fail again
        ;; afterwards to recompute X from scratch.
        lda dos_file_descriptors+dos_filedescriptor_offset_mode,x
        taz

        ;; What we're searching for is always this FD's own cluster.
        ldy #0
-       lda dos_file_descriptors+dos_filedescriptor_offset_startcluster,x
        sta dos_dfdcbc_target,y
        inx
        iny
        cpy #4
        bne -

        ;; The directory branch below also needs this in zptempv32:
        ;; dos_cluster_is_root and dos_find_parent_of_cluster both read
        ;; it as their input (the files branch never reaches either, so
        ;; this is harmless-but-unused work for a file FD).
        ldx #3
-       lda dos_dfdcbc_target,x
        sta <zptempv32,x
        dex
        bpl -

        ;; Where we're searching depends on whether the FD is a file or
        ;; a directory. dos_filemode_directoryaccess ($80) is the only
        ;; mode a resting FD can have with the high bit set (readonly
        ;; is $00), so a sign check is equivalent to and cheaper than
        ;; comparing against the constant.
        tza
        ;; File: cwd is already its parent - renaming an open file
        ;; requires cwd to still be whatever directory it was opened
        ;; from (files carry no ".." of their own to derive it live).
        bpl rename_have_parent

        ;; Directory: derive its parent live via its own ".." entry.
        ;; Root has no ".." - can't rename it.
        jsr dos_cluster_is_root
        bcc rename_not_root
        lda #dos_errorcode_file_not_found
        +Checkpoint "trap_dos_rename <failure>"
        jmp mkfile_fail_with_a
rename_not_root:
        jsr dos_find_parent_of_cluster

rename_have_parent:
        jsr dos_find_dirent_in_cwd_by_cluster
        bcs rename_found
        pha             ;; rename_restore_cwd clobbers A - save the error code
        jsr rename_restore_cwd
        pla
        +Checkpoint "trap_dos_rename <failure>"
        jmp mkfile_fail_with_a

rename_found:
        ;; Protect our own dirent position before the destination check
        ;; below runs its own findfile/readdir scan (which would
        ;; otherwise clobber dos_direntstart_*). cwd is still pointed
        ;; at our parent, which is exactly where the new name must not
        ;; already exist.
        jsr dos_save_direntstart_to_zptemp

        jsr dos_findfile
        bcc rename_destfree
        jsr rename_restore_cwd
        lda #dos_errorcode_file_exists
        +Checkpoint "trap_dos_rename <failure>"
        jmp mkfile_fail_with_a

rename_destfree:
        ;; Restore the saved position and locate its sector.
        jsr dos_restore_direntstart_from_zptemp
        jsr dos_goto_direntstart_and_point_scratch_vector

        jsr dos_analyze_name_for_dirent
        bcc rename_shortcopy_setup

        ;; Carry set: either a valid LFN piece count (relocate), or
        ;; $ff (name unusable - too long to ever reassemble, or empty).
        lda <zptempv32b
        cmp #$ff
        beq rename_name_too_long
        bra rename_lfn

        ;; Fits cleanly - overwrite the short-name field in place,
        ;; nothing else changes.
rename_shortcopy_setup:
        jsr dos_delete_preceding_lfn_pieces
        ldy #10
rename_shortcopy:
        lda dos_dirent_shortfilename,y
        sta (<dos_scratch_vector),y
        dey
        bpl rename_shortcopy

rename_commit:
        jsr write_non_mbr_sector
        jsr sd_wait_for_ready
        jsr rename_restore_cwd
        +Checkpoint "trap_dos_rename <success>"
        jmp return_from_trap_with_success

rename_name_too_long:
        jsr rename_restore_cwd
        lda #dos_errorcode_name_too_long
        +Checkpoint "trap_dos_rename <failure>"
        jmp mkfile_fail_with_a

rename_fail_alreadyset:
        +Checkpoint "trap_dos_rename <failure>"
        jmp return_from_trap_with_failure

;; New name doesn't fit 8.3 - relocate to N+1 fresh consecutive slots
;; elsewhere in the directory. dos_write_lfn_and_shortentry only fills
;; in the name fields (offsets 0-10); attributes/dates/cluster/length
;; (offsets 11-31) are saved from the old entry and copied verbatim.
rename_lfn:
        ;; dos_analyze_name_for_dirent (just called) may have gone
        ;; through dos_shortname_exists to check the new tilde-numbered
        ;; short name for collisions, which does its own directory scan
        ;; and clobbers the shared SD sector buffer dos_scratch_vector
        ;; still points into. dos_direntstart_* itself is untouched by
        ;; that scan, so re-derive dos_scratch_vector from it before
        ;; reading anything through it. Direct variant - must not
        ;; disturb this FD's own currentcluster/sectorincluster (the
        ;; caller may keep reading/writing this FD after the rename).
        jsr dos_goto_direntstart_direct_and_point_scratch_vector

        ldy #fs_fat32_dirent_offset_attributes
        ldx #0
rlfn_save_loop:
        lda (<dos_scratch_vector),y
        sta dos_rename_saved_dirent,x
        iny
        inx
        cpx #21
        bne rlfn_save_loop

        jsr dos_delete_preceding_lfn_pieces

        ;; Delete the old short entry.
        lda #$e5
        ldy #0
        sta (<dos_scratch_vector),y
        jsr write_non_mbr_sector
        jsr sd_wait_for_ready

        ;; zptempv32b+0 (LFN piece count) is still set from
        ;; dos_analyze_name_for_dirent above.
        jsr dos_find_n_free_dirents
        bcs rename_lfn_havedirent
        jsr rename_restore_cwd
        +Checkpoint "trap_dos_rename <failure>"
        jmp return_from_trap_with_failure

rename_lfn_havedirent:
        jsr dos_write_lfn_and_shortentry

        ldy #fs_fat32_dirent_offset_attributes
        ldx #0
rlfn_restore_loop:
        lda dos_rename_saved_dirent,x
        sta (<dos_scratch_vector),y
        iny
        inx
        cpx #21
        bne rlfn_restore_loop

        bra rename_commit

rename_restore_cwd:
        ldx #3
-       lda <dos_rename_saved_cwd,x
        sta dos_disk_cwd_cluster,x
        dex
        bpl -
        rts

;; ---- trap_dos_setname ----

trap_dos_setname:

        ;; read file name from any where in bottom 32KB of RAM, as mapped on entry
        ;; to the hypervisor (this prevents the user from setting the filename to some
        ;; piece of the hypervisor, and thus leaking hypervisor data to user-land if the
        ;; user were to later query the filename).

        +Checkpoint "trap_dos_setname"

        jsr dos_setname_from_userspace
        bcc tdsnfailure

        ;; setname succeeded
        ;;

        jmp return_from_trap_with_success

;;         ========================

tdsnfailure:
        ;; save the error code so a later trap_dos_geterrorcode will return it
        jmp mkfile_fail_with_a

;; ---- trap_dos_findfirst ----

trap_dos_findfirst:

        jsr dos_findfirst
        lbcs return_from_trap_with_success_and_file_descriptor_in_a
+	jmp return_from_trap_with_failure

;;         ========================

trap_dos_findnext:

        jsr dos_findnext
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_findfile ----

trap_dos_findfile:

        jsr dos_findfile
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_geterrorcode ----

trap_dos_geterrorcode:

        lda dos_error_code
        sta hypervisor_a

!if DEBUG_HYPPO {
        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty tdgec1+0
        stx tdgec1+1

        jsr checkpoint
        !8 0
        !text "dos_geterrorcode <=$"
tdgec1: !text "%%>"
        !8 0
}

        jmp return_from_trap_with_success

;; ---- trap_dos_setup_transfer_area ----

trap_dos_setup_transfer_area:

        jsr hypervisor_setup_copy_region

        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_cdrootdir ----

trap_dos_cdrootdir:
        ldx hypervisor_x
        jsr dos_cdroot
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_loadfile_attic ----

trap_dos_loadfile_attic:
        lda #$08  		; Set address to $8xxxxxx to access attic RAM
        !8 $2c 		; BIT $xxxx to skip lda #$00 below
        ;; FALL THROUGH

trap_dos_loadfile:

        ;; Only allow loading into lower 16MB to avoid possibility of writing
        ;; over hypervisor
        ;;
        lda #$00
        sta <(dos_file_loadaddress+3)

        lda hypervisor_x
        sta <dos_file_loadaddress
        lda hypervisor_y
        sta <(dos_file_loadaddress+1)
        lda hypervisor_z
        sta <(dos_file_loadaddress+2)

        jsr dos_readfileintomemory
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_d81attach0 ----

trap_dos_d81attach0:

        +Checkpoint "trap_dos_d81attach0"

        ldx #$00
        jsr dos_attach
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_d81detach ----

trap_dos_d81detach:

        +Checkpoint "trap_dos_d81detach"

        ldx #%11000010          ;; detach both drives, don't attach real drives
        jsr dos_attach

        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_d81write_en ----

trap_dos_d81write_en:

        jsr dos_d81write_en
        jmp return_from_trap_with_carry_flag

dos_d81write_en:
        lda $d68b
        and #$03
        cmp #$03
        bne td81we1
        ora #$04
        sta $d68b

        ;; Mark disk image write-enabled in proces descriptor
        lda currenttask_d81_image0_flags
        ora #d81_image_flag_write_en

        sec
        rts

td81we1:
        ;; No disk image mounted
        ;;

        +Checkpoint "dos_d81writ_en-FAIL"

        lda #dos_errorcode_no_such_disk
        sta dos_error_code
        clc
        rts

;; ---- trap_dos_d81attach1 ----

trap_dos_d81attach1:

        +Checkpoint "trap_dos_d81attach1"

        ldx #$01
        jsr dos_attach
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_get_proc_desc ----

trap_dos_get_proc_desc:
        jsr hypervisor_setup_copy_region
        bcc @bad
        ldy #0
@copyloop:
        lda currenttask_block,y
        sta (<hypervisor_userspace_copy_vector),y
        iny
        bne @copyloop
        sec
@bad:
        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_attach ----

trap_dos_attach:

        +Checkpoint "trap_dos_attach"

        ldx hypervisor_x
        jsr dos_attach

        jmp return_from_trap_with_carry_flag

;; ---- trap_dos_filedate ----

;; BG: the following are placeholders for the future development

trap_dos_filedate:
trap_dos_gettasklist:
trap_dos_sendmessage:
trap_dos_receivemessage:
trap_dos_writeintotask:
trap_dos_readoutoftask:
trap_dos_terminateothertask:
trap_dos_create_task_native:
trap_dos_load_into_task:
trap_dos_create_task_c64:
trap_dos_create_task_c65:
trap_dos_exit_and_switch_to_task:
trap_dos_switch_to_task:
trap_dos_exit_task:

        jmp invalid_subfunction;;

;; ---- trap_task_toggle_rom_writeprotect ----

trap_task_toggle_rom_writeprotect:
        lda hypervisor_feature_enables
        eor #$04
        sta hypervisor_feature_enables
returnFeatureState:
        ;; Pass updated state back out to caller, so they know the result
        sta hypervisor_a
        jmp return_from_trap_with_success

;; ---- trap_task_toggle_force_4502 ----

trap_task_toggle_force_4502:
        lda hypervisor_feature_enables
        eor #$20
        sta hypervisor_feature_enables
        bra returnFeatureState

;; ---- trap_task_get_mapping ----

trap_task_get_mapping:
        jsr hypervisor_setup_copy_region
        bcc @bad
        ldy #5
@copyloop:
        lda hypervisor_maplohi,y
        sta (<hypervisor_userspace_copy_vector),y
        dey
        bpl @copyloop
        sec
@bad:
        jmp return_from_trap_with_carry_flag

;; ---- trap_task_set_mapping ----

trap_task_set_mapping:
        jsr hypervisor_setup_copy_region
        bcc @bad2
        ldy #5
@copyloop2:
        lda (<hypervisor_userspace_copy_vector),y
        sta hypervisor_maplohi,y
        dey
        bpl @copyloop2
        sec
@bad2:
        jmp return_from_trap_with_carry_flag


;; ============================================================
;; SHARED HELPERS (used by 2+ different trap handlers above,
;; or a private sub-helper of one that is)
;; ============================================================

;; Copies a null-terminated name from the caller's userspace (page
;; hypervisor_y, validated by hypervisor_setup_copy_region) into
;; dos_requested_filename. Carry/A convey success/failure exactly as
;; dos_setname itself does - shared by trap_dos_setname and
;; trap_dos_rename, which both need this same "pull a name out of
;; userland" step.
dos_setname_from_userspace:
        jsr hypervisor_setup_copy_region
        bcc dsnfu_done
        ldx <hypervisor_userspace_copy_vector
        ldy <(1+hypervisor_userspace_copy_vector)
        jsr dos_setname
dsnfu_done:
        rts

;;         ========================

;; zptempv32 (32-bit) += A, with carry propagated through all 4 bytes.
dos_add_a_to_zptempv32:
        clc
        adc <(zptempv32+0)
        sta <(zptempv32+0)
        lda <(zptempv32+1)
        adc #0
        sta <(zptempv32+1)
        lda <(zptempv32+2)
        adc #0
        sta <(zptempv32+2)
        lda <(zptempv32+3)
        adc #0
        sta <(zptempv32+3)
        rts

;; Write the pending sector, wait for completion, then mirror it to FAT2.
dos_write_sector_and_fat2_mirror:
        jsr write_non_mbr_sector
        jsr sd_wait_for_ready

;; Mirror the FAT1 sector at $d681-4 to FAT2 and write it there too.
dos_write_fat2_mirror:
        lda dos_disk_table_offset
        ora #fs_fat32_length_of_fat
        tay
        ldx #0
dwf2m_loop:
        lda $d681,x
        adc dos_disk_table,y
        iny
        inx
        cpx #4
        bne dwf2m_loop
        jsr write_non_mbr_sector
        jmp sd_wait_for_ready

;; <dos_current_cluster = zptempv32.
dos_copy_zptempv32_to_current_cluster:
        ldx #3
dctcc_loop:
        lda <zptempv32,x
        sta <dos_current_cluster,x
        dex
        bpl dctcc_loop
        rts

dos_copy_zptempv32_and_read_fat_sector:
        jsr dos_copy_zptempv32_to_current_cluster
        jmp read_fat_sector_for_cluster

dos_copy_zptempv32_and_cluster_to_sector:
        jsr dos_copy_zptempv32_to_current_cluster
        jmp dos_cluster_to_sector

;; dirent: attributes (A), cluster (zptempv32) and length, commit.
;; X=0 writes zero length (mkdir); X<>0 writes hypervisor_x/y/z (mkfile).
dos_write_dirent_common:
        ldy #fs_fat32_dirent_offset_attributes
        sta (<dos_scratch_vector),y
        ldy #fs_fat32_dirent_offset_clusters_low
        lda <(zptempv32+0)
        sta (<dos_scratch_vector),y
        iny
        lda <(zptempv32+1)
        sta (<dos_scratch_vector),y
        ldy #fs_fat32_dirent_offset_clusters_high
        lda <(zptempv32+2)
        sta (<dos_scratch_vector),y
        iny
        lda <(zptempv32+3)
        sta (<dos_scratch_vector),y
        ldy #fs_fat32_dirent_offset_file_length
        cpx #0
        beq dwdc_zero_length
        lda hypervisor_x
        sta (<dos_scratch_vector),y
        iny
        lda hypervisor_y
        sta (<dos_scratch_vector),y
        iny
        lda hypervisor_z
        sta (<dos_scratch_vector),y
        iny
        lda #0
        sta (<dos_scratch_vector),y
        bra dwdc_commit
dwdc_zero_length:
        lda #0
        ldx #4
-	sta (<dos_scratch_vector),y
        iny
        dex
        bne -
dwdc_commit:
        jsr write_non_mbr_sector
        jmp sd_wait_for_ready

;; dos_opendir always reassigns dos_current_file_descriptor/_offset to
;; whatever scratch FD it allocates for its own directory scan. Callers
;; like dos_shortname_exists/dos_find_n_free_dirents open a directory
;; purely as an internal implementation detail mid-trap, so they must
;; save/restore these two bytes around it - otherwise a trap like
;; rename, whose documented contract is that the caller's own FD stays
;; "current" afterwards (readfile/writefile/seekfile have no explicit
;; FD parameter), would silently leave the current FD pointing at the
;; scratch slot instead, which dos_closefile has since freed.
dos_opendir_save_current_fd:
        lda dos_current_file_descriptor
        sta dos_saved_current_fd
        lda dos_current_file_descriptor_offset
        sta dos_saved_current_fd_offset
        rts

dos_opendir_restore_current_fd:
        lda dos_saved_current_fd
        sta dos_current_file_descriptor
        lda dos_saved_current_fd_offset
        sta dos_current_file_descriptor_offset
        rts

;; Closes the scratch directory FD opened by an internal dos_opendir,
;; then restores the caller's own current-FD pointer bytes (which that
;; dos_opendir clobbered). Shared epilogue for the internal directory
;; scans.
dos_closefile_and_restore_current_fd:
        jsr dos_closefile
        bra dos_opendir_restore_current_fd

;; Unified directory scanner shared by two callers. The mode is carried
;; in <dos_dirscan_target: nonzero = "find N+1 free slots", zero =
;; "does short name exist". The directory is opened as an internal
;; implementation detail mid-trap, so dos_current_file_descriptor/
;; _offset are saved and restored so the caller's own FD stays
;; "current" afterwards. Uses zptempp2 as the walk pointer; only the
;; find-free mode touches zptempp/zptempv32b+1.
;;
;; dos_find_n_free_dirents: finds zptempv32b+0 + 1 consecutive
;; free/deleted dirent slots (N LFN pieces plus the short entry) within
;; a single sector. Returns carry set and dos_scratch_vector at the
;; first slot, or carry clear + dos_error_code=directory_full.
;;
;; dos_shortname_exists: returns carry SET if the 11 bytes in
;; dos_dirent_shortfilename already exist as some entry's short name in
;; the current directory (collision), CLEAR if not. Skips deleted
;; entries ($e5) and LFN pieces. Must NOT touch zptempv2/zptempp, since
;; ran_build_tilde's retry loop keeps its digit-position/current-number
;; state in them across this call (the find-free code that uses zptempp
;; is skipped in this mode).
dos_find_n_free_dirents:
        lda <zptempv32b
        clc
        adc #1
        sta <dos_dirscan_target          ;; target run length (mode A, nonzero)
        bra usc_open_and_scan

dos_shortname_exists:
        lda #0
        sta <dos_dirscan_target          ;; mode B marker

usc_open_and_scan:
        jsr dos_opendir_save_current_fd
        jsr dos_opendir
        jsr sd_map_sectorbuffer

usc_sector_loop:
        jsr dos_file_read_current_sector
        lda #$de
        sta <(zptempp2+1)
        lda #0
        sta <zptempp2                      ;; scan pointer, walked forward 32 at a time
        sta <(zptempv32b+1)              ;; clear run length (A still 0); unused in mode B

usc_scan:
        lda <dos_dirscan_target
        beq usc_test_shortname

        ;; ------- mode A: find a run of N+1 consecutive free slots -------
        ldy #0
        lda (<zptempp2),y
        cmp #$00                         ;; vacant
        beq usc_a_isfree
        cmp #$e5                         ;; deleted
        beq usc_a_isfree
        lda #0                           ;; not free - reset run length
        sta <(zptempv32b+1)
        bra usc_next
usc_a_isfree:
        lda <(zptempv32b+1)
        bne usc_a_continuing
        lda <zptempp2                     ;; remember run-start pointer
        sta <zptempp
        lda <(zptempp2+1)
        sta <(zptempp+1)
usc_a_continuing:
        inc <(zptempv32b+1)
        lda <(zptempv32b+1)
        cmp <dos_dirscan_target
        bcs usc_a_found
        bra usc_next
usc_a_found:
        lda <zptempp
        sta <dos_scratch_vector
        lda <(zptempp+1)
        sta <(dos_scratch_vector+1)
        bra usc_found

        ;; ------- mode B: does the short name already exist? -------
usc_test_shortname:
        ldy #0
        lda (<zptempp2),y
        cmp #$e5                         ;; deleted (a never-used $00 slot isn't
        beq usc_next                     ;; special-cased here, matching find-free)
        ldy #fs_fat32_dirent_offset_attributes
        lda (<zptempp2),y
        cmp #$0f
        beq usc_next                     ;; LFN piece, not a short entry
        ldy #10
usc_b_cmp:
        lda (<zptempp2),y
        cmp dos_dirent_shortfilename,y
        bne usc_next
        dey
        bpl usc_b_cmp

        ;; all 11 bytes matched
        bra usc_found

usc_next:
        lda <zptempp2
        clc
        adc #32
        sta <zptempp2
        bcc +
        inc <(zptempp2+1)
+       lda <(zptempp2+1)
        cmp #$e0
        bcc usc_scan

        ;; No target in this sector - any more sectors in this directory?
        jsr dos_file_advance_to_next_sector
        bcs usc_sector_loop

        ;; Ran out of directory.
        lda <dos_dirscan_target
        beq usc_notfound
        ;; mode A: directory full.
        ;; XXX Later we should allow extending the directory by adding another cluster.
        jsr dos_closefile_and_restore_current_fd
        lda #dos_errorcode_directory_full
        sta dos_error_code
        clc
        rts

usc_notfound:                            ;; mode B: no collision
        jsr dos_closefile_and_restore_current_fd
        clc
        rts

usc_found:
        ;; Close the directory FD opened by dos_opendir above.
        jsr dos_closefile_and_restore_current_fd
        sec
        rts

;; Writes the LFN pieces (if any) then the short entry's name field at
;; dos_scratch_vector. Attributes/cluster/length are left for the
;; caller. Returns with dos_scratch_vector at the short entry's slot.
dos_write_lfn_and_shortentry:
        lda <zptempv32b
        beq dwls_short_entry_only        ;; N == 0, nothing precedes it

        sta <(zptempv32b+1)               ;; remaining piece number, counts N..1
        lda #$40                          ;; 0x40 marks the first physical entry
        sta <(zptempv32b+3)

        ;; Checksum only depends on the (already-final) short name, so
        ;; compute it once and reuse for every piece.
        jsr compute_lfn_checksum
        sta <(zptempv32b+2)

dwls_piece_loop:
        ldy #31
        lda #0
dwls_erase:
        sta (<dos_scratch_vector),y
        dey
        bpl dwls_erase

        lda <(zptempv32b+1)
        ora <(zptempv32b+3)
        ldy #fs_fat32_dirent_offset_lfn_part_number
        sta (<dos_scratch_vector),y
        lda #0
        sta <(zptempv32b+3)                ;; only the first physical piece gets 0x40

        ldy #fs_fat32_dirent_offset_attributes
        lda #$0f
        sta (<dos_scratch_vector),y
        ldy #fs_fat32_dirent_offset_lfn_checksum
        lda <(zptempv32b+2)
        sta (<dos_scratch_vector),y

        ;; source char index for this piece = (piece_number-1)*13
        lda <(zptempv32b+1)
        sec
        sbc #1
        tax
        lda lfn_piece_offsets,x
        tax
        lda #0
        sta <zptempv2                       ;; "past name's end" flag, fresh per piece

        ldy #fs_fat32_dirent_offset_lfn_part1_start
        ldz #fs_fat32_dirent_offset_lfn_part1_chars
        jsr dwls_write_run
        ldy #fs_fat32_dirent_offset_lfn_part2_start
        ldz #fs_fat32_dirent_offset_lfn_part2_chars
        jsr dwls_write_run
        ldy #fs_fat32_dirent_offset_lfn_part3_start
        ldz #fs_fat32_dirent_offset_lfn_part3_chars
        jsr dwls_write_run

        ;; advance write pointer to the next slot
        lda <dos_scratch_vector
        clc
        adc #32
        sta <dos_scratch_vector
        bcc +
        inc <(dos_scratch_vector+1)
+
        dec <(zptempv32b+1)
        bne dwls_piece_loop

dwls_short_entry_only:
        ;; erase + pad the short entry's name field, then copy the
        ;; already-built short name in.
        ldy #10
        lda #$20
dwls_pad_loop:
        sta (<dos_scratch_vector),y
        dey
        bpl dwls_pad_loop

        ldy #10
dwls_copy_short:
        lda dos_dirent_shortfilename,y
        sta (<dos_scratch_vector),y
        dey
        bpl dwls_copy_short
        rts

;; X = source char index, Y = entry offset, Z = char count. Writes
;; UTF-16LE chars until the name ends, then NUL, then 0xFFFF padding.
dwls_write_run:
dwlsr_loop:
        lda <zptempv2
        bne dwlsr_pad
        cpx dos_requested_filename_len
        bcc dwlsr_gotchar
        ;; name's end: write NUL terminator, then flag padding for the rest.
        lda #0
        inc <zptempv2
        bra dwlsr_store
dwlsr_gotchar:
        lda dos_requested_filename,x
        jsr toupper
        inx
dwlsr_store:
        sta (<dos_scratch_vector),y
        iny
        lda #0
        sta (<dos_scratch_vector),y
        iny
        bra dwlsr_cont
dwlsr_pad:
        lda #$ff
        sta (<dos_scratch_vector),y
        iny
        sta (<dos_scratch_vector),y
        iny
dwlsr_cont:
        dez
        bne dwlsr_loop
        rts

;;         ========================

read_fat_sector_for_cluster:
        jsr dos_cluster_to_fat_sector

        ;; Now read the sector
        ldx #3
-       lda <dos_current_cluster,x
        sta $d681,x
        dex
        bpl -
        jmp sd_readsector

;; Saves/restores dos_disk_cwd_cluster in zptempv2+zptempp, so callers
;; can temporarily repoint "cwd" at some other directory, then put the
;; real cwd back afterwards.
rmdir_save_cwd:
        lda dos_disk_cwd_cluster+0
        sta <zptempv2
        lda dos_disk_cwd_cluster+1
        sta <(zptempv2+1)
        lda dos_disk_cwd_cluster+2
        sta <zptempp
        lda dos_disk_cwd_cluster+3
        sta <(zptempp+1)
        rts

rmdir_restore_cwd:
        lda <zptempv2
        sta dos_disk_cwd_cluster+0
        lda <(zptempv2+1)
        sta dos_disk_cwd_cluster+1
        lda <zptempp
        sta dos_disk_cwd_cluster+2
        lda <(zptempp+1)
        sta dos_disk_cwd_cluster+3
        rts


mkfile_fail_with_a:
        sta dos_error_code
        jmp return_from_trap_with_failure

;; Calls dos_analyze_name_for_dirent; on the $ff "name unusable" result,
;; fails with dos_errorcode_name_too_long. Returns normally otherwise.
dos_analyze_name_or_fail:
        jsr dos_analyze_name_for_dirent
        lda <zptempv32b
        cmp #$ff
        bne +
        lda #dos_errorcode_name_too_long
        bra mkfile_fail_with_a
+       rts

;; Builds a short name from dos_requested_filename, splitting at the
;; last '.'. If it fits 8.3 cleanly, sets zptempv32b+0 = 0 and returns
;; carry CLEAR. Otherwise builds a tilde-numbered short name, sets
;; zptempv32b+0 to the number of LFN pieces needed, and returns carry
;; SET. A name too long to ever reassemble sets zptempv32b+0 = $ff
;; instead. Uses zptempv2/zptempp as scratch.
dos_analyze_name_for_dirent:
        ;; Pad short name with spaces first.
        ldy #10
        lda #$20
ran_pad_loop:
        sta dos_dirent_shortfilename,y
        dey
        bpl ran_pad_loop

        lda #$ff
        sta <zptempv2                    ;; dot position (0xff = none found)
        ldx #0
ran_scan_dot:
        cpx dos_requested_filename_len
        beq ran_scan_dot_done
        lda dos_requested_filename,x
        cmp #$2e
        bne ran_scan_dot_next
        stx <zptempv2
ran_scan_dot_next:
        inx
        bne ran_scan_dot
ran_scan_dot_done:

        lda <zptempv2
        cmp #$ff
        bne ran_have_dot
        lda dos_requested_filename_len
        sta <(zptempv2+1)                 ;; base_len = whole name
        lda #0
        sta <zptempp                      ;; ext_len = 0
        bra ran_have_lengths
ran_have_dot:
        sta <(zptempv2+1)                 ;; base_len = dot position
        lda dos_requested_filename_len
        sec
        sbc <zptempv2
        sec
        sbc #1
        sta <zptempp                      ;; ext_len = len - dotpos - 1
ran_have_lengths:

        lda <(zptempv2+1)
        beq ran_too_long                  ;; base_len == 0
        cmp #9
        bcs ran_too_long                  ;; base_len >= 9
        lda <zptempp
        cmp #4
        bcs ran_too_long                  ;; ext_len >= 4

        lda <(zptempv2+1)
        jsr ran_copy_base_chars           ;; base_len already <= 8 here
        lda <zptempp
        jsr ran_copy_ext_chars             ;; ext_len already <= 3 here
        lda #0
        sta <zptempv32b
        clc
        rts

ran_too_long:
        ;; Reject empty names and ones too long to reassemble (max 5
        ;; LFN pieces = 65 chars).
        lda dos_requested_filename_len
        beq ran_name_unusable
        cmp #66
        bcc ran_build_tilde
ran_name_unusable:
        lda #$ff
        sta <zptempv32b
        sec
        rts

ran_build_tilde:
        ;; base chars: min(base_len, 6)
        lda <(zptempv2+1)
        cmp #6
        bcc ran_tilde_base_asis
        lda #6
ran_tilde_base_asis:
        jsr ran_copy_base_chars
        ;; X now holds the number of base chars actually copied. Stash
        ;; it across the extension copy below, which also uses X as
        ;; its own loop counter.
        txa
        pha

        ;; extension chars: min(ext_len, 3)
        lda <zptempp
        cmp #3
        bcc ran_tilde_ext_asis
        lda #3
ran_tilde_ext_asis:
        jsr ran_copy_ext_chars

        ;; '~' goes right after the base chars.
        pla
        tax
        lda #$7e                        ;; '~'
        sta dos_dirent_shortfilename,x
        inx
        stx <dos_tilde_digit_pos

        ;; Try ~1, ~2, ... ~9 until one doesn't collide with an
        ;; existing short name in this directory (real FAT32 LFN
        ;; implementations do the same - a naive always-~1 lets two
        ;; names that truncate to the same 6 characters collide).
        ;; The number and its offset must survive dos_shortname_exists,
        ;; so they get their own bytes rather than zptempv2/zptempp.
        lda #1
        sta <dos_tilde_number
ran_tilde_try:
        clc
        adc #$30
        ldx <dos_tilde_digit_pos
        sta dos_dirent_shortfilename,x
        jsr dos_shortname_exists
        bcc ran_tilde_number_ok
        inc <dos_tilde_number
        lda <dos_tilde_number
        cmp #10
        bne ran_tilde_try
        ;; all of ~1-~9 are taken - give up, same as an unreassemblable name.
        bra ran_name_unusable
ran_tilde_number_ok:

        ;; Piece count = ceil(whole_name_len / 13).
        lda #0
        sta <zptempv32b
        lda dos_requested_filename_len
ran_tilde_piece_loop:
        cmp #1
        bcc ran_tilde_piece_done         ;; remaining == 0 -> done
        inc <zptempv32b
        cmp #13
        bcc ran_tilde_piece_lastdone     ;; remaining < 13 -> last piece
        sec
        sbc #13
        bra ran_tilde_piece_loop
ran_tilde_piece_lastdone:
        lda #0
        bra ran_tilde_piece_loop
ran_tilde_piece_done:
        sec
        rts

;; A = number of base chars to copy. Copies+uppercases into
;; dos_dirent_shortfilename, leaves X = count.
ran_copy_base_chars:
        sta <(zptempv2+1)                 ;; loop bound
        ldx #0
ran_copy_base_chars_loop:
        cpx <(zptempv2+1)
        beq ran_copy_base_chars_done
        lda dos_requested_filename,x
        jsr toupper
        sta dos_dirent_shortfilename,x
        inx
        bra ran_copy_base_chars_loop
ran_copy_base_chars_done:
        rts

;; A = number of extension chars to copy (0 is a valid no-op).
;; Copies+uppercases into dos_dirent_shortfilename+8.
ran_copy_ext_chars:
        sta <zptempp
        beq ran_copy_ext_chars_done
        lda <zptempv2
        clc
        adc #1
        sta <(zptempv2+1)                  ;; ext_start, walked forward
        ldx #0
ran_copy_ext_chars_loop:
        cpx <zptempp
        beq ran_copy_ext_chars_done
        ldy <(zptempv2+1)
        lda dos_requested_filename,y
        jsr toupper
        sta dos_dirent_shortfilename+8,x
        inc <(zptempv2+1)
        inx
        bra ran_copy_ext_chars_loop
ran_copy_ext_chars_done:
        rts

;; ============================================================
;; SHARED DOS ENGINE + PARTITION TABLE / DISK-ATTACH MACHINERY
;; ============================================================

;; Read partition table from SD card.
;;
;; Add all FAT32 partitions to our list of known disks.
;;
;; This routine assumes that the SD card has been reset and is ready to
;; service requests.
;;
;; XXX - We don't support extended partition tables! Only the old-fashion
;; 4 DOS partitions.  We might get excited and add support for them later
;;
dos_read_partitiontable:

        ;; clear error code
        ;;
        lda #0
        sta dos_error_code

        ;; Clear the list of known disks
        ;;
        jsr dos_initialise_disklist

        jsr dos_read_mbr
        bcc l_drpt_fail

        ;; Make the sector buffer visible
        ;;
        jsr sd_map_sectorbuffer

        ;; check for $55, $AA MBR signature
        ;;
        jsr dos_check_55aa_signature
        bcc l_drpt_fail

        ;; yes, $55AA MBR signature was found

        +Checkpoint "Found $55, $AA at $1FE on MBR"

        ;; Partitions start at offsets $1BE, $1CE, $1DE, $1EE
        ;; so consider each in turn.  Opening the partition causes other sectors to
        ;; be read, so we must re-read the MBR between each

        ;; get pointer to second half of sector buffer so that we can access the
        ;; partition entries as we see fit.
        ;;

        lda #<(sd_sectorbuffer+$1BE)
        sta <dos_scratch_vector
        lda #>(sd_sectorbuffer+$1BE)
        sta <(dos_scratch_vector+1)
        +Checkpoint "=== Checking Partition #1 at $01BE"
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcc l_drpt_fail
        lda #<(sd_sectorbuffer+$1CE)
        sta <dos_scratch_vector
        +Checkpoint "=== Checking Partition #2 at $01CE"
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcc l_drpt_fail
        lda #<(sd_sectorbuffer+$1DE)
        sta <dos_scratch_vector
        +Checkpoint "=== Checking Partition #3 at $01DE"
        jsr dos_consider_partition_entry

        jsr dos_read_mbr
        bcs +
l_drpt_fail:
        jmp drpt_fail
+       lda #<(sd_sectorbuffer+$1EE)
        sta <dos_scratch_vector
        +Checkpoint "=== Checking Partition #4 at $01EE"
        jsr dos_consider_partition_entry

        lda #0
        sta dos_error_code
        sec
        rts

;;         ========================

;; Checks for the $55,$AA MBR/partition signature at sd_sectorbuffer+$1FE/
;; $1FF, pre-setting dos_error_code to bad_signature. Returns carry SET if
;; found, CLEAR if not.
dos_check_55aa_signature:
        lda #dos_errorcode_bad_signature
        sta dos_error_code
        lda sd_sectorbuffer+$1FE
        cmp #$55
        bne dc55_bad
        lda sd_sectorbuffer+$1FF
        cmp #$AA
        bne dc55_bad
        sec
        rts
dc55_bad:
        clc
        rts

;;         ========================

dos_read_mbr:

        ;; Offset zero on disk
        ;;

        lda #0
        sta sd_address_byte0
        sta sd_address_byte1
        sta sd_address_byte2
        sta sd_address_byte3

        +Checkpoint "Reading MBR @ 0x00000000"

        ;; Read sector
        ;;
        jsr sd_readsector
        bcs +
        bra drpt_fail
+       rts

;;         ========================

dos_initialise_disklist:

        lda #0
        sta dos_disk_count
        rts

;;         ========================

dos_consider_partition_entry:

        lda #$00
        sta dos_error_code

        ;; Offset within partition table entry of partition type
        ;;
        ;; BG: make this a hash-define
        ;;
        ldy #$04

        ;; Get partition type byte
        ;;
        lda (<dos_scratch_vector),y

        ;; We like FAT32 partitions, whether LBA or CHS addressed, although we actually
        ;; use LBA addressing.  XXX - Can this cause problems for CHS partitions?
        ;; (SD cards which must really use LBA, can still show up with CHS partitions!
        ;;  this is really annoying.)
        ;;
        cmp #constant_partition_type_fat32_lba        ;; compare with 0x0C
        beq partitionisinteresting_lba

        cmp #constant_partition_type_fat32_chs        ;; compare with 0x0B
        beq partitionisinteresting_chs

        cmp #constant_partition_type_megea65_sys ;; compare with 0x41
        beq partitionisinteresting_mega65sys

        lda #dos_errorcode_partition_not_interesting
        sta dos_error_code
        bra partitionisnotinteresting

;;         ========================

partitionisinteresting_mega65sys:

        +Checkpoint "MEGA65 System Partition (type=0x41)"

        ;; Only one system partition
        lda syspart_present
        beq +
        bra partitionerror
+
        ;; Store start and length of System partition
        ;; (These are the first two fields of the syspart structure
        ;;  to facilitate a simple copy here)
        ldy #$08
        ldx #$00

spc1:   lda (<dos_scratch_vector),y
        sta syspart_structure,x
        inx
        iny
        cpy #$10
        bne spc1

        jsr syspart_open
        sec
        rts

partitionisinteresting_lba:

        +Checkpoint "Partn has fat32_lba (type=0x0c)"

partitionisinteresting_chs:

        +Checkpoint "WARN:Partn has fat32_chs (type=0x0b)"

;;         ========================

partitionisinteresting:

        ;; Make sure we have a spare disk slot
        lda dos_disk_count
        cmp #dos_max_disks
        bne +
        bra partitionerror
+
        ;; Partition is FAT32 (either 0B or 0C), so add it to the list

        ;; Disk structures in dos_disk_table are 32 bytes long, so shift count left
        ;; 5 times to get offset in dos disk list table
        ;;
        ;; initially, dos_disk_count=00 so shifting results in =00
        ;;
        lda dos_disk_count
        asl
        asl
        asl
        asl
        asl
        tax

        ;; Copy relevant fields into place
        ;; These are start of partition and length of partition (both in sectors)
        ;; XXX - This requires that our dos_disk_table has these two fields together
        ;; at the start of the structure.
        ;;
        ldy #$08        ;; partition_lba_begin (4 bytes)

dcpe1:  lda (<dos_scratch_vector),y
        sta dos_disk_table,x
        inx
        iny
        cpy #$10        ;; partition_num_sectors (4 bytes)
        bne dcpe1

        ;; Examine the internals of the partition to get the remaining fields.
        ;; At this point we no longer use the contents of the MBR
        ;;

        jsr dos_disk_openpartition
        bcc partitionerror

!if DEBUG_HYPPO {
        jsr dump_disk_table
}

        ;; Check if partition is bootable (or the only partition)
        ;; If so, make the partition the default disk
        ;;
        ;; BG, we should examine all four partitions before setting the default disk
        ;;
        lda dos_disk_count
        beq makethispartitionthedefault
        ldy #$00
        lda (<dos_scratch_vector),y
        bpl dontmakethispartitionthedefault


makethispartitionthedefault:
        lda dos_disk_count
        sta dos_default_disk

!if DEBUG_HYPPO {
        ;; print out this message to Checkpoint
        ;;

        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty mtptd
        stx mtptd+1

        jsr checkpoint
        !8 0
        !text "dos_default_disk = "
mtptd:  !text "xx"
        !8 0

;; jsr dump_disk_table
}

        ;; return OK
        ;;
        sec
        rts

;;         ========================

dontmakethispartitionthedefault:

        ldx dos_disk_count

!if DEBUG_HYPPO {
        ;; print out this message to Checkpoint
        ;;

                                        ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        stx mtptd2

        jsr checkpoint
        !8 0
        !text "Part#"
mtptd2: !text "x NOT set to the default_disk"
        !8 0

;; jsr dump_disk_table
}

        ;; return OK
        ;;

        sec
        rts

;;         ========================

partitionisnotinteresting:

        ;; return OK
        ;;

        +Checkpoint "Partition not interesting"

        sec
        rts

;;         ========================

drpt_fail:

        ;; error code will already be set

partitionerror:

        ;; return ERROR

!if DEBUG_HYPPO {
        ldx dos_error_code                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty perr
        stx perr+1

        jsr checkpoint
        !8 0
        !text "partitionerror="
perr:   !text "xx"
        !8 0
}

        clc
        rts

dos_disk_openpartition:

        +Checkpoint "dos_disk_openpartition: (examine Vol ID)"

        ;; A contains the disk number we are trying to open.
        ;;
        lda #$00
        sta dos_error_code

        ;; Load first sector of file system and parse.
        ;; This is the Volume ID pointed to by the PartitionTable in the MBR

        ;; Get offset of disk entry in our disk table structure
        ;;
        lda dos_disk_count
        asl
        asl
        asl
        asl
        asl
        sta dos_disk_table_offset

        ;; Now pull the start sector from the structure and get ready to request
        ;; that structure from the SD card.
        ;;
        ora #fs_start_sector        ;; OR with 00 does nothing, but this is the standard
        tay
        ldx #$00

ddop1:  lda dos_disk_table,y
        sta sd_address_byte0,x
        iny
        inx
        cpx #$04
        bne ddop1

!if DEBUG_HYPPO {
jsr dumpsectoraddress        ;; debugging
}

        jsr sd_readsector
        bcc partitionerror

        ;; We now have the sector, so parse.

        jsr sd_map_sectorbuffer

;;         ========================

        ;; Check for 55/AA singature (again, for the Vol-ID of this partition)
        ;;
        jsr dos_check_55aa_signature
        bcs ddop1b
        bra partitionerror
ddop1b:
        +Checkpoint "Partn has $55, $AA GOOD"

        ;; Start populating fields

;;         BG assumes this is all correct...

;;         ========================

        ;; Filter out obviously FAT16/FAT12 file systems
        ;;
        lda #dos_errorcode_is_small_fat
        sta dos_error_code
        ;;
        ;; BG i think we dont need to check this for minimal operation
        ;;
        ;; for fat32, the 11'th entry is unused, http:;;www.easeus.com/resource/fat32-disk-structure.htm
        ;;
        lda sd_sectorbuffer+$11        ;; this is NOT the MBSyte of the number of FATs
        bne partitionerror

;;         ========================

        ;; get # copies of fat
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_fat_copies        ;; is $17
        tay
        lda sd_sectorbuffer+$10        ;; should be 2
        sta dos_disk_table,y

;;         ========================

        ;; With root directory entries = 0, the reserved sector count
        ;; is the number of reserved sectors, plus (copies of fat) *
        ;; (sectors in one copy of the fat).
        ;; the first FAT begins immediately after the reserved sectors

        ;; Determine system sector count
        ;; (= reserved sectors + fat_count * fat_sectors)
        ;; $20 + $EE5 + $EE5 = $1DEA
        ;; plus partition offset = $81 = $1E6B
        ;; partition length = $3BAF7F
        ;; $08 sectors / cluster
        ;; so data sectors in partition = $3BAF7F - $1DEA = $3B9195
        ;; = $77232 clusters

        ;; BG does not like the above reasoning, ie fixed number of reserved sectors.

        ;; Reserved sector field on disk is only 2 bytes!
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_system_sectors        ;; is $0D
        tay
        ldx #$00

ddop10: lda sd_sectorbuffer+$0E,x
        sta dos_disk_table,y
        iny
        inx
        cpx #$02
        bne ddop10

;;         ========================

        ;; Store length of one copy of the FAT
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_length_of_fat        ;; is $09
        tay
        ldx #$00

ddop11: lda sd_sectorbuffer+$24,x        ;; sectors_per_fat
        sta dos_disk_table,y
        iny
        inx
        cpx #$04
        bne ddop11

;;         ========================

        ;; Get number of reserved clusters.  We only allow upto 255 reserved
        ;; clusters, so report an error if the upper three bytes are not zero
        ;;
        ;; BG: why only 255 reserved clusters? and isnt it reserved sectors instead?
        ;; and seems to be looking at the root_dir_first_cluster
        ;;
        lda #dos_errorcode_too_many_reserved_clusters
        sta dos_error_code

        lda sd_sectorbuffer+$2C+1
        ora sd_sectorbuffer+$2C+2
        ora sd_sectorbuffer+$2C+3
        beq ddop11ok
        jmp partitionerror

;;         ========================

ddop11ok:

        ;; <64K reserved clusters, so file system passes this test -- just copy number
        ;;
        ;; BG does not agree with the logic, of <64k reservedclusters to passes
        ;; BG the code below could be changed to be same as lda,ora,tay
        ;;
        ;; BG, so by design, we reject any Vol_ID that has
        ;; RootDirFirstCluster[3..0] not equal to $00000002
        ;;
        ldy dos_disk_table_offset
        lda sd_sectorbuffer+$2C        ;; 2c is the ClusterNumberOfFirstRootDir
        sta dos_disk_table + fs_fat32_reserved_clusters,y

;; Checkpoint("dos_disk_table-1")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00 = (fs_start_sector),                       (fs_sector_count)
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02 = type, (sectorsPerFat),(reservedSectors),(reservedClusters)
;; dos_disk_table[10-17] = 00,00,00,00,00,00,00,02 = x..x                                ,(fs_fat32_fat_copies)
;; dos_disk_table[18-1F] = 00,00,00,00,xx,xx,xx,xx

;;         ========================

        ;; Now work out the sector of cluster 0, by adding:
        ;;   fs_fat32_system_sectors
        ;; + the length of each FAT
        ;; + start of partition,
        ;; and store this result in dos_disk_table[18..1B]
        ;;
        ;; For efficiency, we pull the fields we need out of the sector buffer,
        ;; instead of working out their offsets in the dos_disk_table structure.
        ;; BG disagree, we know the offsets of the fields in dos_disk_table

        ;; Start with fs_fat32_system_sectors (which is 16 bits), then pad MSBs with zero
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_system_sectors        ;; is $0D
        tay
        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector        ;; is $18
        tax
        ldz #$02

ddop2:  lda dos_disk_table,y
        sta dos_disk_table,x
        iny
        inx
        dez
        bne ddop2

        ;; clear top 16 bits of cluster0_sector (dos_disk_table[1A,1B])
        ;;
        ;; BG: why tza, just do lda#$00
        tza
        sta dos_disk_table+0,x
        sta dos_disk_table+1,x

;; Checkpoint("dos_disk_table-2")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 00,00,00,00,00,00,00,02
;; dos_disk_table[18-1F] = 38,02,00,00,xx,xx,xx,xx -> $00000238


;;         ========================

        ;; Now add length of fat for each copy of the fat
        ;;
        lda #dos_errorcode_not_two_fats
        sta dos_error_code

        ;; BG #FATs should be sourced from dos_disk_table[17], not from buffer+$10

        ldz sd_sectorbuffer+$10         ;; # of FAT copies
        beq l_partitionerror            ;; There must be at least one copy of the FAT!
        cpz #2
        beq ddop_addnextfatsectors
l_partitionerror:
        jmp partitionerror

ddop_addnextfatsectors:
        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector   ;; is $18
        tay
        ldx #$00
        clc
        php                             ;; push processor-status (to remember the carry-flag)

ddop12: plp                             ;; pull processor-status
        lda dos_disk_table,y            ;; cluster0_sector
        adc sd_sectorbuffer+$24,x       ;; sectors per fat ;BG should load from dos_disk_table[09]
        sta dos_disk_table,y            ;; cluster0_sector
        php
        iny
        inx
        cpx #$04
        bne ddop12

        plp
        ;;
        ;; as Z was initially 2 (#FATs), we do this loop twice
        ;; resulting in 2x the sectorsPerFat added to "reservedSectors".
        dez
        bne ddop_addnextfatsectors

;; Checkpoint("dos_disk_table-3")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 00,00,00,00,00,00,00,02
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx -> $00000238 + ($000003e6 + $000003e6) = $00000A04

;; BG does not agree with the calculations below, why do we need to calculate it this way?

        ;; Next, we temporarily need the number of data sectors, so that we can work
        ;; out the number of clusters in the file system.
        ;; This is the total number of sectors in the partition, minus the number of
        ;; reserved sectors.

        ;; Subtract (cluster 0 sector = 32 bits) from
        ;; (length of filesystem in sectors = 32 bits)

        lda dos_disk_table_offset
        ora #fs_fat32_cluster0_sector   ;; is $18
        tax
        lda dos_disk_table_offset
        ora #fs_fat32_cluster_count     ;; is $12
        tay
        sec
        lda sd_sectorbuffer+$20+0     ;; from FAT spec, this is number of sectors in partition
        sbc dos_disk_table+0,x        ;; x=$18 initially
        sta dos_disk_table+0,y        ;; y=$12 initially
        lda sd_sectorbuffer+$20+1
        sbc dos_disk_table+1,x
        sta dos_disk_table+1,y
        lda sd_sectorbuffer+$20+2
        sbc dos_disk_table+2,x
        sta dos_disk_table+2,y
        lda sd_sectorbuffer+$20+3
        sbc dos_disk_table+3,x
        sta dos_disk_table+3,y

;;         ========================

get_sec_per_cluster:
        ;; Get sectors per cluster (and store in dos_disk_table entry)
        ;; (this gets destoryed below, so we have to re-read it again after)
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        ;; is $16
        tay
        lda sd_sectorbuffer+$0D
        sta dos_disk_table,y

;; Checkpoint("dos_disk_table-4")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 00,00,FC,95,0F,00,08,02 -> new data appears
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx


;;         ========================

        ;; Now divide number of sectors available for clusters by the number of
        ;; sectors per cluster to obtain the number of actual clusters in the file
        ;; system.  Since clusters must contain a power-of-two number of sectors,
        ;; we can implement the division using a simple shift.

        ;; copy number of sectors into number of sectors ready for shifting down

        ;; Put number of sectors per cluster into Z, and don't shift if there is only
        ;; one sector per cluster.
        ;;
        lda sd_sectorbuffer+$0D            ;; because of the checkpoint message above
        taz                                ;; why store .A in .Z anyway

        and #$fe        ;; #%1111.1110
        beq ddop_gotclustercount

ddop14:
        ;; Divide cluster count by two.  This is a 32-bit value, so we have to use
        ;; ROR to do the shift, and propagate the carry bits between the bytes.
        ;; This also entails doing it from the last byte, backwards.

        ;; Get offset of start of (sectors_per_cluster) field
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_cluster_count        ;; is $12

        ;; get offset of last byte in this field
        ;;
        clc
        adc #$03
        tay

        ldx #$03
        clc

ddop15: lda dos_disk_table,y
        ror
        sta dos_disk_table,y
        dey
        dex
        bpl ddop15

        tza
        lsr
        taz
        and #$fe
        bne ddop14

ddop_gotclustercount:

;; Checkpoint("dos_disk_table-5")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 00,00,AF,7C,00,00,08,02 -> new data appears
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx


        ;; Re-get sectors per cluster (and store in dos_disk_table entry)
        ;; (this was destroyed in the calculation above)
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        ;; is $16
        tay
        lda sd_sectorbuffer+$0D
        sta dos_disk_table,y

;; Checkpoint("dos_disk_table-6")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 00,00,AF,7C,00,00,08,02
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

;;         ========================

        ;; filter out non-FAT32 filesystems
        ;; NOTE: FAT32 can have as few as 65525 clusters, but we do not support
        ;; such file systems, which should be rare, anyway.

        lda dos_disk_table_offset
        ora #fs_fat32_sectors_per_cluster        ;; is $16
        tay
        lda #dos_errorcode_too_few_clusters
        sta dos_error_code

        lda dos_disk_table+3,y        ;; BG this seems to creep-out-of-bounds from +16 to +19
        ora dos_disk_table+2,y
        lbeq partitionerror
+
        ;; Now get cluster of root directory.
        ;;
        lda dos_disk_table_offset
        ora #fs_fat32_root_dir_cluster                ;; is $10
        tay

        ldx #$03
ddop16: lda sd_sectorbuffer+$2C,x        ;; +$2c is rootDirFirstCluster[3..0]
        sta dos_disk_table,y
        dex
;; BG should there be a "dey" here somewhere?
        bpl ddop16

        ;; We have now set the following fields:
        ;;
        ;; fs_fat32_length_of_fat
        ;; fs_fat32_system_sectors
        ;; fs_fat32_reserved_clusters
        ;; fs_fat32_root_dir_cluster
        ;; 12,13,14,15 ?
        ;; fs_fat32_sectors_per_cluster
        ;; fs_fat32_fat_copies
        ;; fs_fat32_cluster0_sector

        ;; Our caller has set:
        ;;
        ;; fs_start_sector
        ;; fs_sector_count

;; Checkpoint("dos_disk_table-7")
;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 00,E6,03,00,00,38,02,02
;; dos_disk_table[10-17] = 02,00,AF,7C,00,00,08,02 -> new data appears in [10]
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

        ;; So all that is left for us is to set fs_type_and_source to $0F
        ;; to indicate FAT32 filesystem on the SD card ...
        ;;
        lda dos_disk_table_offset
        ora #fs_type_and_source                ;; is $08
        tay
        lda #$0f
        sta dos_disk_table,y

;; jsr dump_disk_table        ; debugging

;; dos_disk_table[00-07] = 00,08,00,00,00,A0,0F,00
;; dos_disk_table[08-0F] = 0F,E6,03,00,00,38,02,02 -> new data appears in [08]
;; dos_disk_table[10-17] = 02,00,AF,7C,00,00,08,02
;; dos_disk_table[18-1F] = 04,0A,00,00,xx,xx,xx,xx

        +Checkpoint "FAT32 partition data copied to dos_disk_table"

        ;; ... and increment the number of disks we know
        inc dos_disk_count

dos_return_success:

        ;; Return success
        ;;
        lda #$00
        sta dos_error_code

        sec
        rts

;;         ========================
;;         ========================

dos_return_error:

        sta dos_error_code

dos_return_error_already_set:

        clc
        rts

;;         ========================

dos_set_current_disk:

        ;; Is disk number valid?
        ;;
        ;; INPUT: .X = disk
        ;;

        cpx dos_disk_count
        lbcs td81we1
+
        stx dos_disk_current_disk
        txa
        asl
        asl
        asl
        asl
        asl
        sta dos_disk_table_offset

!if DEBUG_HYPPO {
        ldx dos_disk_current_disk        ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty dscd+0
        stx dscd+1

        ;; print debug message
        ;;
        jsr checkpoint
        !8 0
        !text "dos_set_current_disk="
dscd:   !text "xx"
        !8 0
}

        sec
        rts

;;         ========================

dos_cdroot:

        ;; Change to root directory on specified disk
        ;; (Changes current disk if required)
        ;;
        ;; INPUT: .X = disk

        jsr dos_set_current_disk
        bcs dos_cdroot_current_disk_already_set

        ;; Could not set disk. Error will be already set
        clc
        rts

dos_cdroot_current_disk_already_set:

        ;; get offset of disk entry
        ;;

        ldx dos_disk_table_offset
        lda dos_disk_table + fs_fat32_root_dir_cluster +0,x
        sta dos_disk_cwd_cluster
        lda dos_disk_table + fs_fat32_root_dir_cluster +1,x
        sta dos_disk_cwd_cluster+1

        lda #$00
        sta dos_disk_cwd_cluster+2        ;; BG here we assume that the 2x MSB's are zero
        sta dos_disk_cwd_cluster+3

        ;; Nothing else to do, as it doesn't actually affect any existing DOS activity,
        ;; only future file/directory operations.

        bra dos_return_success

;;         ========================

dos_cluster_to_sector:

        ;; convert a cluster number in <dos_current_cluster into a sector number
        ;; pre-loaded into SD address registers
        ;; It is assumed to be on the current disk

        ldx #$03
dcts0:  lda dos_current_cluster,x
        sta $d681,x
        dex
        bpl dcts0

        ;; subtract 2 from the cluster number (clusters 0 and 1 don't actually exist
        ;; on FAT32).
        ;;
        lda #$ff
        tax
        tay
        taz
        lda #$fe
        jsr sdsector_add_uint32

        ;; now shift it left according to fs_sectors_per_cluster
        ;;
        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
        tay
        and #$fe
        beq multipliedclusternumber

dcts1:  clc
        rol $D681
        rol $D682
        rol $D683
        rol $D684
        tya
        lsr
        tay
        and #$fe
        bne dcts1

multipliedclusternumber:

        ;; skip over filesystem reserved and FAT sectors
        ;;
        lda #fs_fat32_cluster0_sector
        jsr sdsector_add_uint32_from_disktable

        ;; add start sector of partition
        ;;
        lda #fs_start_sector
        jsr sdsector_add_uint32_from_disktable

        ;; XXX - Check that result does not exceed fs_start_sector+fs_sector_count
        ;; and run over into another partition

        ;; return success
        sec
        rts

;;         ========================

;; A = X*dos_filedescriptor_stride (byte offset of FD X's slot in
;; dos_file_descriptors). Preserves X. Clobbers A. A plain lookup table
;; (X only ranges 0-3) rather than a shift-add chain - smaller, and
;; doesn't force the stride to be a convenient sum of shifts.
dos_fd_number_to_offset:
        lda dos_fd_offset_table,x
        rts
dos_fd_offset_table:
        !8 0, dos_filedescriptor_stride*1, dos_filedescriptor_stride*2, dos_filedescriptor_stride*3

;;         ========================

dos_get_free_descriptor:

        ldx #$00

dgfd1:  jsr dos_fd_number_to_offset
        tay
        lda dos_file_descriptors+dos_filedescriptor_offset_diskid,y
        cmp #$FF
        beq dgfd_found_free
        inx
        cpx #dos_filedescriptor_max
        bne dgfd1

        lda #dos_errorcode_too_many_open_files
        jmp dos_return_error

;;         ========================

dgfd_found_free:

        stx dos_current_file_descriptor
        sty dos_current_file_descriptor_offset

        ;; Push the address dos_file_descriptors + dos_current_file_descriptor_offset
        ;;
        clc
        lda #<dos_file_descriptors
        adc dos_current_file_descriptor_offset
        tay
        lda #>dos_file_descriptors
        adc #$00
        pha
        phy

        ;; Clear descriptor entry
        ;;
        ldy #dos_filedescriptor_stride-1
        lda #$00

dgfd2:  sta ($01,sp),y
        dey
        bne dgfd2

        ;; Pop the address
        pla
        pla

        ;; Return file descriptor in X
        sec
        rts

;;         ========================

dos_clearall:

        ;; Free all file descriptors with extreme prejudice
        ;; Clear dos_disk_table

        ;; display debug message to uart
        ;;
        +Checkpoint "dos_clearall:"

        lda #$ff
        jsr dos_clear_all_filedescriptors
        ldx #$00
        lda #$00
dca1:   sta dos_disk_table,x
        inx
        bne dca1
        sec
        rts

;;         ========================

dos_closefile:

        ;; Close the current file/directory
        ;; If the file is read-only, we can just free the file descriptor and return.
        ;; XXX - If the file is open for write, we might have a buffer to flush.
        ;; (Worry about this when we implement writing. Opening files for write will
        ;; probably require the caller to nominate a 512 byte buffer in user-space
        ;; memory so that the convenience write-byte routine can work.  The other case,
        ;; writing a sector at a time, should just be synchronous, so that there is no
        ;; buffering required.)

        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_mode,x
        cmp #dos_filemode_readwrite
        bne dcf_simple

        ;; This is where we would flush the write buffer, and update file length in
        ;; directory, if required.  Note that to save space, we don't actually keep the
        ;; location of the directory entry of the file in the file descriptor.  This
        ;; complicates things somewhat, and we might need to change this.  However, the
        ;; file descriptor table must be a power of two in length, and there isn't any
        ;; space to double its' size.  Thus we will need a separate table that holds the
        ;; directory sector and entry for any file being written to.  We might save a
        ;; few bytes by allowing less than dos_filedescriptor_max files to be open for
        ;; writing at any point in time.

dcf_simple:

        ldx dos_current_file_descriptor_offset
        lda #$ff ;; not allocated flag for file descriptor
        sta dos_file_descriptors + dos_filedescriptor_offset_diskid,x
        sec
        rts

;;         ========================

dos_chdir:
        ;; Works similarly to dos_openfile, i.e. you must first have the
        ;; directory in the dirent structure, found via dos_findfile

        ;; Check if the file is a directory, if so, refuse to open it.
        ;;
        lda dos_dirent_type_and_attribs
        and #fs_fat32_attribute_isdirectory
        bne dcd_is_a_directory

        lda #dos_errorcode_not_a_directory
        jmp dos_return_error

;;         ========================

dcd_is_a_directory:

        jsr dos_set_current_file_from_dirent
        lbcc l3_dos_return_error_already_set
dcd_gotfile:

        ;; Close the file descriptor opened by dos_set_current_file_from_dirent
        jsr dos_closefile

        ;; Copy cluster of requesteed directory into disk CWD cluster
        ldx #3
dcd1:	lda dos_dirent_cluster,x
        sta dos_disk_cwd_cluster,x
        dex
        bpl dcd1

        ;; Check if cluster 0. If so, cd to root directory
        ;; (its a convention to put cluster 0 in references to the root directory
        ;; on some FAT implementations, apparently).
;;         ========================

;; If dos_disk_cwd_cluster is all-zero (the FAT32 convention some
;; implementations use for "this is the root directory" in a ".."
;; entry), replaces it with this disk's real root cluster. Always
;; returns with carry SET.
dos_cwd_translate_root_sentinel:
        ldx #3
        lda #0
-	ora dos_disk_cwd_cluster,x
        dex
        bpl -
        lbeq dos_cdroot_current_disk_already_set
dctrs_nonzero:
        sec
        rts

;;         ========================

;; Remembers the task's disk and current directory in the process
;; descriptor, which is one of the regions written to the freeze slot.
dos_save_cwd_to_task:
        lda dos_disk_current_disk
        sta currenttask_cwd_disk
        ldx #3
-       lda dos_disk_cwd_cluster,x
        sta currenttask_cwd_cluster,x
        dex
        bpl -
        rts

;; Puts a resumed task back in the directory it froze in. The saved
;; cluster can go stale while the freezer menu is up - the directory may
;; have been removed, or a different card swapped in - and a stale
;; cluster is worse than simply landing in the wrong place, because it
;; may since have been handed to a file whose contents dirent writes
;; would then corrupt. So the directory has to still be reachable from
;; its own parent, otherwise fall back to the root.
;;
;; The checks below read directory sectors, which maps the sector buffer
;; over $DE00 and clears the $D030 colour-RAM bit that the unfreeze has
;; just restored for the task, so $D030 is put back afterwards.
dos_restore_cwd_to_task:
        lda $d030
        pha
        jsr drctt_validate
        jsr sd_unmap_sectorbuffer
        pla
        sta $d030
        rts

drctt_validate:
        ldx currenttask_cwd_disk
        jsr dos_set_current_disk
        bcc drctt_fallback

        ;; Set the cwd straight away and keep a copy in zptempv32 for the
        ;; checks below; the fallback overwrites it if they fail.
        ldx #3
-       lda currenttask_cwd_cluster,x
        sta dos_disk_cwd_cluster,x
        sta <zptempv32,x
        dex
        bpl -

        lda #16                               ;; deeper than any sane nesting
        sta <dos_cwd_walk_limit

        ;; Checking that the cluster still holds a directory is not
        ;; enough: removing a directory only marks its entry in the
        ;; parent as deleted, leaving its own "." and ".." in place. So
        ;; walk up to the parent and require our entry to still be there,
        ;; the same way getcwd does. If it has gone, try the parent in
        ;; turn, so that deleting /dir1/dir2 leaves us in /dir1 rather
        ;; than all the way back at the root.
drctt_loop:
        jsr dos_cluster_is_root
        bcs drctt_accept                      ;; cwd is already the root

        ldx #3
-       lda <zptempv32,x
        sta dos_dfdcbc_target,x
        dex
        bpl -

        jsr dos_find_parent_of_cluster        ;; cwd := our parent
        jsr dos_find_dirent_in_cwd_by_cluster
        bcs drctt_found

        ;; Gone. cwd is the parent now, so try that as the candidate.
        ldx #3
-       lda dos_disk_cwd_cluster,x
        sta <zptempv32,x
        dex
        bpl -
        dec <dos_cwd_walk_limit
        bne drctt_loop

drctt_fallback:
        ldx dos_disk_current_disk
        jmp dos_cdroot

drctt_found:
        ;; Still listed, so go back to being that directory.
        ldx #3
-       lda dos_dfdcbc_target,x
        sta dos_disk_cwd_cluster,x
        dex
        bpl -

drctt_accept:
        rts

;;         ========================

;; Carry SET if zptempv32 equals this disk's real root cluster.
dos_cluster_is_root:
        ldx dos_disk_table_offset
        lda <(zptempv32+0)
        cmp dos_disk_table+fs_fat32_root_dir_cluster+0,x
        bne dcir_no
        lda <(zptempv32+1)
        cmp dos_disk_table+fs_fat32_root_dir_cluster+1,x
        bne dcir_no
        lda <(zptempv32+2)
        bne dcir_no
        lda <(zptempv32+3)
        bne dcir_no
        sec
        rts
dcir_no:
        clc
        rts

;;         ========================

;; Given zptempv32 = a non-root directory's own cluster, sets
;; dos_disk_cwd_cluster to its real parent cluster, by reading that
;; directory's own ".." entry (always the second 32-byte entry of its
;; first sector) and translating the "0=root" sentinel some FAT
;; implementations use there. Caller must have already ruled out
;; zptempv32 being root (dos_cluster_is_root) - root has no ".." entry.
dos_find_parent_of_cluster:
        jsr dos_copy_zptempv32_and_cluster_to_sector
        jsr sd_map_sectorbuffer
        jsr sd_readsector

        ldy #32+fs_fat32_dirent_offset_clusters_low
        lda sd_sectorbuffer,y
        sta dos_disk_cwd_cluster+0
        iny
        lda sd_sectorbuffer,y
        sta dos_disk_cwd_cluster+1
        ldy #32+fs_fat32_dirent_offset_clusters_high
        lda sd_sectorbuffer,y
        sta dos_disk_cwd_cluster+2
        iny
        lda sd_sectorbuffer,y
        sta dos_disk_cwd_cluster+3

        lbra dos_cwd_translate_root_sentinel

;;         ========================

;; Opens dos_disk_cwd_cluster (via dos_opendir) and scans it for the
;; entry whose cluster matches zptempv32. On match: carry set,
;; dos_direntstart_*/dos_dirent_* left at the match (dos_readdir
;; already does this per entry), directory FD closed. On no match (or
;; if dos_opendir itself fails): carry clear, dos_error_code set
;; (dos_errorcode_file_not_found if the whole directory was scanned).
dos_find_dirent_in_cwd_by_cluster:
        jsr dos_opendir_save_current_fd
        jsr dos_opendir
        lbcc dos_opendir_restore_current_fd
+
dfdcbc_loop:
        jsr dos_readdir
        bcs dfdcbc_check
        jsr dos_closefile_and_restore_current_fd
        lda #dos_errorcode_file_not_found
        jmp dos_return_error
dfdcbc_check:
        ldx #$fc
dfdcbc_cmp:
        lda dos_dirent_cluster-$fc,x
        cmp dos_dfdcbc_target-$fc,x
        bne dfdcbc_loop
        inx
        bne dfdcbc_cmp
        jsr dos_closefile_and_restore_current_fd
        sec
        rts

;;         ========================


dos_openfile:

        ;; Open the file that is in the dirent structure
        ;; (to open a file by arbitrary name, you must first call dos_findfile)

        ;; Check if the file is a directory, if so, refuse to open it.
        ;;
        lda dos_dirent_type_and_attribs
        and #fs_fat32_attribute_isdirectory
        beq dos_not_a_directory

        lda #dos_errorcode_is_a_directory
        jmp dos_return_error

;;         ========================

dos_not_a_directory:

        jsr dos_set_current_file_from_dirent
        bcc l3_dos_return_error_already_set

        jmp dos_open_current_file

;;         ========================

dos_findfile:

        ;; Convenience wrapper around dos_findfirst to make sure that we don't
        ;; leave any hanging file descriptors.

        jsr dos_findfirst
        bcs @found
        bra l3_dos_return_error_already_set
@found: ;; if we found the file, directory-FD is still open
        jsr dos_closefile
        sec
        rts

;;         ========================

dos_findfirst:

        ;; Search for file in current directory
        ;; if found:
        ;;    return return carry set
        ;;    leaves directory-FD open, to enable call dos_findnext to find more
        ;; if not found:
        ;;    will return carry clear
        ;;    closes directory-FD

        ;; Convert name to upper case for searching
        ;;
        ;; GI. Avoiding uppercase for now, so we find matches on LFN files
        ;; But later on, would rather enforce uppercase 'everywhere', even on the files we iterate over in the directory...

        jsr dos_opendir
        bcs +
l3_dos_return_error_already_set:
        jmp dos_return_error_already_set
+
        ;; Directory is now open, and we can now iterate through directory
        ;; entries - falls through directly into dos_findnext.

dos_findnext:

        ;; Keep searching in directory for another match
        ;; see dos_findfirst above for return state!

dff_try_next_entry:

        ;; Get next directory entry
        ;;
        jsr dos_readdir
        bcs dff_have_next_entry

        ;; no more entries, so we close file descriptor for convinience
        jsr dos_closefile

        lda #dos_errorcode_file_not_found
        jmp dos_return_error

dff_have_next_entry:

        ;; Compare dos_dirent_longfilename with dos_requested_filename
        ;;
        jsr dos_dirent_compare_name_to_requested

        ;; no match? try next entry
        ;;
        bcc dff_try_next_entry

        ;; we have a match, so return success
        ;; (we don't close the file handle for the directory search, because the
        ;; caller may want to find multiple matches)
        ;;
        sec
        rts

;;         ========================

;; Opens the current working directory for listing.
dos_opendir:

        ;; assure we are using the sdcard buffer (not the fdc buffer)
        lda #$80
        tsb $d689

        jsr dos_get_free_descriptor
        lbcc dos_return_error_already_set
+
        ;; get offset in file descriptor table
        ;;
        jsr dos_fd_number_to_offset
        tay

        ;; set disk id
        ;;
        lda dos_disk_current_disk
        sta dos_file_descriptors+dos_filedescriptor_offset_diskid,y

        ;; load cluster of dir into file descriptor
        ;;
        ldx #$00

dff1:   lda dos_disk_cwd_cluster,x
        sta dos_file_descriptors+dos_filedescriptor_offset_startcluster,y
        sta dos_file_descriptors+dos_filedescriptor_offset_currentcluster,y
        iny
        inx
        cpx #$04
        bne dff1

        ;; Mark file descriptor as being a directory
        ;;
        ldx dos_current_file_descriptor_offset
        lda #dos_filemode_directoryaccess
        sta dos_file_descriptors + dos_filedescriptor_offset_mode,x

        jmp dos_open_current_file

;;         ========================

dos_readdir_storecurrententry
        ;; store current cluster/sector/offset to rewind to later for rmfile
        ldy #$00
        ldx dos_current_file_descriptor_offset
-       lda dos_file_descriptors + dos_filedescriptor_offset_currentcluster,x
        sta dos_direntstart_cluster,y
        inx
        iny
        cpy #$07
        bne -
        rts

dos_readdir_retreivelastentry
        ;; retrieve current cluster/sector/offset to for rmfile
        ldy #$00
        ldx dos_current_file_descriptor_offset
-       lda dos_direntstart_cluster,y
        sta dos_file_descriptors + dos_filedescriptor_offset_currentcluster,x
        inx
        iny
        cpy #$07
        bne -
        rts

;; Reloads the sector for whatever dos_direntstart_* currently holds.
;; NOTE: via dos_readdir_retreivelastentry, this clobbers the CURRENT
;; file descriptor's own currentcluster/sectorincluster/offsetinsector
;; (its read/write position) - fine for dos_rmfile (the file's being
;; deleted anyway), but wrong for anything that must leave an in-use
;; FD's position alone. Use dos_goto_direntstart_direct_and_point_
;; scratch_vector below for that.
dos_goto_direntstart:
        jsr dos_readdir_retreivelastentry
        jsr sd_map_sectorbuffer
        jmp dos_file_read_current_sector

;; dos_goto_direntstart, then points dos_scratch_vector at the dirent.
dos_goto_direntstart_and_point_scratch_vector:
        jsr dos_goto_direntstart
        ;; falls through into the shared tail below

;; Shared tail: given the dirent is at dos_direntstart_offsetinsector in
;; the mapped SD sector buffer ($de00-$dfff), points dos_scratch_vector
;; at it.
dos_scratch_vector_from_direntstart_offset:
        lda dos_direntstart_offsetinsector+0
        sta <(dos_scratch_vector+0)
        lda dos_direntstart_offsetinsector+1
        clc
        adc #$de   ;; high byte of SD card sector buffer
        sta <(dos_scratch_vector+1)
        rts

;; Same destination as dos_goto_direntstart_and_point_scratch_vector,
;; but reads dos_direntstart_cluster/sectorincluster straight into
;; dos_current_cluster instead of routing through a file descriptor -
;; never touches dos_file_descriptors, so it's safe to call while an
;; FD is still mid-read/write (rename_lfn needs this: the FD being
;; renamed may still be read/written afterward).
dos_goto_direntstart_direct_and_point_scratch_vector:
        ldx #$00
-       lda dos_direntstart_cluster,x
        sta <dos_current_cluster,x
        inx
        cpx #$04
        bne -
        jsr dos_cluster_to_sector
        lda dos_direntstart_sectorincluster
        jsr sdsector_add_uint8
        jsr sd_map_sectorbuffer
        jsr sd_readsector
        bra dos_scratch_vector_from_direntstart_offset

;; Saves/restores the 7-byte dos_direntstart_* trio, used by rename to
;; remember a dirent position across a second lookup.
dos_save_direntstart_to_zptemp:
        lda dos_direntstart_cluster+0
        sta <zptempv2
        lda dos_direntstart_cluster+1
        sta <(zptempv2+1)
        lda dos_direntstart_cluster+2
        sta <zptempp
        lda dos_direntstart_cluster+3
        sta <(zptempp+1)
        lda dos_direntstart_sectorincluster
        sta <zptempp2
        lda dos_direntstart_offsetinsector+0
        sta <(zptempp2+1)
        lda dos_direntstart_offsetinsector+1
        sta <zptempv32b
        rts

dos_restore_direntstart_from_zptemp:
        lda <zptempv2
        sta dos_direntstart_cluster+0
        lda <(zptempv2+1)
        sta dos_direntstart_cluster+1
        lda <zptempp
        sta dos_direntstart_cluster+2
        lda <(zptempp+1)
        sta dos_direntstart_cluster+3
        lda <zptempp2
        sta dos_direntstart_sectorincluster
        lda <(zptempp2+1)
        sta dos_direntstart_offsetinsector+0
        lda <zptempv32b
        sta dos_direntstart_offsetinsector+1
        rts

;; drce_copy_lfn_part: copies one of an LFN piece's 3 name-char runs
;; (Y=entry-relative start offset, Z=char count, both caller-set) into
;; dos_dirent_longfilename starting at X, uppercasing as it goes.
;; Returns carry SET if the caller should stop entirely (end of name,
;; or the 64-char cap hit), carry CLEAR to continue with the next run.
drce_copy_lfn_part:
drce_cpp_loop:
        lda (<dos_scratch_vector),y
        beq drce_cpp_stop
        jsr toupper
        sta dos_dirent_longfilename,x
        lda dos_first_vfat_chunk_in_list_flag
        beq +
        stx dos_dirent_longfilename_length
+
        inx
        cpx #$40                ;; protect against over-long LFNs
        beq drce_cpp_stop
        iny
        iny
        dez
        bne drce_cpp_loop
        clc
        rts
drce_cpp_stop:
        ;; A is already 0 here on the common path - write the NUL
        ;; terminator explicitly.
        sta dos_dirent_longfilename,x
        sec
        rts

;;         ========================

dos_readdir:

        ;; Get the current file entry, and advance pointer
        ;; This requires parsing the current directory entry onwards, accumulating
        ;; long filename parts as required.  We only support filenames to 64 chars,
        ;; so long names longer than that will get ignored.
        ;; LFN entries have an attribute byte of $0F (normally indicates volume label)
        ;; LFN entries use 16-bit unicode values. For now we will just keep the lower
        ;; byte of these

        ;; clear long file name data from last call
        ;;
        lda #0
        sta dos_dirent_longfilename_length

        ;; assess the EOF marker very early, to catch case where last read direntry
        ;; was the last direntry of the cluster
        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_mode,x
        cmp #dos_filemode_end_of_directory
        bne drd_continue
        lda #dos_errorcode_eof
        jmp dos_return_error

drd_continue:
        jsr dos_file_read_current_sector

!if DEBUG_HYPPO {
;; debug info, unsure what byte is being displayed...
;;
        +Checkpoint "-"

        ldy dos_current_file_descriptor_offset
        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y

        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty drdcp0+2
        stx drdcp0+3

        ldy dos_current_file_descriptor_offset
        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y

        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty drdcp0+0
        stx drdcp0+1

        jsr checkpoint
        !8 0
        !text "dos_readdir["
drdcp0: !text "xxyy]"
        !8 0

        jsr dumpsectoraddress        ;; debug
        jsr dumpfddata                ;; debug

;; end of debug
}

        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_mode,x
        cmp #dos_filemode_directoryaccess
        beq drd_isdir
        cmp #dos_filemode_end_of_directory
        bne drd_notadir

        lda #dos_errorcode_eof
        jmp dos_return_error

;;         ========================

drd_notadir:
        ;; refuse to read files as directories
        ;;
        lda #dos_errorcode_not_a_directory
        jmp dos_return_error

;;         ========================

drd_isdir:
        ;; Clear dirent structure
        ;; WARNING - Uses carnal knowledge to know that dirent structure is
        ;; 64+1+11+4+4+1 = 85 contiguous bytes
        ;;
        ldx #dos_dirent_structure_length-1
        lda #$00

drce1:  sta dos_dirent_longfilename,x
        dex
        bpl drce1

        ;; Read current sector
        ;;
        jsr dos_file_read_current_sector
        lbcc dos_return_error_already_set
+       jsr sd_map_sectorbuffer

drce_next_piece:

        ;; Offset in sector correctly indicates where we need to read.
        ;; Sectors are 512 bytes, so we can't just do a register index.
        ;; Instead we will setup a 16-bit pointer.
        ;;
        lda dos_current_file_descriptor_offset
        ora #dos_filedescriptor_offset_offsetinsector
        tax
        lda dos_file_descriptors,x
        sta <dos_scratch_vector
        lda dos_file_descriptors+1,x
        clc
        adc #$DE   ;; high byte of SD card sector buffer
        sta <(dos_scratch_vector+1)

        ;; (dos_scratch_vector) now has the address of the directory entry

!if DEBUG_HYPPO {
        phx        ;; as the code below clobbers X

        ;; print out filename and attrib
        ;;
        ldy #fs_fat32_dirent_offset_shortname
        ldx #0
eight31:
        lda (<dos_scratch_vector),y
        jsr makeprintable
        sta eight3,x
        iny
        inx
        cpx #11                ;; 11 chars in the filename (8+3)
        bne eight31
        ;;
        ;; attrib
        ;;
        ldy #fs_fat32_dirent_offset_attributes        ;; = 0x0B
        lda (<dos_scratch_vector),y
        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty eight3attrib+0
        stx eight3attrib+1
        ;;
        ;; char1
        ;;
        ldy #$00
        lda (<dos_scratch_vector),y
        tax                                ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty eight3char1+0
        stx eight3char1+1

        ;;

        jsr checkpoint
        !8 0
        !text " (8.3)+(ATTRIB)+(NAME[0]) = "
eight3: !text "FILENAMEEXT "
eight3attrib:
        !text "xx "
eight3char1:
        !text "xx"
        !8 0

        plx        ;; as the code above clobbers X
}

;;         ========================

        ;; first, check if the entry begins with $E5 marking a deleted file.
        ;; Entry entries we just ignore, as they are totally valid.

        ldy #fs_fat32_dirent_offset_shortname        ;; Y=0 (first char of entry)
        lda (<dos_scratch_vector),y
        cmp #$e5
        lbeq drd_deleted_or_invalid_entry
+
        cmp #$00  ;; NOTE: In Windows, I've seen #$00 markers equating to the end of direntries (i.e., stop iterating over direntries at this point)
        bne +
        ;; Empty entry, so skip over it
        jmp drd_deleted_or_invalid_entry
+
        ;; now check the attrib

        ldy #fs_fat32_dirent_offset_attributes        ;; = 0x0B
        lda (<dos_scratch_vector),y

        ;; check the kind of data we are looking at:
        ;; bit 5 = 1         -> is a Archive
        ;; bit 4 = 1         -> is a Directory
        ;; bit 3 = 1         -> is a Volume ID
        ;; bit 2 = 1         -> is a System
        ;; bit 1 = 1         -> is a Hidden
        ;; bit 0 = 1         -> is a Readonly

        tay        ;; for safe keeping

        ;; if bits xx3210 = xx1111 -> is a long filename
        ;; we process these differently to the standard (shortname) entries
        ;;
        and #$0f
        cmp #$0f                ;; %00001111 LFN entry special attribute value (xxxx1111)
        bne drce_cont0
        bra drce_longname        ;; MATCH -> must be LFN

drce_cont0:
        tya        ;; from safe keeping

        ;; if bit-3 = 1 -> Vol ID
        ;; we process the Vol ID different (for now)
        ;;
        and #$08
        cmp #$08                ;; %00001000 Vol-ID
        bne drce_cont2
        bra drce_cont_next_part	; Ignore it

drce_cont2:
        tya        ;; from safe keeping

        ;; check for bits 2 or 1 asserted
        ;; we should ignore these hidden/system files (for now)
        ;;
        and #$06                ;; %00000110
        beq drce_cont3        ;; branch if equal to zero (ie not Hidden OR System)

        ;; macOS creates the `.` and `..` entries as hidden. Special case `..`
        ;; so that it appears in listings. Some uses, like the Freezer, need it
        ;; visible to know how to navigate to the parent directory.
        ldx #11  ; length of dotdotshortname string
        ldy #fs_fat32_dirent_offset_shortname        ;; Y=0 (first char of entry)
-       lda (<dos_scratch_vector),y
        cmp dotdotshortname,y
        bne drce_ignore
        iny
        dex
        bne -

drce_cont3:
        ;; was not hidden/system, or Vol-ID, or LFN, or was special case "..",
        ;; so we process this entry regardless of if read-only (bit0) or not
        bra drce_normalrecord

drce_ignore:
        ;; Ignore hidden/system files for now
        ;; XXX We should have a flag to enable/disable this behaviour
        bra drce_cont_next_part

dotdotshortname:
        !text "..         "

;;         ========================

drce_longname:

disable_lfn_byte:
        jmp drce_cont_next_part         ;; First byte (jmp) self modifying fom syspart.asm. JMP = LFN disabled, BIT= LFN Enabled

        ;; make sure long entry type is "filename" (=$00)
        ;;
        ldy #fs_fat32_dirent_offset_lfn_type
        lda (<dos_scratch_vector),y
        lbne drce_normalrecord
+
        ;; Remember the checksum so drce_normalrecord can verify it
        ;; against the short entry it precedes (rejects a stale chain).
        ldy #fs_fat32_dirent_offset_lfn_checksum
        lda (<dos_scratch_vector),y
        sta dos_dirent_lfn_checksum

        ;; It's a long filename piece
        ;; byte 0 gives the position in the LFN of this piece.
        ;; Each piece has 13 16-bit unicode values.
        ;; For now, we will only use the lower byte.  later we should gather the
        ;; long filenames as UTF-16, and then convert them to UTF-8.

        ldy #fs_fat32_dirent_offset_lfn_part_number

        ;; assess if this is the first part in the list
        lda (<dos_scratch_vector),y
        pha
        and #$40  ;; bit4=1 means it's the first part in the list
        sta dos_first_vfat_chunk_in_list_flag

        ;; assess which part number it is
        pla
        and #$3f ;; mask out end of LFN indicator
        dec ;; subtract one, since pieces are numbered from 1 upwards

        ;; each piece has 13 chars, and we only allow 64 characters total, so any
        ;; piece number >4 can be ignored
        ;;
        cmp #5
        bcs drce_ignore_lfn_piece
        tax
        lda lfn_piece_offsets,x
        tax

        +Checkpoint "found LFN piece <start>"

        ;; Copy first part of LFN
        ;;
        ldy #fs_fat32_dirent_offset_lfn_part1_start
        ldz #fs_fat32_dirent_offset_lfn_part1_chars
        jsr drce_copy_lfn_part
        bcs drce_eot_in_filename

        ;; Copy second part of LFN
        ;;
        ldy #fs_fat32_dirent_offset_lfn_part2_start
        ldz #fs_fat32_dirent_offset_lfn_part2_chars
        jsr drce_copy_lfn_part
        bcs drce_eot_in_filename

        ;; Copy third part of LFN
        ;;
        ldy #fs_fat32_dirent_offset_lfn_part3_start
        ldz #fs_fat32_dirent_offset_lfn_part3_chars
        jsr drce_copy_lfn_part

drce_eot_in_filename:

        +Checkpoint "BGOK drce_eot_in_filename"

        ;; got all characters from this LFN piece
        ;;
        lda dos_first_vfat_chunk_in_list_flag
        beq +
        cpx dos_dirent_longfilename_length      ;; GI_NOTE: I'm suspicious of this part
        bcc drce_piece_didnt_grow_name_length   ;; We branch if x < dos_dirent_longfilename_length
        stx dos_dirent_longfilename_length      ;; in my case x=19, dos_dirent_longerfilename=18. So why store this?
        ;; cpx #$3f
        ;; bcs drce_eot_in_filename2               ;; We branch if x >= #$3f (63). Should this be #$40?
+
        ;; null terminate if there is space, for convenience
        ;; GI. Let's skip null terminator, as it is in the wrong place, and we wipe out dos_dirent_longfilename with zeroes each time anyway
        ;; lda #$00
        ;; sta dos_dirent_longfilename,x
        ;; stx dos_dirent_longfilename_length

drce_eot_in_filename2:

drce_piece_didnt_grow_name_length:

drce_ignore_lfn_piece:

        +Checkpoint "BGOK drce_ignore_lfn_piece"

        ;; We have finished processing this piece of long name.
        ;; bump directory entry, read next sector if required, and re-enter loop
        ;; above to keep accumulating

drce_cont_next:

        +Checkpoint "BGOK drce_cont_next"

        jsr dos_readdir_advance_to_next_entry
        bcc drce_no_more_pieces

        jmp drce_next_piece

drd_end_of_directory:
        ;; If we have pieces, then emit the final filename,
        ;; else return EOF on the directory by falling through to the following
        ;; Can we ever be in such a position?  Let's assume for the time being that
        ;; we can't.  If we start losing the last name in a directory list, then we
        ;; can worry about fixing it then.

        ;; FALL THROUGH to drce_no_more_pieces

;;         ========================

drce_no_more_pieces:
        +Checkpoint "FOUND END_OF_DIRECTORY"

        lda #dos_errorcode_eof
        jmp dos_return_error

;;         ========================


drce_cont_next_part:

        jsr dos_readdir_advance_to_next_entry
        lbcs dos_readdir
+       jmp dos_return_error_already_set

;;         ========================

drce_normalrecord:
        ;; PGS: We have found a short name.

        ;; start of short filename. store entry for use by fstat and rmfile
        jsr dos_readdir_storecurrententry

        +Checkpoint "processing SHORT-name"

        ;; store short name (fs_fat32_dirent_offset_shortname == 0, so
        ;; the source and dest offsets are identical - one register
        ;; suffices)
        ;;
;; this test has already been done
;;
;;         ; Ignore empty and deleted entries (first byte $00 or $E5 respectively)
;;         ;
;;         lda (<dos_scratch_vector),y
;;         beq drd_end_of_directory
;;         cmp #$e5
;;         beq drd_deleted_or_invalid_entry

        ldy #10
drce5:  lda (<dos_scratch_vector),y
        sta dos_dirent_shortfilename,y
        dey
        bpl drce5

        ;; If we saw preceding LFN pieces, verify the checksum matches
        ;; this short name - a mismatch means a stale/orphaned chain.
        lda dos_dirent_longfilename_length
        beq drce_skip_checksum_check
        jsr compute_lfn_checksum
        cmp dos_dirent_lfn_checksum
        beq drce_skip_checksum_check
        lda #0
        sta dos_dirent_longfilename_length
drce_skip_checksum_check:

        ;; If we have no long name, derive one from the short name.
        lda dos_dirent_longfilename_length
        bne drce_already_have_long_name
        jsr dos_derive_dotted_shortname

drce_already_have_long_name:

        ;; now copy attribute field and other useful data

        ;; starting cluster
        ;;
        ldy #fs_fat32_dirent_offset_clusters_low
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster
        iny
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+1

        ldy #fs_fat32_dirent_offset_clusters_high
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+2
        iny
        lda (<dos_scratch_vector),y
        sta dos_dirent_cluster+3


        ;; file length in bytes
        ;;
        ldy #fs_fat32_dirent_offset_file_length+3
        ldx #3
drce_fl:
        lda (<dos_scratch_vector),y
        sta dos_dirent_length,x
        dey
        dex
        bpl drce_fl

        ;; attributes
        ;;
        ldy #fs_fat32_dirent_offset_attributes
        lda (<dos_scratch_vector),y
        sta dos_dirent_type_and_attribs

        +Checkpoint "drce_fl populated fields"

        jsr dos_readdir_advance_to_next_entry
        bcs drce_not_eof

drce_is_eof:

        +Checkpoint "DEBUG drce_is_eof <!>"

        ;; We need to pass the error through here to indicate EOF in directory,
        ;; but in a way that can be defered to the next call to dos_readdir, because
        ;; we have a valid entry right now.  We do this with a special file mode which
        ;; is EOF of directory (dos_filemode_end_of_directory)
        ;;
        ldx dos_current_file_descriptor_offset
        lda #dos_filemode_end_of_directory
        sta dos_file_descriptors + dos_filedescriptor_offset_mode ,x

        ldx dos_current_file_descriptor_offset
        lda dos_file_descriptors + dos_filedescriptor_offset_mode,x

        sec
        rts

drce_not_eof:

        +Checkpoint "drce_not_eof CHECK<1/3>"

        ;; Ignore zero-length filenames (corresponding to empty directory entries)
        ;;
        lda dos_dirent_longfilename_length
        cmp #0
        beq l_dos_readdir

        +Checkpoint "drce_not_eof CHECK<2/3>"

        lda dos_dirent_shortfilename
        beq l_dos_readdir
        cmp #$20
        bne +
l_dos_readdir:
        jmp dos_readdir
+
        +Checkpoint "drce_not_eof CHECK<3/3>"

!if DEBUG_HYPPO {
        ldx dos_dirent_longfilename_length
        jsr lfndebug
}

        sec
        rts

;;         ========================

!if DEBUG_HYPPO {
lfndebug:
        ;; requires .X to be set
        ;;
                                        ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty fnmsg1-5
        stx fnmsg1-4

        ;; Show what we have in the filename so far
        ;;
        phx        ;; safekeep

        ldx #29
drce23: lda dos_dirent_longfilename,x
        jsr makeprintable
        sta fnmsg1,x
        dex
        bpl drce23

        plx        ;; unsafekeep

        jsr checkpoint
        !8 0
        !text "LFN(xx): " ;; the "xx" can be replaced with the name_length
fnmsg1: !text ".............................." ;; BG: why only 30 chars?
        !8 0

        rts
}

;;         ========================

drd_deleted_or_invalid_entry:

!if DEBUG_HYPPO {
        tax
                                        ;; convert .X to char-representation for display
        jsr checkpoint_bytetohex        ;; returns: .X and .Y (Y is MSB, X is LSB, print YX)
        sty ddie+0
        stx ddie+1

        jsr checkpoint
        !8 0
ddie:   !text "xx drd_deleted_or_invalid_entry"
        !8 0
}

        jsr dos_readdir_advance_to_next_entry
        lbcs dos_readdir
+
        jmp dos_return_error_already_set

;;         ========================

lfn_piece_offsets:
        !8 13*0,13*1,13*2,13*3,13*4

;;         ========================

;; Standard VFAT short-name checksum over dos_dirent_shortfilename's 11
;; bytes. Returns it in A. Keeps the running total in Y, not a
;; dos_scratch_byte_* global, since callers (e.g. rename) may have
;; their own state stashed in one across a findfile/readdir call.
compute_lfn_checksum:
        ldy #0
        ldx #0
clfnc1: tya
        lsr
        bcc clfnc2
        ora #$80
clfnc2: clc
        adc dos_dirent_shortfilename,x
        tay
        inx
        cpx #11
        bne clfnc1
        tya
        rts

;;         ========================

;; Compares dos_dirent_longfilename against dos_requested_filename
;; (length first, then byte-by-byte, uppercasing). Carry SET on match.
;; XXX - Needs to support * and ? - see
;; http:;;6502.org/source/strings/patmatch.htm for a routine to take
;; inspiration from.
dcntr_check_length_then_cmp:
        lda dos_dirent_longfilename_length
        tax
        cmp dos_requested_filename_len
        bne dclc_nomatch
        dex
        bmi dclc_match          ;; both zero-length: trivially equal
dclc_loop:
        lda dos_requested_filename,x
        jsr toupper
        cmp dos_dirent_longfilename,x
        bne dclc_nomatch
        dex
        bpl dclc_loop
dclc_match:
        sec
        rts
dclc_nomatch:
        clc
        rts

dos_dirent_compare_name_to_requested:
        ;; Try the (real or short-derived) long name first.
        jsr dcntr_check_length_then_cmp
        bcs dcntr_done

        ;; Also allow matching by the plain 8.3 short name.
        jsr dos_derive_dotted_shortname
        jsr dcntr_check_length_then_cmp
dcntr_done:
        rts

;; Rebuilds a dotted "NAME.EXT" string (trailing spaces trimmed, "."
;; omitted if no extension) from dos_dirent_shortfilename into
;; dos_dirent_longfilename, and sets dos_dirent_longfilename_length.
dos_derive_dotted_shortname:
        ;; copy name part (X addresses both arrays identically)
        ;;
        ldx #$00
ddsn7:  lda dos_dirent_shortfilename,x
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        cmp #$20            ;; space indicates end of short name before extension
        beq ddsn_insert_dot
        cpx #8
        bne ddsn7
        inx

ddsn_insert_dot:
        dex
        lda #'.'
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx

        ;; copy extension part
        ;;
        ldy #8
        ldz #0
ddsn6:  lda dos_dirent_shortfilename,y
        sta dos_dirent_longfilename,x
        stx dos_dirent_longfilename_length
        inx
        iny
        inz
        cpz #3  ;; short name extensions are <=3 chars
        beq ddsn_copied_extension

        ;; also terminate extensions early if they are <3 chars
        cmp #$20
        bne ddsn6

ddsn_copied_extension:

        ;; Trim spaces from the end of the filename
        cpx #0
        beq @filename0bytes
        lda #$20
        cmp dos_dirent_longfilename-1,x
        bne @nomorespaces
        dex
        bra ddsn_copied_extension

@nomorespaces:

        ;; And trim trailing . from file name in case extension
        ;; was all spaces. But don't trim it if the filename starts
        ;; with ., so that we don't mess up . and .. directories
        lda dos_dirent_longfilename-1,x
        ;; Is last char a . ?
        cmp #$2e
        bne @notrailingdot

@hastrailingdot:

        ;; Cut . from end of filename
        dex

@notrailingdot:

@filename0bytes:

        ;; null terminate short name for convenience in our debugging
        ;;
        lda #$00
        sta dos_dirent_longfilename,x

        ;; record length of short name
        stx dos_dirent_longfilename_length
        rts

;;         ========================

dos_readdir_advance_to_next_entry:

        ldy dos_current_file_descriptor_offset

        clc
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y
        adc #$20 ;; length of FAT32/VFAT directory entry
        sta dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +0,y
        bne dratne_done

        ;; Increment upper byte
        ;;
        lda dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y
        inc
        cmp #$01
        bne drce_end_of_sector
        sta dos_file_descriptors + dos_filedescriptor_offset_offsetinsector +1,y

dratne_done:
        sec
        rts

;;         ========================

drce_end_of_sector:

        ;; Reset pointer back to start of sector
        ;;
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+1,y

        jsr dos_file_advance_to_next_sector
        ; since we've changed sectors, read in new sector data
        bcc @skipreadsector
        jsr dos_file_read_current_sector
@skipreadsector:
        rts

;;         ========================

dos_set_current_file_from_dirent:

        ;; copy start cluster from dirent to start and current cluster
        ;;
        jsr dos_get_free_descriptor
        jsr dos_get_fd_offset_or_fail

        ;; set current cluster to start cluster
        ;; (Y runs $fc..$ff so "iny:bne" wraps to 0 after exactly 4
        ;; iterations, avoiding a separate cpy #4.)
        ;;
        ldy #$fc
dscffd1:
        lda dos_dirent_cluster-$fc,y
        sta dos_file_descriptors+dos_filedescriptor_offset_startcluster,x
        sta dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        inx
        iny
        bne dscffd1

        jsr dos_get_fd_offset_or_fail

        ;; set disk id
        ;;
        lda dos_disk_current_disk
        sta dos_file_descriptors+dos_filedescriptor_offset_diskid,x

        ;; set mode
        ;;
        lda #dos_filemode_readonly
        sta dos_file_descriptors+dos_filedescriptor_offset_mode,x

        ;; set sector in cluster (set to 0)
        ;;
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,x

        ;; set offset in sector (set to 0)
        ;;
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+0,x
        sta dos_file_descriptors+dos_filedescriptor_offset_offsetinsector+1,x

        ;; Get length of file, so that we can
        ;; limit load to reported length of file, instead assuming cluster
        ;; chain is correct length, and file ends on a cluster boundary
        ldx #$03
-       lda dos_dirent_length,x
        sta <dos_bytes_remaining,x
        dex
        bpl -

        sec
        rts

;;         ========================

dos_open_current_file:

        ;; copy start cluster to current cluster, and zero position in file
        ;;
        jsr dos_get_fd_offset_or_fail

        ;; Copy start cluster to current cluster
        ;;
        ldy #3
docf1:  lda dos_file_descriptors + dos_filedescriptor_offset_startcluster   ,x
        sta dos_file_descriptors + dos_filedescriptor_offset_currentcluster ,x
        inx
        dey
        bpl docf1

        jsr dos_get_file_descriptor_offset
        lda #$00

        ;; sectorincluster, offsetinsector, fileoffset are contiguous, which allows
        ;; us to clear these more efficiently.
        ;;
        ldy #6
docf2:  sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,x
        inx
        dey
        bne docf2

        jsr dos_get_file_descriptor_offset

        sec
        rts

;;         ========================

;; A must be $ff on entry. Marks all 4 file descriptor slots unallocated.
dos_clear_all_filedescriptors:
        sta dos_file_descriptors
        sta dos_file_descriptors+dos_filedescriptor_stride*1
        sta dos_file_descriptors+dos_filedescriptor_stride*2
        sta dos_file_descriptors+dos_filedescriptor_stride*3
        rts

;;         ========================

;; dos_get_file_descriptor_offset, propagating failure to the caller's
;; caller (via dos_return_error_already_set) instead of returning it.
dos_get_fd_offset_or_fail:
        jsr dos_get_file_descriptor_offset
        lbcc dos_return_error_already_set
+	rts

;;         ========================

        ;; Load A & X with the offset of the current file descriptor, relative to
        ;; dos_file_descriptors.

dos_get_file_descriptor_offset:

        lda dos_current_file_descriptor
        cmp #4
        bcs dos_bad_file_descriptor
        tax
        jsr dos_fd_number_to_offset
        tax
        sec
        rts

;;         ========================

dos_bad_file_descriptor:

        lda #dos_errorcode_invalid_file_descriptor
        jmp dos_return_error

;;         ========================

dos_set_current_cluster_from_file:

        ;; copy cluster number in file to current cluster
        ;;
        jsr dos_get_file_descriptor_offset
        bcc l2_dos_return_error_already_set

        ldy #$00
dfrcs1: lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        sta dos_current_cluster,y
        inx
        iny
        cpy #$04
        bne dfrcs1
        rts

;;         ========================

dos_file_read_current_sector:

        jsr dos_file_update_sector_offset
        jmp sd_readsector

;;         ========================

dos_file_write_current_sector:

        jsr dos_file_update_sector_offset
        jmp sd_writesector

;;         ========================

dos_file_update_sector_offset:

       jsr dos_get_file_descriptor_offset
        jsr dos_set_current_cluster_from_file
        jsr dos_cluster_to_sector

        ;; Add sector within cluster
        ;;
        jsr dos_get_file_descriptor_offset
        bcs gotFDOffset
l2_dos_return_error_already_set:
        jmp dos_return_error_already_set
gotFDOffset:

        ;; Set A to the offset of the sectorincluster field of the current
        ;; file descriptor
        ;;
        ora #dos_filedescriptor_offset_sectorincluster

        ;; Now put that offset in y, so that we can load the sector number in the
        ;; current cluster for the current file descriptor
        ;;
        tay
        lda dos_file_descriptors,y

        ;; add sector number in cluster to current sector number (which is the
        ;; start of the cluster)
        ;;
        jmp sdsector_add_uint8

;;         ========================

dos_file_advance_to_next_sector:

        ;; Increment file position offset by 2 pages
        ;;
        ldx dos_current_file_descriptor_offset

        lda dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0 ,x
        clc
        adc #$02
        sta dos_file_descriptors + dos_filedescriptor_offset_fileoffset+0 ,x
        bcc dfatns1
        inc dos_file_descriptors + dos_filedescriptor_offset_fileoffset+1 ,x
        bne dfatns1
        inc dos_file_descriptors + dos_filedescriptor_offset_fileoffset+2 ,x
dfatns1:

        ;; increase sector
        ;;
        inc dos_file_descriptors + dos_filedescriptor_offset_sectorincluster ,x
        lda dos_file_descriptors + dos_filedescriptor_offset_sectorincluster ,x
        ldy dos_disk_table_offset

        cmp dos_disk_table + fs_fat32_sectors_per_cluster ,y

        ;; and if necessary, advance to next cluster
        ;;
        bne +
        bra dos_file_advance_to_next_cluster
+
        sec
        rts

;;         ========================

dos_file_advance_to_next_cluster:

        ;; set to sector 0 in cluster
        ;;
        ldy dos_current_file_descriptor_offset
        lda #$00
        sta dos_file_descriptors+dos_filedescriptor_offset_sectorincluster,y

        ;; read chained cluster number for fs_clusternumber

        ;; FAT32 uses 32-bit cluster numbers.
        ;; the text below may be misleading, as we have 8 sectors per cluster
        ;; 512 / 4 = 128 cluster numbers per sector.
        ;; To get the sector of the FAT containin a particular
        ;; cluster entry, we thus need to shift the cluster number
        ;; right 7 bits.  Then we add the start sector number of the FAT.

        jsr dos_set_current_cluster_from_file

        ;; copy cluster to sector number
        ;;
        ldx #$03
dfanc1:
        lda <dos_current_cluster,x
        sta <dos_current_sector,x
        dex
        bpl dfanc1

        ;; Remember low byte of cluster number so that we can pull the
        ;; cluster number for the next cluster out of the FAT sector
        ;;
        lda <dos_current_cluster
        sta <dos_scratch_byte_1

        jsr dos_cluster_to_fat_sector

        jsr dos_remember_sd_sector

        ;; copy from current cluster to SD sector address register
        ;;
        ldx #$03
        php
dfanc41:
        lda <dos_current_cluster,x
        sta $d681,x
        dex
        bpl dfanc41

dfanc44:
        plp
        lda <dos_current_cluster,x
        adc #$00
        sta <dos_current_cluster,x
        php
        inx
        cpx #$04
        bne dfanc44

        plp

        ;; Read the FAT sector and extract the next cluster number into
        ;; the current file descriptor (shared with dos_rmfile_rmchainentry).
        jsr dos_read_next_cluster_from_fat
        beq dfanc_ok

        jsr dos_restore_sd_sector
        lda #dos_errorcode_invalid_cluster
        jmp dos_return_error

dfanc_ok:
        jsr dos_restore_sd_sector
        sec
        rts

;;         ========================

;; dos_read_next_cluster_from_fat[_mirrored]: caller must already have
;; set <dos_current_cluster and called dos_cluster_to_fat_sector, and
;; loaded $d681-4 with the resulting FAT sector (<dos_scratch_byte_1 =
;; the low byte of the OLD cluster number, as both callers already
;; arrange). Reads that FAT sector and extracts the next cluster
;; number into the current file descriptor. The _mirrored entry point
;; (used only by dos_rmfile_rmchainentry) also mirrors each read
;; low-half byte to $1800,y.
;; Returns A: 0=ok (valid data cluster), 1=eof marker, 2=invalid
;; (cluster 0). Clobbers X/Y/Z/<dos_scratch_byte_2.
;;
;; The mirrored/plain choice is passed on the stack (not a zero-page
;; scratch byte) because this can run nested inside a dos_readdir scan
;; (e.g. via getcwd), which relies on zptemp*/dos_scratch_byte_* still
;; holding its own state across such nested calls.
dos_read_next_cluster_from_fat_mirrored:
        lda #1
        pha
        bra drncff_common
dos_read_next_cluster_from_fat:
        lda #0
        pha
drncff_common:
        jsr sd_readsector
        bcs +
        pla
        jmp dos_return_error_already_set
+	jsr sd_map_sectorbuffer

        lda <dos_scratch_byte_1
        asl
        asl
        tax

        lda dos_current_file_descriptor_offset
        ora #dos_filedescriptor_offset_currentcluster
        tay
        sty <dos_scratch_byte_2

        ldz #$00
        lda <dos_scratch_byte_1
        and #$40
        bne drncff_gohigh
        pla
        bne drncff_low_mirrored

drncff_low_plain:
        lda sd_sectorbuffer,x
        sta dos_file_descriptors,y
        inx
        iny
        inz
        cpz #$04
        bne drncff_low_plain
        bra drncff_check

drncff_low_mirrored:
        lda sd_sectorbuffer,x
        sta dos_file_descriptors,y
        sta $1800,y
        inx
        iny
        inz
        cpz #$04
        bne drncff_low_mirrored
        bra drncff_check

drncff_gohigh:
        pla
drncff_high:
        lda sd_sectorbuffer+$100,x
        sta dos_file_descriptors,y
        inx
        iny
        inz
        cpz #$04
        bne drncff_high

drncff_check:
        ldy <dos_scratch_byte_2

        ;; First, only the lower 28-bits are valid
        lda dos_file_descriptors+3,y
        and #$0f
        sta dos_file_descriptors+3,y

        ;; cluster 0 is invalid
        lda dos_file_descriptors+3,y
        ora dos_file_descriptors+2,y
        ora dos_file_descriptors+1,y
        ora dos_file_descriptors,y
        bne drncff_notzero
        lda #2
        rts

drncff_notzero:
        ;; $?FFFFFF7 = bad cluster, $?FFFFFF8-$?FFFFFFF = end of file
        ;; (anything from $?FFFFFF0-F is treated as eof for simplicity)
        lda dos_file_descriptors+3,y
        cmp #$0f
        bne drncff_isok
        lda dos_file_descriptors+2,y
        and dos_file_descriptors+1,y
        cmp #$ff
        bne drncff_isok
        lda dos_file_descriptors,y
        and #$f0
        cmp #$f0
        bne drncff_isok
        lda #1
        rts

drncff_isok:
        lda #0
        rts

;;         ========================

        ;; Some routines disturb the current SD card sector in the buffer,
        ;; but where the caller might not expect or want this to happen.
        ;; For this reason we have the following convenience routines for
        ;; stashing and restoring the current ready sector.
dos_remember_sd_sector:
        ldx #3
-	lda $d681,x
        sta dos_stashed_sd_sector_number,x
        dex
        bpl -
        rts

dos_restore_sd_sector:
        ldx #3
-	lda dos_stashed_sd_sector_number,x
        sta $d681,x
        dex
        bpl -
        jmp sd_readsector


;;         ========================

dos_cluster_to_fat_sector:
        ;; Take <dos_current_cluster, as a cluster number,
        ;; and compute the absolute sector number on the SD card
        ;; where that cluster must live.
        ;; INPUT: <dos_current_cluster = cluster number
        ;; OUTPUT: <dos_current_cluster = absolute sector, which
        ;;         contains the FAT sector that has the FAT entry
        ;;         corresponding to the requested cluster number.

        ;; shift right 7 times = divide by 128
        ;;
        ldy #$07
dfanc2: clc
        ror <dos_current_cluster+3
        ror <dos_current_cluster+2
        ror <dos_current_cluster+1
        ror <dos_current_cluster+0
        dey
        bne dfanc2

        ;; add start of partition offset
        ;;
        ldy dos_disk_table_offset
        ldx #$00
        clc
        php
dfanc3: plp
        lda <dos_current_cluster,x
        adc dos_disk_table + fs_start_sector ,y
        sta <dos_current_cluster,x
        php
        iny
        inx
        cpx #$04
        bne dfanc3
        plp

        ;; add start of fat offset
        ;;
        ldy dos_disk_table_offset
        ldx #$00
        clc
        php
dfanc4: plp
        lda <dos_current_cluster,x
        adc dos_disk_table + fs_fat32_system_sectors ,y
        sta <dos_current_cluster,x
        php
        iny
        inx
        cpx #$02
        bne dfanc4

        plp

        rts

;;         ========================

!if DEBUG_HYPPO {
dos_print_current_cluster:

        ;; prints a message to the screen
        ;;
        ldx #<msg_clusternumber
        ldy #>msg_clusternumber
        jsr printmessage
        ldy #$00
        ldz <dos_current_cluster+3
        jsr printhex
        ldz <dos_current_cluster+2
        jsr printhex
        ldz <dos_current_cluster+1
        jsr printhex
        ldz <dos_current_cluster+0
        jsr printhex

        +Checkpoint "dos_print_current_cluster"

        rts
}

;;         ========================

dos_readfileintomemory:

        ;; assumes that filename is already set using "dos_setname", which
        ;; copies filename string into "dos_requested_filename",
        ;;        and sets length into "dos_requested_filename_length".
        ;;
        ;; assumes that the 32-bit load-address pointer is set by
        ;; storing load-address at "dos_file_loadaddress+{0-3}"

        ;; print some debug information
        ;;
        ;;         jsr dos_print_current_cluster

        ;; Clear number of sectors read
        ldx #$00
        stx <dos_sectorsread
        stx <dos_sectorsread+1

        jsr dos_findfirst
        bcc l_dos_return_error_already_set
        ;; close directory now that we have what we were looking for ...
        jsr dos_closefile

        jsr dos_openfile
        bcc l_dos_return_error_already_set

        jsr sd_map_sectorbuffer

        bra drfim_sector_loop

l_dos_return_error_already_set:
        jmp dos_return_error_already_set

;;         ========================

drfim_sector_loop:

        jsr dos_file_read_current_sector
        bcc drfim_eof

        ;; copy sector to memory
        ;;

        ;; Work out how many bytes of this page we need to read
        jsr dos_load_y_based_on_dos_bytes_remaining

        ldx #$00
        ldz #$00

        ;; Actually write the bytes to memory that have been loaded
drfim_rr1:
        lda sd_sectorbuffer,x                ;; is $DE00
        sta [<dos_file_loadaddress],z
        inz ;; dest offset
        inx ;; src offset
        dey ;; bytes in page to copy
        bne drfim_rr1

        inw <dos_file_loadaddress+1

        ;; Work out how many bytes of this page we need to read
        jsr dos_load_y_based_on_dos_bytes_remaining

        ;; Actually write the bytes to memory that have been loaded
drfim_rr1b:
        lda sd_sectorbuffer+$100,x        ;; is $DF00
        sta [<dos_file_loadaddress],z
        inz ;; dest offset
        inx ;; src offset
        dey ;; bytes in page to copy
        bne drfim_rr1b

        jsr dos_file_advance_to_next_sector
        bcc drfim_eof

        ;; We only allow loading into a 16MB space
        ;; Provided that we check the load address before starting,
        ;; this ensures that a user-land request cannot load a huge file
        ;; that eventually overwrites the hypervisor and results in privilege
        ;; escalation.
        ;; This restriction to a 16MB space is implemented by only incrementing the middle 2 bytes of
        ;; the address, instead of all 3 upper bytes.
        ;;
        inw <dos_file_loadaddress+1

        ;; Increment number of sectors read (16 bit valie)
        ;;
        inc <dos_sectorsread
        bne drfim_sector_loop

        inc <dos_sectorsread+1
        ;; see if there is another sector
        bne drfim_sector_loop

        jsr dos_closefile

        ;; File is >65535 sectors (32MB), report error
        ;;
        lda #dos_errorcode_file_too_long
        jmp dos_return_error

;;         ========================

drfim_eof_pop_pc:
        pla
        pla

drfim_eof:

        jsr dos_closefile
        jmp dos_return_success

dos_load_y_based_on_dos_bytes_remaining:
        ldy #$00
        lda <dos_bytes_remaining+1
        ora <dos_bytes_remaining+2
        ora <dos_bytes_remaining+3
        bne +
        lda <dos_bytes_remaining+0
        ;; If no more bytes to read, then jump to EOF
        beq drfim_eof_pop_pc
        ldy <dos_bytes_remaining+0
        lda #$00
        sta  <dos_bytes_remaining+0
        rts
+
        lda <dos_bytes_remaining+1
        sec
        sbc #$01
        sta <dos_bytes_remaining+1
        lda <dos_bytes_remaining+2
        sbc #0
        sta <dos_bytes_remaining+2
        lda <dos_bytes_remaining+3
        sbc #0
        sta <dos_bytes_remaining+3
        rts

dos_updatereturnsize:

;; 	ldx <dos_bytes_remaining+3
;; 	jsr checkpoint_bytetohex
;; 	sty lenhex+0
;; 	stx lenhex+1
;; 	ldx <dos_bytes_remaining+2
;; 	jsr checkpoint_bytetohex
;; 	sty lenhex+2
;; 	stx lenhex+3
;; 	ldx <dos_bytes_remaining+1
;; 	jsr checkpoint_bytetohex
;; 	sty lenhex+4
;; 	stx lenhex+5
;; 	ldx <dos_bytes_remaining+0
;; 	jsr checkpoint_bytetohex
;; 	sty lenhex+6
;; 	stx lenhex+7

;; 	jsr checkpoint
;; 	!8 0
;; 	ascii("$")
;; lenhex:
;; 	ascii("%%%%%%%% bytes remaining.")
;; 	!8 0

        lda <dos_bytes_remaining+0
        ora <dos_bytes_remaining+1
        ora <dos_bytes_remaining+2
        ora <dos_bytes_remaining+3
        bne +

        ;; End of file: So zero bytes returned
        lda #$00
        sta hypervisor_x
        sta hypervisor_y
        clc
        rts

+
        ;; Indicate how many bytes we are returning
        ldx #<$0200
        ldy #>$0200

        lda <dos_bytes_remaining+2
        ora <dos_bytes_remaining+3
        bne +   ;; lots more to read
        lda <dos_bytes_remaining+1
        cmp #2
        bcs +   ;; at least a whole sector more to read

        ;; Only a fractional part of a sector to read, so zero out remaining

        ;; Update number of bytes for fractional sector read
        ldx <dos_bytes_remaining+0
        ldy <dos_bytes_remaining+1

        lda #$00
        sta <dos_bytes_remaining+0
        ;; Actually make it look like 1 sector to go, so we decrement that to zero
        ;; immediately below
        lda #$02
        sta <dos_bytes_remaining+1
        ;; FALL THROUGH
+

        ;; Deduct one sector from the remaining
        lda <dos_bytes_remaining+1
        sec
        sbc #2
        sta <dos_bytes_remaining+1
        lda <dos_bytes_remaining+2
        sbc #0
        sta <dos_bytes_remaining+2
        lda <dos_bytes_remaining+3
        sbc #0
        sta <dos_bytes_remaining+3

        ;; Store number of bytes read in X and Y for calling process
        stx hypervisor_x
        sty hypervisor_y

        jmp sd_map_sectorbuffer

dos_readfile:

        jsr dos_updatereturnsize
        bcs +
        rts

+	;; Now read sector and return
        jsr dos_file_read_current_sector
        bcs drwf_readwritesuccess
        rts

;;         ========================

dos_writefile:

        jsr dos_updatereturnsize
        bcs +
        rts

+	;; Now write sector and return
        jsr dos_file_write_current_sector
        bcs drwf_readwritesuccess
        rts

drwf_readwritesuccess:
        jsr dos_file_advance_to_next_sector

        sec
        rts

;;         ========================

;; Called with dos_scratch_vector pointing at a short entry whose name
;; bytes are still intact. Walks backward through the same sector, 32
;; bytes at a time, marking every immediately-preceding LFN piece
;; (attribute $0F) whose checksum matches this short entry's name as
;; deleted ($E5). Stops at the first non-matching entry, an
;; already-deleted entry, or the start of the sector buffer. Doesn't
;; write to disk itself. Uses zptempp2 as its walking pointer; doesn't
;; touch dos_scratch_vector.
dos_delete_preceding_lfn_pieces:
        lda <dos_scratch_vector
        sta <zptempp2
        lda <(dos_scratch_vector+1)
        sta <(zptempp2+1)

        ;; Compute the checksum of this short entry's name, keeping
        ;; the running value in A (Y is the byte index here).
        lda #0
        ldy #0
dlp_cksum:
        lsr
        bcc +
        ora #$80
+       clc
        adc (<zptempp2),y
        iny
        cpy #11
        bne dlp_cksum
        sta <dos_scratch_byte_1

dlp_loop:
        ;; back up 32 bytes, stop if that passed the start of the
        ;; sector buffer ($de00)
        lda <zptempp2
        sec
        sbc #32
        sta <zptempp2
        bcs +
        dec <(zptempp2+1)
+
        lda <(zptempp2+1)
        cmp #$de
        bcc dlp_done

        ;; check attribute is exactly $0F and checksum matches
        ldy #fs_fat32_dirent_offset_attributes
        lda (<zptempp2),y
        cmp #$0f
        bne dlp_done
        ldy #fs_fat32_dirent_offset_lfn_checksum
        lda (<zptempp2),y
        cmp <dos_scratch_byte_1
        bne dlp_done
        ldy #0
        lda #$e5
        sta (<zptempp2),y
        bra dlp_loop

dlp_done:
        rts

;;         ========================

dos_rmfile:
        jsr dos_goto_direntstart_and_point_scratch_vector
        jsr dos_delete_preceding_lfn_pieces

        ldy #$00
        lda #$e5
        sta (<dos_scratch_vector),y

        ;; Write the erased dirent, then mirror to FAT2.
        jsr dos_write_sector_and_fat2_mirror

        ldx #$03
-       lda dos_dirent_cluster+0,x
        sta <dos_current_cluster+0,x
        dex
        bpl -

        ; start clearing fat entries until eof or fail
-       jsr dos_rmfile_rmchainentry
        bcc +
        jmp -

+       sec
        rts

dos_rmfile_rmchainentry:

        ;; Remember low byte of cluster number so that we can pull the
        ;; cluster number for the next cluster out of the FAT sector
        lda <dos_current_cluster
        sta <dos_scratch_byte_1

        jsr dos_cluster_to_fat_sector

        ;; copy from current cluster to SD sector address register
        ldx #$03
        php
drf2:   lda dos_current_cluster,x
        sta $d681,x
        dex
        bpl drf2

drf3:   plp
        lda <dos_current_cluster,x
        adc #$00                                ; carry (set/cleared at end of dos_cluster_to_fat_sector)
        sta <dos_current_cluster,x
        php
        inx
        cpx #$04
        bne drf3

        plp

        ;; Read the FAT sector and extract the next cluster number into
        ;; the current file descriptor (shared with
        ;; dos_file_advance_to_next_cluster). Also mirrors the low-half
        ;; bytes to $1800,y - rmfile-only behavior.
        jsr dos_read_next_cluster_from_fat_mirrored
        cmp #2
        beq drf_fail
        pha                        ;; 0=ok, 1=eof - remember across the clearwrite call
        jsr drf_clearwriteandincreasesector
        pla
        beq drf_ok2
        clc
        rts
drf_ok2:
        sec
        rts

drf_fail:
        clc
        rts

drf_clearwriteandincreasesector
        lda <dos_scratch_byte_1
        asl
        asl
        tax

        ldz #$00
        lda <dos_scratch_byte_1
        and #$40
        bne drf_ok_clearinhighsector

drf_ok_clearinlowsector:
        lda #$00
-       sta sd_sectorbuffer,x
        inx
        inz
        cpz #$04
        bne -
        bra drf_ok_cleardone

drf_ok_clearinhighsector:
        lda #$00
-       sta sd_sectorbuffer+$100,x
        inx
        inz
        cpz #$04
        bne -

drf_ok_cleardone:
        jsr sd_writesector
        lda dos_file_descriptors+0,y
        sta <dos_current_cluster+0
        lda dos_file_descriptors+1,y
        sta <dos_current_cluster+1
        lda dos_file_descriptors+2,y
        sta <dos_current_cluster+2
        lda dos_file_descriptors+3,y
        sta <dos_current_cluster+3
        rts

;;         ========================

dos_fstat:

        ;; Set up the userland transfer area.  (Previously this was never
        ;; called, so fstat wrote its result through whatever stale copy-region
        ;; vector a prior, unrelated trap had left behind.)
        jsr hypervisor_setup_copy_region
        bcc dos_fstat_done

        ;; rewind to start of directory entry
        jsr dos_goto_direntstart

        ldy #32
        lda dos_current_file_descriptor_offset
        ora #dos_filedescriptor_offset_offsetinsector
        tax
        lda dos_file_descriptors,x
        sta (<hypervisor_userspace_copy_vector),y       ; write directory entry offset to userland+32
        sta <dos_scratch_vector
        lda dos_file_descriptors+1,x
        iny
        sta (<hypervisor_userspace_copy_vector),y       ; write directory entry offset to userland+33
        clc
        adc #$de   ;; high byte of SD card sector buffer
        sta <(dos_scratch_vector+1)

        ldy #31                                      ;; copy first 32 bytes of directory entry to userland+0
tdfs:   lda (<dos_scratch_vector),y
        sta (<hypervisor_userspace_copy_vector),y
        dey
        bpl tdfs

        sec
dos_fstat_done:
        rts

;;         ========================

dos_setname:

        ;; INPUT: .X .Y = pointer to filename,
        ;;                 filename string must be terminated with $00
        ;;                 filename string must be <= $3F chars

        stx <dos_scratch_vector
        sty <(dos_scratch_vector+1)
        ldy #$00

lr11:   lda (<dos_scratch_vector),y
        sta dos_requested_filename,y
        beq dsn_eon
        iny
        cpy #$40
        bne lr11

        lda #0
        sta dos_requested_filename_len
        lda #dos_errorcode_name_too_long
        clc
        rts

dsn_eon:
        sty dos_requested_filename_len

        sec
        rts

;;         ========================

        ;; Flags lookup tables
        ;; drive 0    drive 1    drive 0+1  drive 0+1
dos_attach_imgena_bits          ;; $d68b
        !8 %00000111, %00111000, %00111111, %00111111
dos_attach_typeflg_bits         ;; $d68b/a
        !8 %01000000, %10000000, %11000000, %11000000
dos_attach_realdrv_bits         ;; $d6a1
        !8 %00000001, %00000100, %00000101, %00000101

dos_attach:
        ;; NEW CALL DOS 1.3
        ;;
        ;; handles both attaching and detaching images and real drives
        ;;
        ;; X.0 - DRVNUM  select drive 0 or 1
        ;; X.1 - BOTHDRV (MODE=detach) selects both drives
        ;; X.6 - NOREAL  (MODE=detach) don't attach real drive if set
        ;; X.7 - MODE    select mode 0 - attach, 1 - detach

        ;; set the attach bits according to the selected drives
        txa
        bmi @detach_multi_drive ;; only detach supports both drives at once
        and #$01                ;; limit to 1
@detach_multi_drive:
        and #$03                ;; limit to 3
        tay                     ;; offset into dos_attach_*_bits tables

        txa                     ;; sets N and Z flags
        bpl dos_diskattach      ;; bit 7 not set (N flag), so we want to attach

        and #$40
        tax                     ;; we only need the noreal flag later

        ;; now we detach the drives
        lda dos_attach_typeflg_bits,y
        trb $d68a               ;; clear d64/d71 flags
        ora dos_attach_imgena_bits,y
        trb $d68b		;; clear mount, d81/d65 flags

        lda dos_attach_realdrv_bits,y
        cpx #$40                ;; check for noreal flag
        beq @attach_detach_noreal
        tsb $d6a1               ;; enable real drive(s)
        lda #0
        bra @attach_detach_flags
@attach_detach_noreal:
        trb $d6a1               ;; disable real drive(s)
        lda #d81_image_flag_noreal

        ;; set mount flags in currenttask
@attach_detach_flags:
        cpy #$00
        bne @attach_detach_1
@attach_detach_both:
        sta currenttask_d81_image0_flags
        bra @attach_detach_flags_done
@attach_detach_1:
        sta currenttask_d81_image1_flags
        cpy #$02
        bcs @attach_detach_both
@attach_detach_flags_done:

        jmp dos_return_success

dos_diskattach:
        ;; dos_attach_bits determines on which drive it works
        ;;
        ;; Assumes only that D81 file name has been set with dos_setname.
        ;;
        sty <dos_attach_offset  ;; save Y offset into dos_attach_*_bits

        ;; Check if the filename of the disk image is too long
        ldx dos_requested_filename_len
        cpx #d81_image_max_namelen
        bcc @d81lenok
        lda #dos_errorcode_name_too_long
        jmp dos_return_error

@d81lenok
        jsr dos_findfile
        bcs @d81a1

        ;; dos_findfile sets the error
        jmp dos_return_error_already_set

;;         ========================

@d81a1:
        ;; Why do we call closefile here?
        ;; -> because dos_findfile/first only closes on file_not_found
        jsr dos_closefile

        jsr dos_checkimage
        bcs @d81a1a
        jmp dos_return_error_already_set

@d81a1a:
        ;; copy sector number from $D681 to DxSTARTSEC (D68C or D690)
        ;;
        ldz #$03                ;; disk 0 is D68C-D68F
        lda <dos_attach_offset  ;; fetch disk offset
        beq @attach_disk_0
        ldz #$07                ;; disk 1 is D690-D693

        lda #%00000001
        bit $d68b               ;; check if disk 0 is image
        beq @attach_copy_sector ;; no image -> proceed
        bra @attach_check_double

@attach_disk_0:
        lda #%00001000
        bit $d68b               ;; check if disk 1 is image
        beq @attach_copy_sector ;; no image -> proceed

@attach_check_double
        tza
        eor #$04
        tay
        ldx #$03
-       lda $d681,x		;; resolved sector number
        cmp $d68c,y  		;; sector number of disk image
        bne @attach_copy_sector
        dey
        dex
        bpl -

        ;; same sector number, error out
        lda #dos_errorcode_double_attach
        jmp dos_return_error

@attach_copy_sector:
        tza
        tay
        ldx #$03
-       lda $d681,x		;; resolved sector number
        sta $d68c,y  		;; sector number of disk image
        dey
        dex
        bpl -

        ;; disable real floppy
        ldy <dos_attach_offset
        lda dos_attach_realdrv_bits,y
        trb $d6a1

        ;; Set flags to indicate it is mounted (and read-write).
        ;; clear D65 mega disk flag,
        ;; But don't mess up the flags for the 2nd drive
        lda dos_attach_imgena_bits,y
        tsb $d68b
        ;; Clear D64 flag
        lda dos_attach_typeflg_bits,y
        tax
        trb $d68a

        ;; Check what dos_checkimage detected
        lda <disk_lasttype
        cmp #64
        bne @not_d64

        ;; Set D64 flag
        txa
        tsb $d68a
        bra @d81attach_typeset

@not_d64:
        cmp #71
        bne @not_d71

        ;; D71 disk image
        ;; Set both the D64 and the D65 flags to mean "big D64" = D71 image
        txa
        tsb $d68a
        tsb $d68b
        bra @d81attach_typeset

@not_d71:
        cmp #65
        bne @d81attach_typeset

        ;; D65 disk image
        ;; Set megadisk flag
        txa
        tsb $d68b

@d81attach_typeset:
        cpx #$80
        beq @d81attach1_typeset

        +Checkpoint "dos_attach 0 <success>"

        ;; Save name and set mount flag for disk image in process descriptor block
        lda #(d81_image_flag_mounted | d81_image_flag_write_en)
        sta currenttask_d81_image0_flags

        ldx dos_requested_filename_len

        ;; Name not too long, save name and length
        stx currenttask_d81_image0_namelen
        ldx #0
-       lda dos_requested_filename,x
        sta currenttask_d81_image0_name,x
        inx
        cpx currenttask_d81_image0_namelen
        bne -

        bra @attach_success

@d81attach1_typeset:

        +Checkpoint "dos_attach 1 <success>"

        ;; Save name and set mount flag for disk image in process descriptor block
        lda #(d81_image_flag_mounted | d81_image_flag_write_en)
        sta currenttask_d81_image1_flags

        ldx dos_requested_filename_len

        ;; Name not too long, save name and length
        stx currenttask_d81_image1_namelen
        ldx #0
-       lda dos_requested_filename,x
        sta currenttask_d81_image1_name,x
        inx
        cpx currenttask_d81_image1_namelen
        bne -

@attach_success:
        jmp dos_return_success

dos_checkimage:
        ;; now we need to check that the file is long enough,
        ;; and also that the clusters are contiguous.

        ;; Start by opening the file
        ;;
        jsr dos_set_current_file_from_dirent
        bcc @fileNotOpenedOk

        jsr dos_openfile
        bcs @fileOpenedOk
@fileNotOpenedOk:
        jmp dos_return_error_already_set
@fileOpenedOk:

        ;; work out how many clusters we need
        ;; We need 1600 sectors, so halve for every zero tail
        ;; bit in sectors per cluster.  we can do this because
        ;; clusters in FAT must be 2^n sectors.
        ;;
        ;; TODO: D65 clusters are not calculated yet, but hardcoded below
        ;;
        lda #$00
        sta <d81_clustercount
        sta <d81_clustercount+1
        lda #<1600
        sta <d81_clustersneeded
        lda #>1600
        sta <d81_clustersneeded+1
        ;; 1541 - rounded up to 512b sectors 344*512 = 176128, D64 = 174848
        lda #<344
        sta <d64_clustersneeded
        lda #>344
        sta <d64_clustersneeded+1
        ;; 1571 - rounded up to 512b sectors 688*512 = 352256, D71 = 349696
        lda #<688
        sta <d71_clustersneeded
        lda #>688
        sta <d71_clustersneeded+1

        ;; get sectors per cluster of disk
        ;;
        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
        taz

l94:    tza
        and #$01
        bne d81firstcluster
        tza
        lsr
        taz
        lsr <d81_clustersneeded+1
        ror <d81_clustersneeded
        lsr <d64_clustersneeded+1
        ror <d64_clustersneeded
        lsr <d71_clustersneeded+1
        ror <d71_clustersneeded
        bra l94

d81firstcluster:
        ;; Get current cluster of D81 file, so that
        ;; we can check that clusters in file are contiguous
        ;;
        ldx dos_current_file_descriptor_offset
        ldy #0

l94b:   lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        sta d81_clusternumber,y
        inx
        iny
        cpy #4
        bne l94b

d81nextcluster:
        ;; Now read through clusters and make sure that all is
        ;; well.

        ;; check that it matches expected cluster number
        ;;
        ldx dos_current_file_descriptor_offset
        ldy #0

l94a:   lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        cmp d81_clusternumber,y
        lbne d81isfragged
not_a_frag:
        inx
        iny
        cpy #4
        bne l94a

        ;; increment number of clusters found so far
        ;;
        inc <d81_clustercount
        bne l96
        inc <d81_clustercount+1
        beq d81wronglength      ;; overflow means wrong length
l96:

        ;; increment expected cluster number
        ;;
        clc
        lda <d81_clusternumber
        adc #$01
        sta <d81_clusternumber
        lda <d81_clusternumber+1
        adc #$00
        sta <d81_clusternumber+1
        lda <d81_clusternumber+2
        adc #$00
        sta <d81_clusternumber+2
        lda <d81_clusternumber+3
        adc #$00
        sta <d81_clusternumber+3

        jsr dos_file_advance_to_next_cluster
        bcs d81nextcluster

        +Checkpoint "dos_checkimage <measured end of image>"

        jsr dos_closefile

        ;; we have read to end of D81 file, and it is contiguous
        ;; now check that it is the right length

        ;; It might also be a D64 (1541) or D71 (1571) disk image,
        ;; so check for 683x256/4096 = 42.6875 = 43 clusters or
        ;; double that for D71
        lda <d81_clustercount+1
        cmp <d64_clustersneeded+1
        bne not_1541
        lda <d81_clustercount
        cmp <d64_clustersneeded
        bne not_1541_2

        ;;  IS a d64 sized file
        lda #64
        bra d81_is_good

not_1541_2:
        lda <d81_clustercount+1
not_1541:
        cmp <d71_clustersneeded+1
        bne not_1571
        lda <d81_clustercount
        cmp <d71_clustersneeded
        bne not_1571_2

        ;; IS a d71 sized file
        lda #71
        bra d81_is_good

not_1571_2:
        lda <d81_clustercount+1
not_1571:
        ;; First check if we read enough for 85 tracks x 64 sectors x 2 sides = 5,570,560 bytes
        ;; = 1,360 clusters = $0550 clusters
        ;; XXX - This currently assumes 8 sectors per cluster = 4KB sectors
        cmp #$05
        bne not_mega_floppy
        lda <d81_clustercount
        cmp #$50
        bne not_mega_floppy_2

        lda #65
        bra d81_is_good

not_mega_floppy_2:
        lda <d81_clustersneeded+1
not_mega_floppy:
        ;; D81 image?
        cmp <d81_clustercount+1
        bne d81wronglength
        lda <d81_clustersneeded
        cmp <d81_clustercount
        bne d81wronglength

        lda #81

d81_is_good:
        ;; disk image size is good. save type on stack for later
        sta <disk_lasttype

        ;; Get cluster number again, convert to sector, and copy to
        ;; SD controller FDC emulation disk image offset registers
        ;;
        ldx dos_current_file_descriptor_offset
        ldy #0

l94c:   lda dos_file_descriptors+dos_filedescriptor_offset_startcluster,x
        sta dos_current_cluster,y
        inx
        iny
        cpy #4
        bne l94c

        jsr dos_cluster_to_sector

        jmp dos_return_success

;;         ========================

d81wronglength:
        +Checkpoint "dos_attach <wrong length>"

        lda #dos_errorcode_image_wrong_length
        jmp dos_return_error

;;         ========================

d81isfragged:
        +Checkpoint "dos_attach <fragmented>"

        ;; close dangeling open descriptor
        jsr dos_closefile

        lda #dos_errorcode_image_fragmented
        jmp dos_return_error

;;         ========================

sdsector_add_uint8:

        pha
        lda #0
        tax
        tay
        taz
        pla
        ;; FALL THROUGH to sdsector_add_uint32

sdsector_add_uint32:

        ;; Add the 32-bit value contained in A,X,Y,Z to
        ;; $D681-$D684, the SD card sector number.
        ;;
        clc
        adc $D681
        sta $D681
        txa
        adc $d682
        sta $d682
        tya
        adc $d683
        sta $d683
        tza
        adc $d684
        sta $d684
        ldz #$00
        rts

;;         ========================

sdsector_add_uint32_from_disktable:

        ora dos_disk_table_offset
        tay
        ldx #$00
        clc
        php
l23:    plp
        lda $D681,x
        adc dos_disk_table,y
        sta $D681,x
        php
        iny
        inx
        cpx #$04
        bne l23
        plp
        rts

;;         ========================

makeprintable:
        ;; Convert unprintable ASCII characters to question marks

        cmp #$20
        bcc unprintable
        cmp #$7f
        bcs unprintable
        rts

unprintable:
        lda #$3f
        rts

;;         ========================
