;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.

;;     Defragmentation of a single file, so that fragmented disk images
;;     (D81/D64/D71) can be mounted.
;;
;;     The F011 disk image emulation only knows a single start sector
;;     ($D68C-$D68F / $D690-$D693) and assumes the image is stored
;;     contiguously on the SD card. dos_defrag_current copies a
;;     fragmented file into a run of free, contiguous clusters and then
;;     re-points the existing directory entry to it.
;;
;;     Order of operations (chosen so that an interruption at any point
;;     can at worst leave lost clusters, never a damaged file):
;;       1. Check whether the file is fragmented at all (read only).
;;       2. Work out how many clusters are needed (from the file length).
;;       3. Verify that the remembered directory entry really belongs to
;;          the file (read only).
;;       4. Find a run of free clusters (read only).
;;       5. Copy the file sector by sector into that run. The clusters are
;;          still marked free in the FAT, so nothing references them yet.
;;       6. Write the new cluster chain into both FATs.
;;       7. Point the directory entry at the new chain (one sector write;
;;          name, long file name, dates and length stay untouched).
;;       8. Free the old cluster chain in both FATs.
;;
;;     Input: dos_dirent_* and dos_direntstart_* describe the file, as left
;;            behind by dos_findfile.
;;     Output: C=1 on success (also if the file was not fragmented),
;;             dos_dirent_cluster updated to the new start cluster.
;;             C=0 on failure, dos_error_code set. Nothing on the card has
;;             been changed when an error is returned before step 6.
;;     ---------------------------------------------------------------- */

dos_defrag_current:

        +Checkpoint "dos_defrag_current"

        jsr sd_map_sectorbuffer

        ;; ---- 1. Is the file fragmented at all? ----
        jsr dos_openfile
        bcs +
        rts
+
        ldq dos_dirent_cluster
        stq dfg_prev
        ldz #$00
@walk:
        jsr dos_file_advance_to_next_cluster
        bcc @contiguous                         ;; end of chain reached

        ldq dfg_prev
        clc
        adcq Qone
        stq dfg_prev
        ldz #$00

        ldx dos_current_file_descriptor_offset
        ldy #0
-       lda dos_file_descriptors+dos_filedescriptor_offset_currentcluster,x
        cmp dfg_prev,y
        bne @fragmented
        inx
        iny
        cpy #4
        bne -
        bra @walk

@contiguous:
        jsr dos_closefile
        +Checkpoint "dos_defrag_current <not fragmented>"
        jmp dos_return_success

@fragmented:
        jsr dos_closefile

        ;; ---- 2. Sectors and clusters needed ----
        ;; dfg_left = ceil(length / 512)
        ldq dos_dirent_length
        clc
        adcq dfg_c511
        stq dfg_val
        ldz #$00
        lda dfg_val+3
        lsr
        sta dfg_left+2
        lda dfg_val+2
        ror
        sta dfg_left+1
        lda dfg_val+1
        ror
        sta dfg_left+0
        lda #$00
        sta dfg_left+3
        ora dfg_left+2
        ora dfg_left+1
        ora dfg_left+0
        bne +
        lda #dos_errorcode_image_wrong_length   ;; empty file
        jmp dos_return_error
+
        ;; dfg_need = ((dfg_left - 1) >> log2(sectors per cluster)) + 1
        ldq dfg_left
        sec
        sbcq Qone
        stq dfg_need
        ldz #$00
        ldx dos_disk_table_offset
        lda dos_disk_table+fs_fat32_sectors_per_cluster,x
-       lsr
        beq +
        lsr dfg_need+3
        ror dfg_need+2
        ror dfg_need+1
        ror dfg_need+0
        bra -
+
        ldq dfg_need
        clc
        adcq Qone
        stq dfg_need

        ;; dfg_limit = cluster count + 2 (first cluster number past the end)
        ldx dos_disk_table_offset
        ldy #0
