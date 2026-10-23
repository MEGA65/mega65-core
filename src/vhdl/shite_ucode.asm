; SHITE's microcode (shite_useq.vhdl; docs/shite/MICROCODE.md for the ops).
; tools/shite_uasm.py makes shite_ucode_pkg.vhdl of it.
;
; An instruction starts at 0 with its operands readable by movx (OP, RA,
; RB, RC, RD, RZ, X) and ends with end #error (res first for a result).
; The instructions not here yet are shite.vhdl's state machine's: it
; starts this only for those dispatched below.

.equ ERR_NONE    = 0x00
.equ ERR_OPCODE  = 0x01
.equ ERR_ABORTED = 0x05
.equ ERR_FORMAT  = 0x06
.equ K_FORMULA   = 2
.equ K_FREE      = 15
.equ F_CHANGED   = 0x10         ; (a header's byte 3)
.equ LIST_MAX    = 1024         ; the most cells REBALANCE_ROW sorts in one row
.equ MV_HEAP     = 1            ; why a move failed: the heap too small,
.equ MV_LONGROW  = 2            ; a row's cells past 4096 granules,
.equ MV_FAR      = 3            ; a reference past its form

.const M32    = 0xFFFFFFFF
.const MAGIC  = 0x31544853      ; "SHT1"
.const DEL_S  = 0xA0002000      ; a deleted reference: short form,
.const DEL_L  = 0x080000800000  ; long form

; the instruction, the descriptor
.reg op, desc, rowtab, nrows, ncols, bad
; scratch (any routine may use them)
.reg t0, t1, t2, t3
; a row block (open_block; REBALANCE's tree, rb_block) and a walk over its
; cells (granule g, its header cg, its length len)
.reg row, rlast, blk, rh0, rh1, gfree, g, cg, len
; the byte reader: a formula's bytecode (at cell + 32), its length; the
; byte; where to go past the end, with the stack's depth there
.reg cell, pc, bclen, by, bx_end, bx_sp

; ----------------------------------------------------------------------
start:
        movx    op, OP
        ext     t0, op, 0, 4
        jtab    t0, optab
optab:  jmp     bad_op          ; $40 RECALC
        jmp     rebalance       ; $41 REBALANCE_ROW
        jmp     find_cell       ; $42 FIND_CELL
        jmp     bad_op          ; $43
        jmp     bad_op          ; $44
        jmp     bad_op          ; $45
        jmp     bad_op          ; $46
        jmp     bad_op          ; $47
        jmp     move            ; $48 MOVE_CELLS
        jmp     move            ; $49 CELLS_MOVED
        jmp     bad_op          ; $4A
        jmp     bad_op          ; $4B
        jmp     bad_op          ; $4C
        jmp     bad_op          ; $4D
        jmp     bad_op          ; $4E
        jmp     bad_op          ; $4F

bad_op: end     #ERR_OPCODE
aborted:
        end     #ERR_ABORTED

; ERR_FORMAT: the row (bad) into the descriptor's bytes 48-51
format_fault:
        stl     [desc+48], bad
        end     #ERR_FORMAT

; ----------------------------------------------------------------------
; The descriptor at desc: magic (else ERR_FORMAT), the row table, the
; sheet's size.  Then the abort checked
read_desc:
        ldl     t0, [desc]
        bne     t0, MAGIC, desc_bad
        ldl     rowtab, [desc+4]
        ext     rowtab, rowtab, 0, 28
        ldl     nrows, [desc+8]
        ldl     ncols, [desc+12]
        babt    aborted
        ret
desc_bad:                               ; (not a descriptor: nothing written)
        end     #ERR_FORMAT

; t0 = row t0's entry in the row table (a block, or $FFFFFFFF: none)
row_entry:
        ext     t0, t0, 0, 26
        shl     t0, t0, #2
        add     t0, rowtab, t0
        ldl     t0, [t0]                | ret

; The row block at t0, for row bad: blk, its header (rh0, rh1), its first
; free granule (gfree).  The row number, and gfree within the block (<=
; 4096), checked
open_block:
        ext     blk, t0, 0, 28
        ldq     rh0, [blk]
        ldq     rh1, [blk+8]
        ext     t0, rh0, 0, 32
        bne     t0, bad, format_fault
        ext     gfree, rh1, 16, 16      | z format_fault
        ext     t1, rh0, 32, 16
        bltu    t1, gfree, format_fault
        bgtu    t1, #4096, format_fault
        ret

; The cell at granule g: cg its header, len its length (checked: not 0,
; within gfree)
cell_at:
        shl     t0, g, #4
        add     t0, blk, t0
        ldq     cg, [t0]
        ext     len, cg, 32, 8          | z format_fault
        add     t1, g, len
        bltu    gfree, t1, format_fault
        ret

; ----------------------------------------------------------------------
; FIND_CELL ($42): RA, RB a row and column; the cell's address, 0 if none
.scope
.reg qr, qc, qa, lg, lh
find_cell:
        movx    desc, X
        call    read_desc
        movx    qr, RA
        movx    qc, RB
        call    lookup
        res     qa
        end     #ERR_NONE

; qa = the cell (qr, qc)'s address, 0 if none: the row's block, its root,
; then the tree
lookup:
        li      qa, #0
        bgeu    qr, nrows, lk_ret
        mov     t0, qr
        call    row_entry
        beq     t0, M32, lk_ret
        ext     blk, t0, 0, 28
        ldh     lg, [blk+8]             ; the root (bytes 8-9)
lk_loop:
        bz      lg, lk_ret
        shl     t0, lg, #4
        add     t0, blk, t0
        ext     t0, t0, 0, 28
        ldq     lh, [t0]
        ext     t1, lh, 0, 24           ; its column
        beq     qc, t1, lk_found
        bltu    qc, t1, lk_left
        ext     lg, lh, 52, 12          | abt aborted
        jmp     lk_loop
lk_left:
        ext     lg, lh, 40, 12          | abt aborted
        jmp     lk_loop
lk_found:
        mov     qa, t0
lk_ret: ret
.endscope

; ----------------------------------------------------------------------
; REBALANCE_ROW ($41): rows RA..RB (those with a block)
rebalance:
        movx    desc, X
        call    read_desc
        movx    row, RA
        movx    rlast, RB
b_row:  bgtu    row, rlast, b_done
        bgeu    row, nrows, b_done
        babt    aborted
        mov     t0, row
        call    row_entry
        beq     t0, M32, b_next
        mov     bad, row
        call    open_block
        call    rb_block
b_next: add     row, row, #1            | jmp b_row
b_done: end     #ERR_NONE

; A row block's tree (blk, its header rh0 and rh1, gfree; faults for row
; bad).  Its cells listed (column, granule, header bytes 3-4) in the data
; RAM, sorted by column, then each one's header written with the children
; a balanced tree gives it: the node at the middle of lo..hi has the
; middles of its halves as children, so a node's range is found by
; descending from 0..n-1 as a search would.  Then the block's header: the
; cell count, the root, the stale flag cleared
; (its registers not in a scope: MOVE_CELLS calls it)
.reg ln, i, j, key, lo, hi, md, first, root, gl, gr
rb_block:
        li      g, #1
        li      ln, #0
b_walk: bgeu    g, gfree, b_sort0
        call    cell_at
        ext     t0, cg, 24, 4
        beq     t0, #K_FREE, b_wnext
        beq     ln, #LIST_MAX, format_fault     ; (more cells than the list holds)
        ; column (63:40), granule (39:24), header bytes 3-4 (23:8)
        ext     t2, cg, 24, 16
        shl     t2, t2, #8
        ins     t2, g, t2, 24, 16
        ins     t2, cg, t2, 40, 24
        std     [ln], t2
        add     ln, ln, #1
b_wnext:
        add     g, g, len               | jmp b_walk

        ; insertion sort by column: 0..i-1 sorted
b_sort0:
        li      i, #1
b_sort: bgeu    i, ln, b_tree
        ldd     key, [i]
        ext     t3, key, 40, 24
        mov     j, i
b_sort2:
        bz      j, b_sort4
        ldd     t0, [j-1]
        ext     t1, t0, 40, 24
        beq     t1, t3, format_fault    ; (two cells in one column)
        bltu    t1, t3, b_sort4
        std     [j], t0
        sub     j, j, #1                | jmp b_sort2
b_sort4:
        std     [j], key
        add     i, i, #1                | jmp b_sort

        ; the tree: each node i in turn
b_tree: li      root, #0
        li      i, #0
b_tree1:
        bgeu    i, ln, b_rhdr
        babt    aborted
        li      lo, #0
        sub     hi, ln, #1
        li      first, #1
b_tree2:                                ; one level down towards i
        add     t0, lo, hi
        shr     md, t0, #1
        beq     i, md, b_node
        li      first, #0
        bltu    i, md, b_tleft
        add     lo, md, #1              | jmp b_tree2
b_tleft:
        sub     hi, md, #1              | jmp b_tree2
b_node: ldd     key, [md]
        bz      first, b_node1
        ext     root, key, 24, 16
b_node1:
        li      gl, #0
        li      gr, #0
        bgeu    lo, md, b_node2         ; its left child: the middle of lo..md-1
        add     t0, lo, md
        sub     t0, t0, #1
        shr     t0, t0, #1
        ldd     t1, [t0]
        ext     gl, t1, 24, 16
b_node2:
        bgeu    md, hi, b_node3         ; its right: of md+1..hi
        add     t0, md, hi
        add     t0, t0, #1
        shr     t0, t0, #1
        ldd     t1, [t0]
        ext     gr, t1, 24, 16
b_node3:                                ; the node's header
        ext     t0, key, 40, 24
        ext     t1, key, 8, 16
        ins     t0, t1, t0, 24, 16
        ins     t0, gl, t0, 40, 12
        ins     t0, gr, t0, 52, 12
        ext     t1, key, 24, 16
        shl     t1, t1, #4
        add     t1, blk, t1
        stq     [t1], t0
        add     i, i, #1                | jmp b_tree1

        ; the cell count (bytes 6-7); the root (bytes 8-9), the stale flag
        ; (bit 0 of byte 14) cleared
b_rhdr: ins     t0, ln, rh0, 48, 16
        stq     [blk], t0
        ins     t0, root, rh1, 0, 16
        ins     t0, _, t0, 48, 1
        stq     [blk+8], t0             | ret

; ----------------------------------------------------------------------
; The byte reader: by = bytecode byte pc of the cell, pc + 1.  Past the
; end (pc >= bclen): to bx_end, the calls since bx_sp undone
fetch:  bgeu    pc, bclen, f_end
        add     t0, cell, pc
        ldb     by, [t0+32]
        add     pc, pc, #1              | ret
f_end:  setsp   bx_sp
        jr      bx_end

; ----------------------------------------------------------------------
; MOVE_CELLS ($48), CELLS_MOVED ($49).  X: the parameter block (README
; section 6): the descriptor, the source rectangle S (clipped to the
; sheet), the destination (S's image there: D), the rows to fix, the heap
.scope
.reg xblk, sr1, sc1, sr2, sc2, dr, dc, dr2, dc2, empty, fr1, fr2, he, hp, hb
.reg moved, deleted, changed, mvw, mg, inc, wrow, cc, nc, cphdr, cpsrc, cpdst, cpi, cpn
; a formula's references (fx): the cell's kind and flags, where its formula
; was (po) and is (pn); a reference's bytes (fi) and where (fpos), its
; form, its target (ftr, ftc), the bytes it becomes (fnb, fwn of them)
.reg kf, por, poc, pnr, pnc, fch, fi, fpos, fshort, fra, fca, ftr, ftc, fro, fco
.reg fgone, ffit, fnb, fwn, vl
move:
        movx    xblk, X
        ldq     t0, [xblk]
        ext     desc, t0, 0, 28
        ext     sr1, t0, 32, 32
        ldq     t0, [xblk+8]
        ext     sc1, t0, 0, 32
        ext     sr2, t0, 32, 32
        ldq     t0, [xblk+16]
        ext     sc2, t0, 0, 32
        ext     dr, t0, 32, 20
        ldq     t0, [xblk+24]
        ext     dc, t0, 0, 24
        ext     fr1, t0, 32, 32
        ldq     t0, [xblk+32]
        ext     fr2, t0, 0, 32
        ext     hp, t0, 32, 32          ; (the heap's start)
        ldl     he, [xblk+40]
        stq     [xblk+48], _            ; (why a move failed, and its row: 0 unless it does)
        call    read_desc
        ; S clipped to the sheet; D its image at the destination
        sub     t0, nrows, #1
        and     t0, t0, M32
        bltu    sr2, nrows, mv_s1
        mov     sr2, t0
mv_s1:  sub     t0, ncols, #1
        and     t0, t0, M32
        bltu    sc2, ncols, mv_s2
        mov     sc2, t0
mv_s2:  li      empty, #1
        bgtu    sr1, sr2, mv_s3
        bgtu    sc1, sc2, mv_s3
        li      empty, #0
mv_s3:  add     t0, dr, sr2
        sub     t0, t0, sr1
        and     dr2, t0, M32
        add     t0, dc, sc2
        sub     t0, t0, sc1
        and     dc2, t0, M32
        li      moved, #0
        li      deleted, #0
        li      changed, #0
        ; first the formulas to fix, checked (nothing written)
        li      mvw, #0
        call    mw_pass
        beq     op, #0x49, mv_49
        ; MOVE_CELLS: the rows of S and D built afresh, the row table
        ; pointed at them, then the other formulas rewritten
        call    mb_build
        call    mc_table
        call    mw_pass
        stl     [xblk+36], hp           ; the heap's new start
        stl     [xblk+44], deleted
        res     moved
        end     #ERR_NONE
mv_49:  li      mvw, #1                 ; CELLS_MOVED: checked, now rewritten
        call    mw_pass
        stl     [xblk+44], deleted
        res     changed
        end     #ERR_NONE

; a move that cannot be done (the sheet as it was): why (t1) and where (t2,
; t3: a row and column) into the parameter block
mv_fail:
        ins     t0, t2, t1, 32, 32
        stq     [xblk+48], t0
        stl     [xblk+56], t3
        end     #ERR_FORMAT
mv_heap:
        li      t1, #MV_HEAP
        mov     t2, row
        li      t3, #0                  | jmp mv_fail

; t0 = 1 if (t1, t2) is in S, in D; if row t1 is one MOVE_CELLS builds
; afresh (one of S's, or of D's on the sheet).  t1, t2 kept
in_s:   li      t0, #0
        bnz     empty, in_ret
        bltu    t1, sr1, in_ret
        bgtu    t1, sr2, in_ret
        bltu    t2, sc1, in_ret
        bgtu    t2, sc2, in_ret
        li      t0, #1                  | ret
in_d:   li      t0, #0
        bnz     empty, in_ret
        bltu    t1, dr, in_ret
        bgtu    t1, dr2, in_ret
        bltu    t2, dc, in_ret
        bgtu    t2, dc2, in_ret
        li      t0, #1                  | ret
rebuilt:
        li      t0, #0
        bnz     empty, in_ret
        bltu    t1, sr1, rbt_d
        bgtu    t1, sr2, rbt_d
        li      t0, #1                  | ret
rbt_d:  bltu    t1, dr, in_ret
        bgtu    t1, dr2, in_ret
        bgeu    t1, nrows, in_ret
        li      t0, #1
in_ret: ret

; The formulas of rows fr1..fr2, in place (MOVE_CELLS: but the rows it
; builds afresh), written if mvw.  CELLS_MOVED: a formula in D was moved
; there, from S
mw_pass:
        mov     row, fr1
mw_row: bgtu    row, fr2, mw_done
        bgeu    row, nrows, mw_done
        babt    aborted
        beq     op, #0x49, mw_r1
        mov     t1, row
        call    rebuilt
        bnz     t0, mw_skip
mw_r1:  mov     t0, row
        call    row_entry
        beq     t0, M32, mw_skip
        mov     bad, row
        call    open_block
        li      g, #1
mw_cell:
        bgeu    g, gfree, mw_skip
        call    cell_at
        ext     t0, cg, 24, 4
        bne     t0, #K_FORMULA, mw_cnext
        shl     t0, g, #4
        add     cell, blk, t0
        ext     kf, cg, 24, 8
        ext     pnc, cg, 0, 24
        mov     pnr, row
        mov     por, row
        mov     poc, pnc
        bne     op, #0x49, mw_fx
        mov     t1, row
        mov     t2, pnc
        call    in_d
        bz      t0, mw_fx
        sub     t1, row, dr
        add     t1, t1, sr1
        and     por, t1, M32
        sub     t2, pnc, dc
        add     t2, t2, sc1
        and     poc, t2, M32
mw_fx:  call    fx
mw_cnext:
        add     g, g, len               | jmp mw_cell
mw_skip:
        add     row, row, #1            | jmp mw_row
mw_done:
        ret

; MOVE_CELLS: each row of S or D built afresh in the heap (hp): its own
; cells but those in S or D, then those moving in from S, then its tree
; (rb_block).  Nothing of the sheet changes
mb_build:
        li      mvw, #1
        bnz     empty, mb_ret
        bgeu    dr, nrows, mb_s         ; (D has rows on the sheet?)
        mov     row, dr
        bltu    dr, sr1, mb_a
        mov     row, sr1
mb_a:   sub     t0, nrows, #1
        and     t0, t0, M32
        mov     t1, dr2
        bltu    dr2, nrows, mb_b
        mov     t1, t0
mb_b:   mov     rlast, t1
        bgtu    t1, sr2, mb_row
        mov     rlast, sr2              | jmp mb_row
mb_s:   mov     row, sr1
        mov     rlast, sr2
mb_row: bgtu    row, rlast, mb_ret
        mov     t1, row
        call    rebuilt
        bz      t0, mb_rnext
        babt    aborted
        add     t0, hp, #16
        bgtu    t0, he, mv_heap
        mov     hb, hp
        li      mg, #1
        li      inc, #0
        mov     wrow, row
mb_rd:  mov     t0, wrow                ; row wrow's block
        call    row_entry
        beq     t0, M32, mb_eob
        mov     bad, wrow
        call    open_block
        li      g, #1
mb_cell:
        bgeu    g, gfree, mb_eob
        call    cell_at
        ext     cc, cg, 0, 24
        sub     t0, cc, sc1
        add     t0, t0, dc
        and     nc, t0, M32
        ext     t0, cg, 24, 4
        beq     t0, #K_FREE, mb_next
        bnz     inc, mb_in
        mov     t1, row                 ; staying, unless in S or D
        mov     t2, cc
        call    in_s
        bnz     t0, mb_next
        call    in_d
        bnz     t0, mb_next
        mov     cphdr, cg
        mov     por, row
        mov     poc, cc
        mov     pnr, row
        mov     pnc, cc                 | jmp mb_put
mb_in:  bltu    cc, sc1, mb_next        ; (not in S; or moved off the sheet: dropped)
        bgtu    cc, sc2, mb_next
        bgeu    nc, ncols, mb_next
        ext     t0, cg, 24, 16          ; moving in: its column, CHANGED
        or      t0, t0, #F_CHANGED
        shl     t0, t0, #24
        ins     cphdr, nc, t0, 0, 24
        mov     por, wrow
        mov     poc, cc
        mov     pnr, row
        mov     pnc, nc
        add     moved, moved, #1
mb_put: add     t0, mg, len             ; room for it: then copied, word by word
        bgtu    t0, #4096, mb_long
        shl     t0, t0, #4
        add     t0, hb, t0
        and     t0, t0, M32
        bgtu    t0, he, mv_heap
        shl     t0, g, #4
        add     cpsrc, blk, t0
        shl     t0, mg, #4
        add     cpdst, hb, t0
        ext     cpdst, cpdst, 0, 28
        stq     [cpdst], cphdr
        li      cpi, #1
        shl     cpn, len, #1
mb_cp:  bgeu    cpi, cpn, mb_cpd
        shl     t0, cpi, #3
        add     t1, cpsrc, t0
        ldq     t2, [t1]
        add     t1, cpdst, t0
        stq     [t1], t2
        add     cpi, cpi, #1            | jmp mb_cp
mb_cpd: add     mg, mg, len
        ext     t0, cphdr, 24, 4
        bne     t0, #K_FORMULA, mb_next
        mov     cell, cpdst
        ext     kf, cphdr, 24, 8
        call    fx
mb_next:
        add     g, g, len               | jmp mb_cell
mb_eob: bnz     inc, mb_tree            ; a block walked: the cells moving in next
        bltu    row, dr, mb_tree
        bgtu    row, dr2, mb_tree
        li      inc, #1
        sub     t0, row, dr
        add     t0, t0, sr1
        and     wrow, t0, M32           | jmp mb_rd
mb_tree:                                ; or the header, and the tree
        ext     blk, hb, 0, 28
        shl     rh0, mg, #32
        or      rh0, rh0, row
        shl     rh1, mg, #16
        mov     gfree, mg
        mov     bad, row
        call    rb_block
        add     row, row, #1
        shl     t0, mg, #4
        add     hp, hb, t0
        and     hp, hp, M32             | jmp mb_row
mb_rnext:
        add     row, row, #1            | jmp mb_row
mb_long:
        li      t1, #MV_LONGROW
        mov     t2, row
        li      t3, #0                  | jmp mv_fail
mb_ret: ret

; the row table: each new block, in heap order (no cells: an empty row)
mc_table:
        ldl     t3, [xblk+36]           ; (the heap's start)
mc_loop:
        bgeu    t3, hp, mc_done
        ldq     t1, [t3]
        mov     t2, t3
        ext     t0, t1, 48, 16
        bnz     t0, mc_a
        mov     t2, M32
mc_a:   ext     t0, t1, 0, 26
        shl     t0, t0, #2
        add     t0, rowtab, t0
        stl     [t0], t2
        ext     t0, t1, 32, 16
        shl     t0, t0, #4
        add     t3, t3, t0              | jmp mc_loop
mc_done:
        ret

; ----------------------------------------------------------------------
; A formula's references (the FORMULA cell at cell, kf its byte 3), for
; the move: each read relative to po and written relative to pn, in its own
; form; past the bytecode, or a byte not an opcode: done
fx:     movx    bx_sp, SP
        li      bx_end, #fx_end
        li      fch, #0
        ldh     bclen, [cell+26]
        li      pc, #0
fx_next:
        bgeu    pc, bclen, fx_end
        call    fetch
        bgeu    by, #0x80, fx_sref
        bgeu    by, #0x1E, fx_end
        jtab    by, fx_tab
fx_tab: jmp     fx_end                  ; 00 END
        jmp     fx_s1                   ; 01 I8
        jmp     fx_s4                   ; 02 I32
        jmp     fx_s8                   ; 03 I64
        jmp     fx_s8                   ; 04 F64
        jmp     fx_str                  ; 05 STR: its text skipped
        jmp     fx_s1                   ; 06 FIX
        jmp     fx_lref                 ; 07 REF: the long form
        jmp     fx_next                 ; 08 RECT: two references follow
        jmp     fx_host                 ; 09 HOSTCALL: the text, then the cell
        jmp     fx_s2                   ; 0A JZ
        jmp     fx_s2                   ; 0B JMP
        jmp     fx_call                 ; 0C CALL: two counts
        jmp     fx_cells                ; 0D CELLS: its references follow as items
        jmp     fx_end                  ; 0E
        jmp     fx_end                  ; 0F
        jmp     fx_next                 ; 10-1D: operators
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
        jmp     fx_next
fx_s1:  li      t1, #1                  | jmp fx_skip
fx_s2:  li      t1, #2                  | jmp fx_skip
fx_s4:  li      t1, #4                  | jmp fx_skip
fx_s8:  li      t1, #8
fx_skip:                                ; t1 bytes skipped (past the end: done)
        add     t1, pc, t1
        bgeu    t1, bclen, fx_end
        mov     pc, t1                  | jmp fx_next
fx_str: call    rd_count
        mov     t1, vl                  | jmp fx_skip
fx_call:
        call    rd_count
fx_cells:
        call    rd_count
        jmp     fx_next
fx_host:
        call    rd_count
        add     t1, pc, vl
        add     t2, t1, #6
        bgtu    t2, bclen, fx_end
        mov     pc, t1
fx_lref:
        mov     fpos, pc
        li      fshort, #0
        li      fi, #0
        li      t3, #6
        call    rd_be
        jmp     fx_ref
fx_sref:                                ; a short reference: 4 bytes, the first read
        sub     fpos, pc, #1
        li      fshort, #1
        mov     fi, by
        li      t3, #3
        call    rd_be
fx_ref: bz      fshort, fx_lr           ; its target, absolute (deleted: left)
        beq     fi, DEL_S, fx_next
        ext     fra, fi, 30, 1
        ext     fca, fi, 14, 1
        ext     t2, fi, 15, 15
        bnz     fra, fx_sr1
        exts    t1, fi, 15, 15
        add     t2, por, t1
        and     t2, t2, #0xFFFFF
fx_sr1: mov     ftr, t2
        ext     t2, fi, 0, 14
        bnz     fca, fx_sr2
        exts    t1, fi, 0, 14
        add     t2, poc, t1
        and     t2, t2, #0xFFFFFF
fx_sr2: mov     ftc, t2                 | jmp fx_map
fx_lr:  beq     fi, DEL_L, fx_next
        ext     fra, fi, 47, 1
        ext     fca, fi, 46, 1
        ext     t2, fi, 24, 20
        bnz     fra, fx_lr1
        add     t2, por, t2
        and     t2, t2, #0xFFFFF
fx_lr1: mov     ftr, t2
        ext     t2, fi, 0, 24
        bnz     fca, fx_lr2
        add     t2, poc, t2
        and     t2, t2, #0xFFFFFF
fx_lr2: mov     ftc, t2
fx_map: mov     t1, ftr                 ; to S: follows it; to D but not S: gone
        mov     t2, ftc
        call    in_s
        bz      t0, fx_md
        sub     t1, ftr, sr1
        add     t1, t1, dr
        and     ftr, t1, M32
        sub     t2, ftc, sc1
        add     t2, t2, dc
        and     ftc, t2, M32
        li      fgone, #1
        bgeu    ftr, nrows, fx_enc
        bgeu    ftc, ncols, fx_enc
        li      fgone, #0               | jmp fx_enc
fx_md:  call    in_d
        mov     fgone, t0
fx_enc: sub     t1, ftr, pnr            ; in its form again, relative to pn
        and     fro, t1, #0xFFFFF
        sub     t1, ftc, pnc
        and     fco, t1, #0xFFFFFF
        li      ffit, #1
        bz      fshort, fx_el
        mov     t1, fro                 ; short: 15 bits of row, 14 of column
        bz      fra, fx_es1
        mov     t1, ftr
        bltu    ftr, #32768, fx_es2
        li      ffit, #0                | jmp fx_es2
fx_es1: bltu    fro, #0x4000, fx_es2
        bgeu    fro, #0xFC000, fx_es2
        li      ffit, #0
fx_es2: mov     t2, fco
        bz      fca, fx_es3
        mov     t2, ftc
        bltu    ftc, #16384, fx_es4
        li      ffit, #0                | jmp fx_es4
fx_es3: bltu    fco, #0x2000, fx_es4
        bgeu    fco, #0xFFE000, fx_es4
        li      ffit, #0
fx_es4: ext     t2, t2, 0, 14
        ins     t2, fca, t2, 14, 1
        ins     t2, t1, t2, 15, 15
        ins     t2, fra, t2, 30, 1
        li      t1, #1
        ins     t2, t1, t2, 31, 1
        bne     t2, DEL_S, fx_es5
        li      ffit, #0
fx_es5: bz      fgone, fx_es6
        mov     t2, DEL_S
        li      ffit, #1
fx_es6: mov     fnb, t2
        li      fwn, #4                 | jmp fx_cmp
fx_el:  mov     t1, fro                 ; long: 20 bits of row, 24 of column
        bz      fra, fx_el1
        mov     t1, ftr
fx_el1: mov     t2, fco
        bz      fca, fx_el2
        mov     t2, ftc
fx_el2: ext     t2, t2, 0, 24
        ins     t2, t1, t2, 24, 20
        ins     t2, fca, t2, 46, 1
        ins     t2, fra, t2, 47, 1
        bne     t2, DEL_L, fx_el3
        li      ffit, #0
fx_el3: bz      fgone, fx_el4
        mov     t2, DEL_L
        li      ffit, #1
fx_el4: mov     fnb, t2
        li      fwn, #6
fx_cmp: bnz     ffit, fx_c1
        li      t1, #MV_FAR
        mov     t2, pnr
        mov     t3, pnc                 | jmp mv_fail
fx_c1:  beq     fnb, fi, fx_next
        li      fch, #1
        bz      mvw, fx_next
        bz      fgone, fx_wb
        add     deleted, deleted, #1
fx_wb:  add     t1, cell, fpos          ; its bytes, from the top
        add     t1, t1, #32
        mov     t2, fwn
fx_wb1: sub     t2, t2, #1
        shl     t3, t2, #3
        shr     t3, fnb, t3
        stb     [t1], t3
        add     t1, t1, #1
        bnz     t2, fx_wb1
        jmp     fx_next
fx_end: bz      mvw, fx_ret             ; changed: CHANGED (header byte 3)
        bz      fch, fx_ret
        add     changed, changed, #1
        or      t1, kf, #F_CHANGED
        stb     [cell+3], t1
fx_ret: ret

; t3 bytes onto fi, big-endian
rd_be:  call    fetch
        shl     fi, fi, #8
        or      fi, fi, by
        sub     t3, t3, #1              | nz rd_be
        ret

; a count (one or two bytes) into vl
rd_count:
        call    fetch
        mov     vl, by
        bltu    by, #0x80, rdc_ret
        and     vl, by, #0x7F
        call    fetch
        shl     t1, by, #7
        or      vl, vl, t1
rdc_ret:
        ret
.endscope
