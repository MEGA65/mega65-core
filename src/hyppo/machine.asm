;; /*  -------------------------------------------------------------------
;;     MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
;;     Paul Gardner-Stephen, 2014-2019.
;;     ---------------------------------------------------------------- */

!addr reset_vector = $fffc
!addr irq_vector = $fffe
!addr nmi_vector = $fffa

        ;; UART IO block (contains many other peripherals)
!addr uart65_irq_flag = $d606
!addr ascii_key_in = $d610
!addr buckykey_status = $d611
!addr mouse_detect_ctrl = $d61b

        ;; Hypervisor regisger block $d640-$d67f
!addr hypervisor_a = $d640
!addr hypervisor_x = $d641
!addr hypervisor_y = $d642
!addr hypervisor_z = $d643
!addr hypervisor_b = $d644
!addr hypervisor_spl = $d645
!addr hypervisor_sph = $d646
!addr hypervisor_flags = $d647
!addr hypervisor_pcl = $d648
!addr hypervisor_pch = $d649
!addr hypervisor_maplolo = $d64a
!addr hypervisor_maplohi = $d64b
!addr hypervisor_maphilo = $d64c
!addr hypervisor_maphihi = $d64d
!addr hypervisor_maplomb = $d64e
!addr hypervisor_maphimb = $d64f
!addr hypervisor_cpuport00 = $d650
!addr hypervisor_cpuport01 = $d651
!addr hypervisor_iomode = $d652
!addr hypervisor_dmagic_srcmb = $d653
!addr hypervisor_dmagic_dstmb = $d654
!addr hypervisor_dmagic_list0 = $d655
!addr hypervisor_dmagic_list1 = $d656
!addr hypervisor_dmagic_list2 = $d657
!addr hypervisor_dmagic_list3 = $d658
!addr hypervisor_hardware_virtualisation = $d659

        ;; d65a
        ;; d65b
        ;; d65c

!addr hypervisor_vm_currentpage_lo = $d65d
!addr hypervisor_vm_currentpage_mid = $d65e
!addr hypervisor_vm_currentpage_hi = $d65f

!addr hypervisor_vm_pagetable = $d660
!addr hypervisor_vm_pagetable0_logicalpage_lo = $d660
!addr hypervisor_vm_pagetable0_logicalpage_hi = $d661
!addr hypervisor_vm_pagetable0_physicalpage_lo = $d662
!addr hypervisor_vm_pagetable0_physicalpage_hi = $d663
!addr hypervisor_vm_pagetable1_logicalpage_lo = $d664
!addr hypervisor_vm_pagetable1_logicalpage_hi = $d665
!addr hypervisor_vm_pagetable1_physicalpage_lo = $d666
!addr hypervisor_vm_pagetable1_physicalpage_hi = $d667
!addr hypervisor_vm_pagetable2_logicalpage_lo = $d668
!addr hypervisor_vm_pagetable2_logicalpage_hi = $d669
!addr hypervisor_vm_pagetable2_physicalpage_lo = $d66a
!addr hypervisor_vm_pagetable2_physicalpage_hi = $d66b
!addr hypervisor_vm_pagetable3_logicalpage_lo = $d66c
!addr hypervisor_vm_pagetable3_logicalpage_hi = $d66d
!addr hypervisor_vm_pagetable3_physicalpage_lo = $d66e
!addr hypervisor_vm_pagetable3_physicalpage_hi = $d66f

!addr hypervisor_georam_base_mb = $d670
!addr hypervsior_georam_block_mask = $d671

        ;; d672 110 010
!addr hypervisor_secure_mode_flags = $d672

        ;; d673
        ;; d674
        ;; d675
        ;; d676
        ;; d677
        ;; d678
        ;; d679
        ;; d67a
        ;; d67b

!addr hypervisor_write_char_to_serial_monitor = $d67c

!addr hypervisor_feature_enables = $d67d
!addr hypervisor_hickedup_flag = $d67e
!addr hypervisor_cartridge_flags = $d67e
!addr hypervisor_enterexit_trigger = $d67f

        ;; Where sector buffer maps (over $DE00-$DFFF IO expansion space)
!addr sd_sectorbuffer = $DE00
!addr sd_ctrl = $d680
!addr sd_address_byte0 = $D681
!addr sd_address_byte1 = $D682
!addr sd_address_byte2 = $D683
!addr sd_address_byte3 = $D684
!addr sd_buffer_ctrl = $d689
!addr sd_f011_en = $d68b
!addr sd_fdc_select = $d6a1
!addr fdc_mfm_speed = $d6a2
!addr f011_flag_stomp  = $d6af

!addr fpga_switches_low = $d6dc
!addr fpga_switches_high = $d6dd

        ;; $D6Ex - Ethernet controller
!addr mac_addr_0 = $d6e9
!addr mac_addr_1 = $d6ea
!addr mac_addr_2 = $d6eb
!addr mac_addr_3 = $d6ec
!addr mac_addr_4 = $d6ed
!addr mac_addr_5 = $d6ee

        ;; $D6Fx - mostly audio interfaces
!addr audiomix_addr = $d6f4
!addr audiomix_data = $d6f5
!addr audioamp_ctl = $d6fe

        ;; Hardware 25(d) x 18(e) multiplier
!addr mult48_d0 = $d770
!addr mult48_d1 = $d771
!addr mult48_d2 = $d772
!addr mult48_d3 = $d773
!addr mult48_e0 = $d774
!addr mult48_e1 = $d775
!addr mult48_e2 = $d776
!addr mult48_e3 = $d777
!addr mult48_result0 = $d778
!addr mult48_result1 = $d779
!addr mult48_result2 = $d77a
!addr mult48_result3 = $d77b
!addr mult48_result4 = $d77c
!addr mult48_result5 = $d77d
!addr mult48_result6 = $d77e
!addr mult48_result7 = $d77f

!addr viciv_magic = $d02f