-       lda dos_disk_table+fs_fat32_cluster_count,x
        sta dfg_limit,y
        inx
        iny
        cpy #4
        bne -
        ldq dfg_limit
        clc
        adcq Qone
        clc
        adcq Qone
        stq dfg_limit
        ldz #$00

        ;; ---- 3. Check the remembered directory entry ----
        jsr dfg_read_dirent
        ldy #fs_fat32_dirent_offset_clusters_low
        lda (<dos_scratch_vector),y
        cmp dos_dirent_cluster+0
        bne @badentry
        iny
        lda (<dos_scratch_vector),y
        cmp dos_dirent_cluster+1
        bne @badentry
        ldy #fs_fat32_dirent_offset_clusters_high
        lda (<dos_scratch_vector),y
        cmp dos_dirent_cluster+2
        bne @badentry
        iny
        lda (<dos_scratch_vector),y
        cmp dos_dirent_cluster+3
        beq +
@badentry:
        lda #dos_errorcode_invalid_cluster
        jmp dos_return_error
+

        ;; ---- 4. Find a run of dfg_need free clusters ----
        jsr dfg_find_free
        bcs +
        +Checkpoint "dos_defrag_current <no space>"
        lda #dos_errorcode_no_space
        jmp dos_return_error
+

        ;; ---- 5. Copy the file into the free run ----
        jsr dos_openfile
        bcs +
        rts
+
        ldq dfg_cand
        stq dos_current_cluster
        ldz #$00
        jsr dos_cluster_to_sector
        ldq $d681
        stq dfg_dest
        ldz #$00
@copy:
        jsr dos_file_read_current_sector
        bcc @copyfail
        ldq dfg_dest
        stq $d681
        ldz #$00
        jsr sd_writesector
        bcc @copyfail
        ldq dfg_dest
        clc
        adcq Qone
        stq dfg_dest
        ldq dfg_left
        sec
        sbcq Qone
        stq dfg_left
        ldz #$00
        lda dfg_left+0
        ora dfg_left+1
        ora dfg_left+2
        ora dfg_left+3
        beq @copydone
        jsr dos_file_advance_to_next_sector
        bcs @copy
@copyfail:
        ;; Chain shorter than the file length, or a read error.
        ;; Nothing has been changed on the card yet.
        jsr dos_closefile
        +Checkpoint "dos_defrag_current <copy failed>"
        lda #dos_errorcode_read_error
        jmp dos_return_error

@copydone:
        jsr dos_closefile

        ;; ---- 6. Write the new chain into both FATs ----
        ;; dfg_prev = last cluster of the new chain
        ldq dfg_cand
        clc
        adcq dfg_need
        sec
        sbcq Qone
        stq dfg_prev
        ldq dfg_cand
        stq dfg_scan
        ldz #$00
@fatsector:
        ldq dfg_scan
        stq dos_current_cluster
        ldz #$00
        jsr read_fat_sector_for_cluster
@fatentry:
        lda dfg_scan
        jsr dfg_entry_ptr
        ldq dfg_scan
        cpq dfg_prev
        beq @eoc
        clc
        adcq Qone                       ;; entry = next cluster
        bra @put
@eoc:   lda #$ff                        ;; entry = $0FFFFFFF (end of chain)
        tax
        tay
        ldz #$0f
@put:   stq dfg_val
        ldz #$00
        ldy #3
-       lda dfg_val,y
        sta (<dos_scratch_vector),y
        dey
        bpl -

        ldq dfg_scan
        cpq dfg_prev
        beq @fatlast
        clc
        adcq Qone
        stq dfg_scan
        ldz #$00
        lda dfg_scan
        and #$7f
        bne @fatentry
        jsr write_fat_sector_both          ;; FAT sector full, write it out
        bra @fatsector
@fatlast:
        ldz #$00
        jsr write_fat_sector_both

        ;; ---- 7. Point the directory entry at the new chain ----
        jsr dfg_read_dirent
        ldy #fs_fat32_dirent_offset_clusters_low
        lda dfg_cand+0
        sta (<dos_scratch_vector),y
        iny
        lda dfg_cand+1
        sta (<dos_scratch_vector),y
        ldy #fs_fat32_dirent_offset_clusters_high
        lda dfg_cand+2
        sta (<dos_scratch_vector),y
        iny
        lda dfg_cand+3
        sta (<dos_scratch_vector),y
        jsr sd_writesector

        ;; ---- 8. Free the old chain in both FATs ----
        ldq dos_dirent_cluster
        stq dfg_scan
