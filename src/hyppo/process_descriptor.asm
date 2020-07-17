;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

        ;; Process descriptor block (fixed 256 bytes)
        ;;
        ;; This needs to have information about the current running task,
        ;; and also hold information about the current open files, if any.

        ;; Process description (first 128 bytes)

	start = *
currenttask_block:

        ;; Tasks are idenfied by what amounts to an 8-bit process id.
        ;; Process ID #$FF is special, and indicates that it is the operating system/hypervisor
        ;; that is active.  This affects how results are return from system calls, so that they

currenttask_id:
        !8 $FF

        ;; Name of task (16 characters, unused characters should be null)

currenttask_name:
        !text "OPERATING SYSTEM"

currenttask_d81_image0_flags:
        !8 0
currenttask_d81_image1_flags:
        !8 0

        ;; File names of currently mounted disk images (32 character max length)
currenttask_d81_image0_namelen:
        !8 0
currenttask_d81_image1_namelen:
        !8 0
currenttask_d81_image0_name:
        !text "                                "
currenttask_d81_image1_name:
        !text "                                "

	;; DOS work area is full, so some things over-flow here:
	
	;; Used to temporarily stash the currently read SD card sector.
	;; (mostly to hide when we have to read a FAT sector during file
	;; access)
dos_stashed_sd_sector_number:
	!8 0,0,0,0
	
	
        ;; Make sure we don't over-flow the available space
        * = start + $80

        ;; Now we have file control blocks for the open files/directories.
        ;; We have only 128 bytes for these, so not many files can be open at a time!
        ;; This also means that we don't keep much information about a file in here.
        ;; For example, name, permissions/attributes and so on must be requested seprately
        ;; using trap_dos_fstat.  As a result, we can fit a few more open files in here, to
        ;; make life easy for programmers.  128 bytes / 32 bytes = 4 open files, which seems
        ;; a fairly minimal number.

currenttask_filedescriptor0:
        ;; Which logical drive the file resides on
        ;; (or $FF for a free descriptor block = closed file.
        ;;  we put this in the first byte for convience for checking
        ;;  if a file descriptor is free).
currenttask_filedescriptor0_drivenumber:
        !8 $00

        ;; Starting cluster in file system
        ;; (used so that we can seek around in the file)
currenttask_filedescriptor0_startcluster:
        !8 $00,$00,$00,$00

        ;; Current cluster in file system
currenttask_filedescriptor0_currentcluster:
        !8 $00,$00,$00,$00

        ;; Current sector within current cluster
currenttask_filedescriptor0_sectorincluster:
        !8 $00

        ;; Length of file
currenttask_filedescriptor0_filelength:
        !8 $00,$00,$00,$00

        ;; Position in file indicated by the buffer
currenttask_filedescriptor0_bufferposition:
        !8 $00,$00,$00,$00

        ;; Cluster of the directory in which this file resides
currenttask_filedescriptor0_directorycluster:
        !8 $00,$00,$00,$00

        ;; Which entry this file is within the containing directory
currenttask_filedescriptor0_entryindirectory:
        !16 $0000

        ;; Buffer address in target task used for this file
        ;; (32-bit virtual address, so that the buffer can be paged out)
currenttask_filedescriptor0_bufferaddress:
        !8 $00,$00,$00,$00

        ;; bytes loaded into buffer
currenttask_filedescriptor0_bytesinbuffer:
        !16 $0000

        ;; current offset within buffer
currenttask_filedescriptor0_offsetinbuffer:
        !16 $0000

        ;; The other three file descriptors follow the same format as the first

        * = start + $a0
currenttask_filedescriptor1:

        * = start + $c0
currenttask_filedescriptor2:

        * = start + $e0
currenttask_filedescriptor3:

        * = start + $100

