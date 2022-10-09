;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

         os_version = $0102
         dos_version = $0103
         constant_partition_type_fat32_chs = $0b
         constant_partition_type_fat32_lba = $0c
         constant_partition_type_megea65_sys = $41

        ;; DOS error codes
        ;;
         dos_errorcode_partition_not_interesting = $01
         dos_errorcode_bad_signature = $02
         dos_errorcode_is_small_fat = $03
         dos_errorcode_too_many_reserved_clusters = $04
         dos_errorcode_not_two_fats = $05
         dos_errorcode_too_few_clusters = $06
         dos_errorcode_read_timeout = $07
         dos_errorcode_partition_error = $08
         dos_errorcode_invalid_address = $10
         dos_errorcode_illegal_value = $11
         dos_errorcode_read_error = $20
         dos_errorcode_write_error = $21
         dos_errorcode_no_such_disk = $80
         dos_errorcode_name_too_long = $81
         dos_errorcode_not_implemented = $82
         dos_errorcode_file_too_long = $83
         dos_errorcode_too_many_open_files = $84
         dos_errorcode_invalid_cluster = $85
         dos_errorcode_is_a_directory = $86
         dos_errorcode_not_a_directory = $87
         dos_errorcode_file_not_found = $88
         dos_errorcode_invalid_file_descriptor = $89
         dos_errorcode_image_wrong_length = $8A
         dos_errorcode_image_fragmented = $8B
         dos_errorcode_no_space = $8C
         dos_errorcode_file_exists = $8D
         dos_errorcode_directory_full = $8E
         dos_errorcode_eof = $FF

        ;; FAT directory entry constants
        ;;
        ;; these seem to be offsets into the STANDARD FAT32 header (DO NOT CHANGE)
        ;;
         fs_fat32_dirent_offset_attributes = 11
         fs_fat32_dirent_offset_shortname = 0
         fs_fat32_dirent_offset_create_tenthsofseconds = 13
         fs_fat32_dirent_offset_create_time = 14
         fs_fat32_dirent_offset_create_date = 16
         fs_fat32_dirent_offset_access_date = 18
         fs_fat32_dirent_offset_clusters_high = 20
         fs_fat32_dirent_offset_modify_time = 22
         fs_fat32_dirent_offset_modify_date = 24
         fs_fat32_dirent_offset_clusters_low = 26
         fs_fat32_dirent_offset_file_length = 28

        ;; VFAT long file name entry constants
        ;;
        ;; These are the offsets of the various fields in a directory entry, when
        ;; used to store a long-file-name fragment.
        ;;
         fs_fat32_dirent_offset_lfn_part_number = 0
         fs_fat32_dirent_offset_lfn_type = 12 ;; $0C
         fs_fat32_dirent_offset_lfn_checksum = 13
         fs_fat32_dirent_offset_lfn_part1_chars = 5
         fs_fat32_dirent_offset_lfn_part1_start = 1
         fs_fat32_dirent_offset_lfn_part2_chars = 6
         fs_fat32_dirent_offset_lfn_part2_start = 14
         fs_fat32_dirent_offset_lfn_part3_chars = 2
         fs_fat32_dirent_offset_lfn_part3_start = 28

         fs_fat32_attribute_isreadonly = $01
         fs_fat32_attribute_ishidden = $02
         fs_fat32_attribute_issystem = $04
         fs_fat32_attribute_isvolumelabel = $08
         fs_fat32_attribute_isdirectory = $10
         fs_fat32_attribute_archiveset = $20

        ;; Possible file modes
        ;;
         dos_filemode_directoryaccess = $80
         dos_filemode_end_of_directory = $81
         dos_filemode_readonly = 0
         dos_filemode_readwrite = 1

        ;; 256-byte fixed size records for REL emulaton
        ;;
         dos_filemode_relative = 2

        ;; Each disk entry consists of;
        ;;
        ;; Offset $00 - starting sector (4 bytes)
         fs_start_sector = $00

        ;; Offset $04 - sector count (4 bytes)
         fs_sector_count = $04

        ;; Offset $08 - Filesystem type & media source ($0x = FAT32, $xF = SD card, others reserved for now)
         fs_type_and_source = $08

        ;; Remaining bytes are filesystem dependent:
        ;; For FAT32:
        ;;
        ;; Offset $09 - length of fat (4 bytes) (FAT starts at fs_fat32_system_sectors)
         fs_fat32_length_of_fat = $09

        ;; Offset $0D - system sectors (2 bytes)
         fs_fat32_system_sectors = $0D

        ;; Offset $0F - reserved clusters (1 byte)
         fs_fat32_reserved_clusters = $0F

        ;; Offset $10 - root dir cluster (2 bytes)
         fs_fat32_root_dir_cluster = $10

        ;; Offset $12 - cluster count (4 bytes)
         fs_fat32_cluster_count = $12

        ;; Offset $16 - sectors per cluster
         fs_fat32_sectors_per_cluster = $16

        ;; Offset $17 - copies of FAT
         fs_fat32_fat_copies = $17

        ;; Offset $18 - first sector of cluster zero (4 bytes)
         fs_fat32_cluster0_sector = $18

        ;; Offset $1C - Four spare bytes.

         freeze_prep_none = 0
         freeze_prep_palette0 = 2
         freeze_prep_palette1 = 4
         freeze_prep_palette2 = 6
         freeze_prep_palette3 = 8
         freeze_prep_stash_sd_buffer_and_regs = 10
         freeze_prep_thumbnail = 12
         freeze_prep_viciv = 14
 	 freeze_prep_hyperregs = 16

         d81_image_max_namelen = 32
         d81_image_flag_mounted = 1
         d81_image_flag_write_en = 4

         syspart_error_readerror = $01
         syspart_error_badslotnum = $02
         syspart_error_badmagic = $42
         syspart_error_nosyspart = $ff