@freeloop:
        ldq dfg_scan
        stq dos_current_cluster
        ldz #$00
        jsr read_fat_sector_for_cluster
        lda dfg_scan
        jsr dfg_entry_ptr
        ldy #3
-       lda (<dos_scratch_vector),y
        sta dfg_val,y
        lda #$00
        sta (<dos_scratch_vector),y
        dey
        bpl -
        lda dfg_val+3
        and #$0f
        sta dfg_val+3
        jsr write_fat_sector_both

        ;; Continue with the next cluster, if it is a valid one.
        ;; End-of-chain markers are >= dfg_limit, and so is anything bogus.
        ldq dfg_val
        stq dfg_scan
        cpq dfg_limit
        bcs @freedone
        lda dfg_val+3
        ora dfg_val+2
        ora dfg_val+1
        bne @freeloop
        lda dfg_val+0
        cmp #2
        bcs @freeloop
@freedone:
        ldz #$00

        ;; The file now starts at the new cluster
        ldq dfg_cand
        stq dos_dirent_cluster
        ldz #$00

        +Checkpoint "dos_defrag_current <done>"
        jmp dos_return_success

;;         ========================

dfg_find_free:
        ;; Find dfg_need free clusters in a row, starting the search at
        ;; cluster 2. C=1 and dfg_cand = first cluster on success.
        lda #$02
        ldx #$00
        ldy #$00
        ldz #$00
        stq dfg_scan
        stq dfg_cand
        lda #$00
        stq dfg_run
        bra @readsector
@loop:
        ldq dfg_scan
        cpq dfg_limit
        bcs @nospace
        ldz #$00
        lda dfg_scan
        and #$7f
        bne @noread
@readsector:
        ldq dfg_scan
        stq dos_current_cluster
        ldz #$00
        jsr read_fat_sector_for_cluster
@noread:
        lda dfg_scan
        jsr dfg_entry_ptr
        ldy #3
        lda (<dos_scratch_vector),y
        and #$0f
        dey
        ora (<dos_scratch_vector),y
        dey
        ora (<dos_scratch_vector),y
        dey
        ora (<dos_scratch_vector),y
        beq @free

        ;; In use: start again after this cluster
        lda #$00
        tax
        tay
        taz
        stq dfg_run
        ldq dfg_scan
        clc
        adcq Qone
        stq dfg_cand
        bra @next
@free:
        ldq dfg_run
        clc
        adcq Qone
        stq dfg_run
        cpq dfg_need
        beq @found
@next:
        ldq dfg_scan
        clc
        adcq Qone
        stq dfg_scan
        ldz #$00
        jmp @loop
@found:
        ldz #$00
        sec
        rts
@nospace:
        ldz #$00
        clc
        rts

;;         ========================

dfg_entry_ptr:
        ;; A = low byte of a cluster number.
        ;; Sets dos_scratch_vector to its FAT entry in the sector buffer.
        pha
        asl
        asl
        sta <dos_scratch_vector
        pla
        and #$40
        beq +
        lda #$01
+       clc
        adc #$de
        sta <(dos_scratch_vector+1)
        rts

;;         ========================

dfg_read_dirent:
        ;; Read the directory sector holding the short entry remembered by
        ;; dos_readdir_storecurrententry, and point dos_scratch_vector at it.
        ldq dos_direntstart_cluster
        stq dos_current_cluster
        ldz #$00
        jsr dos_cluster_to_sector
        lda dos_direntstart_sectorincluster
        jsr sdsector_add_uint8
        jsr sd_readsector
        lda dos_direntstart_offsetinsector+0
        sta <dos_scratch_vector
        lda dos_direntstart_offsetinsector+1
        clc
        adc #$de
        sta <(dos_scratch_vector+1)
        rts

dfg_c511:
        !32 511

;;         ========================

trap_dos_defragfile:
        ;; Defragment the file whose name was set with dos_setname
        ;; (current directory). Does nothing if it is not fragmented.
        +Checkpoint "trap_dos_defragfile"

        jsr dos_findfile
        bcc +
        jsr dos_closefile
        jsr dos_defrag_current
+       jmp return_from_trap_with_carry_flag
