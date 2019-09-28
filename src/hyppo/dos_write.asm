/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.

    Routines for writing to FAT file system.
    ---------------------------------------------------------------- */

dos_find_contiguous_free_space:
        // Find a piece of free space in the specified file system
        // (dos_default_disk), and return the first cluster number
        // if it can be found.
        //
        // INPUT: dos_dirent_length = # of clusters required
        // OUTPUT: dos_opendir_cluster = first cluster
        // C flag set on success, clear on failure.
        //
        // FAT32 file systems have the expected first cluster free
        // stored in the 2nd sector of the file system at offset
        // $1EC (actually, this may point to the last allocated cluster).
        // This field is only a suggestion however, to accelerate allocation,
        // and thus should not be relied upon, but rather to allow quick
        // skipping of the already allocated area of disk.
        //
        // The number of clusters we need to allocate is to be provided in
        // dos_opendir_cluster as a 32-bit value, thus allowing for files
        // upto 2^32 * cluster size bytes long to be created.
        // (Note that in practice files are limited to 2GiB - 1 bytes for
        // total compatibility, and 4GiB -1 for fairly decent compatibility,
        // and 256GiB - 1 if we implement the FAT+ specification
        // (http://www.fdos.org/kernel/fatplus.txt.1) in the appropriate places
        // at some point, which we will likely do, as it is really very simple.
        // Mostly we just have to use 40 bit offsets for file lengths.

        // Let's start with a completely naive algorithm:
        // 1. Begin at cluster 2. Reset # of contiguous clusters found to zero.
        //    Remember this cluster as candidatee starting point.
        // 2. If current cluster not free, advance to next cluster number, reset
        //    contiguous free cluster count.  Remember the newly advanced cluster
        //    number as candidate starting point.
        // 3. If current cluster is free, increase contiguous free clusters found.
        //    If equal to desired number, return candidate cluster number.
        // 4. Repeat 2 and 3 above until end of file system is reached (and return
        //    an error), or until step 3 has returned success.
        //
        // This algorithm can be made more efficient by using the last allocated
        // cluster number field as an alternative starting point, and only if that
        // fails, retrying beginning at cluster 2.

        // So the state we need to keep track of is:
        // dos_opendir_cluster = current cluster we are considering as candidate starting point.
        // dos_file_loadaddress = current cluster being tested for vacancy.
        // dos_dirent_length = number of clusters required, in total.
        // dos_dirent_cluster = number of clusters required, from this point
        // (i.e., the total minus the number we have already found contiguously free).
        // current_disk[fs_fat32_cluster_count] = number of clusters in disk
        // (and thus the end point of our search).
        //
        // Other than that, we just need to advance our way linearly through the FAT sectors.
        // This is straight forward, as we can just read the first FAT sector, and then progress
        // our way through, until we reach the end.

        // First, make sure we can see the sector buffer at $DE00-$DFFF
        jsr sd_map_sectorbuffer

        // 1. Start at cluster 2
        lda #$02
        sta dos_opendir_cluster+0
        sta dos_file_loadaddress+0
        lda #$00
        sta dos_opendir_cluster+1
        sta dos_opendir_cluster+2
        sta dos_opendir_cluster+3
        sta dos_file_loadaddress+1
        sta dos_file_loadaddress+2
        sta dos_file_loadaddress+3

@tryNewStartingPointCandidate:

        // Reset # of clusters still required
        ldx #$03
@ll74:  lda dos_dirent_length, X
        sta dos_dirent_cluster, X
        dex
        bpl @ll74

@testIfClusterEmptyAfterReadingFATSector:
        // Read the appropriate sector of the FAT
        // To do this, we copy the target cluster number to
        // dos_current_cluster, and call dos_cluster_to_fat_sector.
        // This leaves the absolute sector number in
        // dos_current_cluster.
        ldx #$03
