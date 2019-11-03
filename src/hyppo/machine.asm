/*  -------------------------------------------------------------------
    MEGA65 "HYPPOBOOT" Combined boot and hypervisor ROM.
    Paul Gardner-Stephen, 2014-2019.
    ---------------------------------------------------------------- */

        .label reset_vector = $fffc
        .label irq_vector = $fffe
        .label nmi_vector = $fffa

        // UART IO block (contains many other peripherals)
        .label uart65_irq_flag = $d606
        .label ascii_key_in = $d610
        .label buckykey_status = $d611
        .label mouse_detect_ctrl = $d61b

        // Hypervisor regisger block $d640-$d67f
        .label hypervisor_a = $d640
        .label hypervisor_x = $d641
        .label hypervisor_y = $d642
        .label hypervisor_z = $d643
        .label hypervisor_b = $d644
        .label hypervisor_spl = $d645
        .label hypervisor_sph = $d646
        .label hypervisor_flags = $d647
        .label hypervisor_pcl = $d648
        .label hypervisor_pch = $d649
        .label hypervisor_maplolo = $d64a
        .label hypervisor_maplohi = $d64b
        .label hypervisor_maphilo = $d64c
        .label hypervisor_maphihi = $d64d
        .label hypervisor_maplomb = $d64e
        .label hypervisor_maphimb = $d64f
        .label hypervisor_cpuport00 = $d650
        .label hypervisor_cpuport01 = $d651
        .label hypervisor_iomode = $d652
        .label hypervisor_dmagic_srcmb = $d653
        .label hypervisor_dmagic_dstmb = $d654
        .label hypervisor_dmagic_list0 = $d655
        .label hypervisor_dmagic_list1 = $d656
        .label hypervisor_dmagic_list2 = $d657
        .label hypervisor_dmagic_list3 = $d658
        .label hypervisor_hardware_virtualisation = $d659

        // d65a
        // d65b
        // d65c

        .label hypervisor_vm_currentpage_lo = $d65d
        .label hypervisor_vm_currentpage_mid = $d65e
        .label hypervisor_vm_currentpage_hi = $d65f

        .label hypervisor_vm_pagetable = $d660
        .label hypervisor_vm_pagetable0_logicalpage_lo = $d660
        .label hypervisor_vm_pagetable0_logicalpage_hi = $d661
        .label hypervisor_vm_pagetable0_physicalpage_lo = $d662
        .label hypervisor_vm_pagetable0_physicalpage_hi = $d663
        .label hypervisor_vm_pagetable1_logicalpage_lo = $d664
        .label hypervisor_vm_pagetable1_logicalpage_hi = $d665
        .label hypervisor_vm_pagetable1_physicalpage_lo = $d666
        .label hypervisor_vm_pagetable1_physicalpage_hi = $d667
        .label hypervisor_vm_pagetable2_logicalpage_lo = $d668
        .label hypervisor_vm_pagetable2_logicalpage_hi = $d669
        .label hypervisor_vm_pagetable2_physicalpage_lo = $d66a
        .label hypervisor_vm_pagetable2_physicalpage_hi = $d66b
        .label hypervisor_vm_pagetable3_logicalpage_lo = $d66c
        .label hypervisor_vm_pagetable3_logicalpage_hi = $d66d
        .label hypervisor_vm_pagetable3_physicalpage_lo = $d66e
        .label hypervisor_vm_pagetable3_physicalpage_hi = $d66f

        .label hypervisor_georam_base_mb = $d670
        .label hypervsior_georam_block_mask = $d671

        // d672 110 010
        .label hypervisor_secure_mode_flags = $d672

        // d673
        // d674
        // d675
        // d676
        // d677
        // d678
        // d679
        // d67a
        // d67b

        .label hypervisor_write_char_to_serial_monitor = $d67c

        .label hypervisor_feature_enables = $d67d
        .label hypervisor_hickedup_flag = $d67e
        .label hypervisor_cartridge_flags = $d67e
        .label hypervisor_enterexit_trigger = $d67f

        // Where sector buffer maps (over $DE00-$DFFF IO expansion space)
        .label sd_sectorbuffer = $DE00
        .label sd_ctrl = $d680
        .label sd_address_byte0 = $D681
        .label sd_address_byte1 = $D682
        .label sd_address_byte2 = $D683
        .label sd_address_byte3 = $D684
        .label sd_buffer_ctrl = $d689
        .label sd_f011_en = $d68b
        .label sd_fdc_select = $d6a1
        .label fdc_mfm_speed = $d6a2
        .label f011_flag_stomp  = $d6af

        .label fpga_switches_low = $d6dc
        .label fpga_switches_high = $d6dd

        // $D6Ex - Ethernet controller
        .label mac_addr_0 = $d6e9
        .label mac_addr_1 = $d6ea
        .label mac_addr_2 = $d6eb
        .label mac_addr_3 = $d6ec
        .label mac_addr_4 = $d6ed
        .label mac_addr_5 = $d6ee

        // $D6Fx - mostly audio interfaces
        .label audiomix_addr = $d6f4
        .label audiomix_data = $d6f5
        .label audioamp_ctl = $d6fe

        // Hardware 25(d) x 18(e) multiplier
        .label mult48_d0 = $d770
        .label mult48_d1 = $d771
        .label mult48_d2 = $d772
        .label mult48_d3 = $d773
        .label mult48_e0 = $d774
        .label mult48_e1 = $d775
        .label mult48_e2 = $d776
        .label mult48_e3 = $d777
        .label mult48_result0 = $d778
        .label mult48_result1 = $d779
        .label mult48_result2 = $d77a
        .label mult48_result3 = $d77b
        .label mult48_result4 = $d77c
        .label mult48_result5 = $d77d
        .label mult48_result6 = $d77e
        .label mult48_result7 = $d77f

        .label viciv_magic = $d02f