@ll78:  lda dos_file_loadaddress, X
        sta dos_current_cluster, X
        dex
        bpl @ll78
        jsr dos_cluster_to_fat_sector
        // Now we have the sector # in dos_current_cluster
        // Copy to the SD card sector register, and do the read
        ldx #$03
@ll83:  lda dos_current_cluster, X
        sta $D681, X
        dex
        bpl @ll83

        // Finally, do the read
        lda #dos_errorcode_read_error
        sta dos_error_code
        jsr sd_readsector
        // XXX - Fail on error
        bcs @ll93
        rts
@ll93:

@testIfClusterEmpty:
        // Here we have the sector read, and do the test on the contents of the cluster
        // entry.

        // But first, check that the cluster number is valid:
        // 1. Get dos_disk_table_offset pointing correctly
        ldx dos_disk_current_disk
        jsr dos_set_current_disk
        ldx dos_disk_table_offset
        // 2. Compare cluster count to current cluster
        ldy #$00
@ll128: lda [dos_disk_table + fs_fat32_cluster_count + 0], X
        cmp dos_file_loadaddress, Y
        bne @notLastClusterOfFileSystem
        inx
        iny
        cpy #$04
        bne @ll128

        // Return error due to lack of space
        lda #dos_errorcode_no_space
        sta dos_error_code
        clc
        rts

@notLastClusterOfFileSystem:

        // The offset in the sector is computed from the bottom
        // 7 bits of the cluster number * 4, to give an offset
        // in the 512 byte sector. Once we have the offset, OR the
        // four bytes of the cluster number together to test if = 0,
        // and thus empty.
        lda dos_file_loadaddress+0
        asl
        asl
        tay
        lda dos_file_loadaddress+0
        and #$40
        beq @lowMoby
        lda $df00, y
        ora $df01, y
        ora $df02, y
        ora $df03, y
        bra @ll120
@lowMoby:
        lda $De00, y
        ora $De01, y
        ora $de02, y
        ora $de03, y
@ll120:
        // Remember result of free-test
        tax

        // Increment next cluster number we will look at
        lda dos_file_loadaddress+0
        clc
        adc #$01
        sta dos_file_loadaddress+0
        lda dos_file_loadaddress+1
        adc #$00
        lda dos_file_loadaddress+1
        lda dos_file_loadaddress+2
        adc #$00
        lda dos_file_loadaddress+2
        lda dos_file_loadaddress+3
        adc #$00
        lda dos_file_loadaddress+3

        // If the cluster was not free, then reset search point
        cpx #$00
        beq @thisClusterWasFree
        ldx #$03
@ll160: lda dos_file_loadaddress, X
        sta dos_opendir_cluster, X
        dex
        bpl @ll160
        jmp @tryNewStartingPointCandidate

@thisClusterWasFree:
        // Decrement # of clusters still required
        lda dos_dirent_cluster+0
        sec
        sbc #$01
        sta dos_dirent_cluster+0
        lda dos_dirent_cluster+1
        sbc #$00
        sta dos_dirent_cluster+1
        lda dos_dirent_cluster+2
        sbc #$00
        sta dos_dirent_cluster+2
        lda dos_dirent_cluster+3
        sbc #$00
        sta dos_dirent_cluster+3
        // Now see if zero
        ora dos_dirent_cluster+2
        ora dos_dirent_cluster+1
        ora dos_dirent_cluster+0
        beq @foundFreeSpace

        // Nope, we still need more, so continue the search

        // Then check if this next cluster is unallocated?
        // (If the cluster entry in the FAT will be in the same
        //  sector as the last, then don't waste time recomputing
        //  and reading the FAT sector number).
        lda dos_file_loadaddress+0
        and #$7F
        bne @sameSector
        jmp @testIfClusterEmptyAfterReadingFATSector
@sameSector:
        jmp @testIfClusterEmpty

@foundFreeSpace:
        // Found the requested space
        sec
        rts
