; SHITE's microcode (shite_useq.vhdl; docs/shite/MICROCODE.md for the ops).
; tools/shite_uasm.py makes shite_ucode_pkg.vhdl of it.
;
; An instruction starts at 0 with its operands readable by movx (OP, RA,
; RB, RC, RD, RZ, X) and ends with end #error (res first for a result).
; The instructions not here yet are shite.vhdl's state machine's: it
; starts this only for those dispatched below.

.equ ERR_NONE    = 0x00
.equ ERR_OPCODE  = 0x01
.equ ERR_ADDRESS = 0x02
.equ ERR_ABORTED = 0x05
.equ ERR_FORMAT  = 0x06
.equ K_FORMULA   = 2
.equ K_FREE      = 15
.equ F_CHANGED   = 0x10         ; (a header's byte 3)
.equ LIST_MAX    = 1024         ; the most cells REBALANCE_ROW sorts in one row
.equ MV_HEAP     = 1            ; why a move failed: the heap too small,
.equ MV_LONGROW  = 2            ; a row's cells past 4096 granules,
.equ MV_FAR      = 3            ; a reference past its form
.equ K_EMPTY     = 0
.equ K_TEXT      = 1
.equ K_F64       = 3
.equ K_I32       = 5
.equ K_ERROR     = 6
.equ K_UNCOMPILED = 7

; the codec units (shite.vhdl): job #unit, its inputs (out #P_), its
; results (in #I_)
.equ U_CODEC     = 0            ; COMPILE, DECOMPILE (shite_formula_codec)
.equ U_RENDER    = 1            ; RENDER, FORMAT_CELLS (shite_cell_text)
.equ U_PARSE     = 2            ; PARSE (shite_number_text)
.equ P_CO_SOURCE = 0
.equ P_CO_LEN    = 1
.equ P_CO_CAP    = 2
.equ P_CO_ROW    = 3
.equ P_CO_COL    = 4
.equ P_CO_DEST   = 5
.equ P_CO_DECOMPILE = 6
.equ P_CO_NAMES  = 7
.equ P_CO_DSEP   = 8            ; (the renderer's and PARSE's too)
.equ P_CO_ASEP   = 9
.equ P_CE_KIND   = 10
.equ P_CE_FORMAT = 11
.equ P_CE_WIDTH  = 12
.equ P_CE_UPPER  = 13
.equ P_CE_VALUE  = 14
.equ P_CE_TEXT   = 15
.equ P_CE_TLEN   = 16
.equ P_CE_DEST   = 17
.equ P_CE_SCRATCH = 18
.equ P_CE_CAP    = 19
.equ P_SF_SOURCE = 20
.equ P_SF_LEN    = 21
.equ I_CO_ERROR  = 0
.equ I_CO_RLEN   = 1
.equ I_CO_EPOS   = 2
.equ I_CO_HOSTS  = 3
.equ I_CE_ERROR  = 4
.equ I_CE_COLOUR = 5
.equ I_NU_ERROR  = 6
.equ I_NU_RVALUE = 7
.equ I_NU_RKIND  = 8
.equ I_NU_RSCALE = 9
.equ CODEC_MEMORY = 0x0A
.equ CODEC_ABORTED = 0x0B

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
; a reference's bytes (rd_be), a count (rd_count); RECALC's counters
; loaded (a format fault writes them back first)
.reg fi, vl, cntl

; ----------------------------------------------------------------------
start:
        li      cntl, #0
        movx    op, OP
        ext     t0, op, 0, 4
        jtab    t0, optab
optab:  jmp     recalc          ; $40 RECALC
        jmp     rebalance       ; $41 REBALANCE_ROW
        jmp     find_cell       ; $42 FIND_CELL
        jmp     format_cells    ; $43 FORMAT_CELLS
        jmp     codec           ; $44 COMPILE
        jmp     codec           ; $45 DECOMPILE
        jmp     codec           ; $46 RENDER
        jmp     codec           ; $47 PARSE
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
        bz      cntl, ffa_1             ; (RECALC: its counters back first)
        li      cntl, #0
        call    rc_cw
ffa_1:  stl     [desc+48], bad
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
        ldl     t0, [rowtab+t0*4]       | ret

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
        ldq     cg, [blk+g*16]
        ext     len, cg, 32, 8          | z format_fault
        add     t1, g, len
        bltu    gfree, t1, format_fault
        ret

; ----------------------------------------------------------------------
; FIND_CELL ($42): RA, RB a row and column; the cell's address, 0 if none.
; (lookup's registers not in a scope: FORMAT_CELLS calls it)
.reg qr, qc, qa, lg, lh, lkb
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
        ext     lkb, t0, 0, 28          ; (its own: RECALC's walk keeps blk)
        ldh     lg, [lkb+8]             | z lk_ret      ; the root (bytes 8-9)
lk_loop:
        ldq     lh, [lkb+lg*16]         | abt aborted
        ext     t1, lh, 0, 24           ; its column
        beq     qc, t1, lk_found
        bltu    qc, t1, lk_left
        ext     lg, lh, 52, 12          | nz lk_loop    ; right
        ret
lk_left:
        ext     lg, lh, 40, 12          | nz lk_loop    ; left
        ret
lk_found:
        shl     t0, lg, #4
        add     t0, lkb, t0
        ext     qa, t0, 0, 28
lk_ret: ret

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
.reg ln, i, j, key, lo, hi, md, root, gl, gr
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

        ; the tree: the ranges lo..hi in a queue (lo | hi << 16, in the
        ; data RAM after the list), from 0..n-1; each one's middle a node
b_tree: li      root, #0
        bz      ln, b_rhdr
        sub     hi, ln, #1
        shr     md, hi, #1
        ldd     key, [md]
        ext     root, key, 24, 16       ; (the root: the middle of 0..n-1)
        shl     t0, hi, #16
        li      i, #LIST_MAX            ; (the queue's head,
        li      j, #LIST_MAX            ; and tail)
        std     [j], t0
        add     j, j, #1
b_tree1:
        bgeu    i, j, b_rhdr
        ldd     t0, [i]                 | abt aborted
        add     i, i, #1
        ext     lo, t0, 0, 16
        ext     hi, t0, 16, 16
        add     md, lo, hi
        shr     md, md, #1
        ldd     key, [md]
        li      gl, #0
        li      gr, #0
        bgeu    lo, md, b_node2         ; its left child: the middle of lo..md-1
        sub     t1, md, #1
        ins     t0, t1, lo, 16, 16
        std     [j], t0
        add     j, j, #1
        add     t0, lo, t1
        shr     t0, t0, #1
        ldd     t1, [t0]
        ext     gl, t1, 24, 16
b_node2:
        bgeu    md, hi, b_node3         ; its right: of md+1..hi
        add     t1, md, #1
        ins     t0, hi, t1, 16, 16
        std     [j], t0
        add     j, j, #1
        add     t0, t1, hi
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
        stq     [t1], t0                | jmp b_tree1

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
        ldb     by, [cell+pc+32]
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
.reg kf, por, poc, pnr, pnc, fch, fpos, fshort, fra, fca, ftr, ftc, fro, fco
.reg fgone, ffit, fnb, fwn
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
        add     cpi, cpdst, #8          ; (the copy's pointers)
        add     t3, cpsrc, #8
        shl     cpn, len, #1
        sub     cpn, cpn, #1            | z mb_cpd      ; (8-byte words after the header)
mb_cp:  ldq     t2, [t3]
        stq     [cpi], t2
        add     t3, t3, #8
        add     cpi, cpi, #8
        sub     cpn, cpn, #1            | nz mb_cp
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

; ----------------------------------------------------------------------
; COMPILE ($44), DECOMPILE ($45), RENDER ($46), PARSE ($47) (README
; section 10): the parameter block (32 bytes) and the descriptor's codec
; settings, the job on its unit, its results back.  FORMAT_CELLS ($43):
; RENDER's unit for each field
.scope
.reg xb, xp0, xp8, xp16, xp24, xp32, xp40, k
codec:
        movx    xb, X
        call    x_params
        ldq     t0, [desc+56]           ; names, separators (0: "." and ",")
        ext     t1, t0, 0, 28
        out     #P_CO_NAMES, t1
        call    x_dsep
        ext     t1, t0, 40, 8
        bnz     t1, cx_1
        li      t1, #0x2C
cx_1:   out     #P_CO_ASEP, t1
        beq     op, #0x46, cx_render
        beq     op, #0x47, cx_parse
        ext     t0, xp0, 32, 28         ; COMPILE, DECOMPILE
        out     #P_CO_SOURCE, t0
        ext     t0, xp8, 0, 16
        out     #P_CO_LEN, t0
        ext     t0, xp8, 16, 16
        out     #P_CO_CAP, t0
        ext     t0, xp8, 32, 20
        out     #P_CO_ROW, t0
        ext     t0, xp16, 0, 24
        out     #P_CO_COL, t0
        ext     t0, xp16, 32, 28
        out     #P_CO_DEST, t0
        ext     t0, op, 0, 1
        out     #P_CO_DECOMPILE, t0
        job     #U_CODEC
        in      k, #I_CO_ERROR
        li      t0, #0
        bnz     k, cx_c1
        in      t0, #I_CO_RLEN
cx_c1:  res     t0
        in      t0, #I_CO_RLEN          ; length, error, host calls, position (24-29)
        ins     t0, k, t0, 16, 8
        in      t1, #I_CO_HOSTS
        ins     t0, t1, t0, 24, 8
        in      t1, #I_CO_EPOS
        ins     t0, t1, t0, 32, 16
        stq     [xb+24], t0             | jmp cx_end
cx_render:
        ext     t0, xp0, 32, 4
        out     #P_CE_KIND, t0
        ext     t0, xp16, 0, 16         ; the format (byte 2: the block's fixed point)
        ext     t1, xp0, 40, 8
        ins     t0, t1, t0, 16, 8
        ext     t1, xp16, 24, 40
        ins     t0, t1, t0, 24, 40
        out     #P_CE_FORMAT, t0
        ext     t0, xp0, 48, 8
        out     #P_CE_WIDTH, t0
        out     #P_CE_CAP, t0
        ext     t0, xp0, 63, 1
        out     #P_CE_UPPER, t0
        out     #P_CE_VALUE, xp8
        ext     t0, xp8, 0, 28
        out     #P_CE_TEXT, t0
        ext     t0, xp8, 32, 16
        out     #P_CE_TLEN, t0
        ext     t0, xp24, 0, 28
        out     #P_CE_DEST, t0
        ext     t0, xp24, 32, 28
        out     #P_CE_SCRATCH, t0
        job     #U_RENDER
        in      k, #I_CE_ERROR          ; R[a]: the colour; a renderer error in bits 15-8
        in      t1, #I_CE_COLOUR
        ins     t0, k, t1, 8, 8
        res     t0
        jmp     cx_end
cx_parse:
        ext     t0, xp0, 32, 28         ; PARSE: the literal
        out     #P_SF_SOURCE, t0
        ext     t0, xp8, 0, 16
        out     #P_SF_LEN, t0
        job     #U_PARSE
        in      k, #I_NU_ERROR
        bz      k, cx_p1
        res     _
        stq     [xb+16], _
        stq     [xb+24], _              | jmp cx_end
cx_p1:  in      t1, #I_NU_RKIND         ; the value (16-23), then its kind, fixed point
        li      t0, #4
        bz      t1, cx_p2
        li      t0, #3
cx_p2:  res     t0
        in      t1, #I_NU_RVALUE
        stq     [xb+16], t1
        in      t1, #I_NU_RSCALE
        ins     t0, t1, t0, 8, 8
        stq     [xb+24], t0
cx_end: beq     k, #CODEC_MEMORY, cx_mem        ; a unit's memory fault or abort ends the job
        beq     k, #CODEC_ABORTED, aborted
        end     #ERR_NONE
cx_mem: end     #ERR_ADDRESS

; the parameter block's first 32 bytes (FORMAT_CELLS: 48), its descriptor
x_params:
        ldq     xp0, [xb]
        ext     desc, xp0, 0, 28
        ldq     xp8, [xb+8]
        ldq     xp16, [xb+16]
        ldq     xp24, [xb+24]
        ldq     xp32, [xb+32]
        ldq     xp40, [xb+40]           | ret
; the decimal separator (t0: the descriptor's bytes 56-63; 0: ".")
x_dsep: ext     t1, t0, 32, 8
        bnz     t1, xd_1
        li      t1, #0x2E
xd_1:   out     #P_CO_DSEP, t1          | ret

; FORMAT_CELLS ($43) (section 6): rows r1..r2, columns c1..c2 (widths from
; the list), each field rendered (RENDER's unit), colours, CHANGED
.reg line, cline, col, foff, coff, w, ckind, cval, cfmt, ctlen, ctext, chg, numfmt, hdr
format_cells:
        movx    xb, X
        call    x_params
        ldl     t0, [desc]              ; the descriptor: magic, row table, size
        bne     t0, MAGIC, desc_bad
        ldl     rowtab, [desc+4]
        ext     rowtab, rowtab, 0, 28
        ldl     nrows, [desc+8]
        ldl     ncols, [desc+12]
        ldq     t0, [desc+56]
        call    x_dsep
        ext     row, xp0, 32, 32
        ext     line, xp24, 0, 28
        ext     cline, xp32, 0, 28
        li      ctext, #0
fc_rows:
        ext     t0, xp8, 0, 32
        bgtu    row, t0, fc_done
        bgeu    row, nrows, fc_done
        babt    aborted
        ext     col, xp8, 32, 32
        li      foff, #0
        li      coff, #0
fc_cols:
        ext     t0, xp16, 0, 32         ; the column's width (a byte of the list)
        bleu    col, t0, fc_c1
        add     row, row, #1
        ext     t0, xp24, 32, 16
        add     line, line, t0
        ext     line, line, 0, 28
        ext     t0, xp32, 32, 16
        add     cline, cline, t0
        ext     cline, cline, 0, 28     | jmp fc_rows
fc_c1:  ext     t0, xp16, 32, 28
        ext     t1, xp8, 32, 32
        sub     t1, col, t1
        add     t0, t0, t1
        ldb     w, [t0]
        bz      w, fc_col1              ; (a hidden column)
        mov     qr, row
        mov     qc, col
        call    lookup
        li      ckind, #0               ; the cell (none: blank)
        li      cval, #0
        li      cfmt, #0
        li      ctlen, #0
        li      chg, #0
        li      numfmt, #0
        bgeu    qc, ncols, fc_blank
        bz      qa, fc_blank
        ldq     hdr, [qa]               ; its header: kind, CHANGED
        ext     chg, hdr, 28, 1
        ext     t0, xp24, 56, 1
        bz      t0, fc_h1
        bz      chg, fc_next            ; (only cells with CHANGED)
fc_h1:  ldq     t1, [qa+8]              ; +8: a format, a value, or an error code
        ext     t0, hdr, 24, 4
        beq     t0, #K_EMPTY, fc_empty
        beq     t0, #K_ERROR, fc_err
        bltu    t0, #K_F64, fc_other
        bgtu    t0, #K_I32, fc_other
        mov     ckind, t0               ; a number: its format at +16 if it has one
        mov     cval, t1
        ext     t2, hdr, 30, 1
        bz      t2, fc_render
        ldq     cfmt, [qa+16]
        li      numfmt, #1              | jmp fc_render
fc_empty:
        mov     cfmt, t1                | jmp fc_render
fc_err: li      ckind, #K_ERROR
        mov     cval, t1                | jmp fc_render
fc_other:                               ; TEXT, FORMULA, UNCOMPILED: the format, then +16
        mov     cfmt, t1
        ldq     t1, [qa+16]
        bne     t0, #K_TEXT, fc_o1
        li      ckind, #K_TEXT          ; length (16-17), text at +18
        ext     ctlen, t1, 0, 16
        add     ctext, qa, #18          | jmp fc_render
fc_o1:  bne     t0, #K_UNCOMPILED, fc_o2
        li      ckind, #K_UNCOMPILED    ; length (20-21), text at +24
        ext     ctlen, t1, 32, 16
        add     ctext, qa, #24          | jmp fc_render
fc_o2:  mov     cval, t1                ; FORMULA: the result (16-23), then its kind (24)
        ldq     t1, [qa+24]
        li      numfmt, #1
        ext     t0, t1, 0, 4
        beq     t0, #K_ERROR, fc_o3
        beq     t0, #K_TEXT, fc_o4
        bltu    t0, #K_F64, fc_o5
        bgtu    t0, #K_I32, fc_o5
        mov     ckind, t0               | jmp fc_render
fc_o3:  li      ckind, #K_ERROR
        li      numfmt, #0              | jmp fc_render
fc_o4:  li      ckind, #K_TEXT          ; its text: after the bytecode
        ext     ctlen, cval, 0, 16
        li      numfmt, #0
        ext     t0, t1, 16, 16
        add     ctext, qa, t0
        add     ctext, ctext, #32
        ext     ctext, ctext, 0, 28     | jmp fc_render
fc_o5:  li      ckind, #0
        li      numfmt, #0              | jmp fc_render
fc_blank:
        ext     t0, xp24, 56, 1
        bnz     t0, fc_next
fc_render:                              ; one field (char size 2: into scratch, then expanded)
        out     #P_CE_KIND, ckind
        out     #P_CE_VALUE, cval
        out     #P_CE_FORMAT, cfmt
        out     #P_CE_TLEN, ctlen
        out     #P_CE_TEXT, ctext
        out     #P_CE_WIDTH, w
        out     #P_CE_CAP, w
        ext     t0, xp24, 58, 1
        out     #P_CE_UPPER, t0
        ext     t0, xp40, 0, 28
        out     #P_CE_SCRATCH, t0
        ext     t1, xp24, 48, 2
        bne     t1, #2, fc_r1
        add     t0, t0, #512
        ext     t0, t0, 0, 28           | jmp fc_r2
fc_r1:  add     t0, line, foff
        ext     t0, t0, 0, 28
fc_r2:  out     #P_CE_DEST, t0
        job     #U_RENDER
        in      t0, #I_CE_ERROR
        beq     t0, #CODEC_MEMORY, cx_mem
        beq     t0, #CODEC_ABORTED, aborted
        li      i, #0
        ext     t1, xp24, 48, 2
        bne     t1, #2, fc_colr
fc_exp: bgeu    i, w, fc_exp9           ; 16-bit characters: the code, then 0
        ext     t0, xp40, 0, 28
        add     t0, t0, i
        ldb     t2, [t0+512]
        shl     t1, i, #1
        add     t1, t1, foff
        add     t1, t1, line
        sth     [t1], t2
        add     i, i, #1                | jmp fc_exp
fc_exp9:
        li      i, #0
fc_colr:                                ; the colour plane: one byte a character
        ext     t0, xp32, 0, 28
        bz      t0, fc_clr
        in      t2, #I_CE_COLOUR
        bz      numfmt, fc_cl1
        bz      ckind, fc_cl1
        bnz     cfmt, fc_cl2
fc_cl1: ext     t2, xp32, 48, 8
fc_cl2: bgeu    i, w, fc_clr
        add     t1, cline, coff
        add     t1, t1, i
        stb     [t1], t2
        add     i, i, #1                | jmp fc_cl2
fc_clr: ext     t0, xp24, 57, 1         ; CHANGED cleared (flags bit 1)
        bz      t0, fc_next
        bz      chg, fc_next
        ext     t0, hdr, 24, 8
        and     t0, t0, #0xEF
        stb     [qa+3], t0
fc_next:
        ext     t1, xp24, 48, 2
        add     foff, foff, w
        bne     t1, #2, fc_n1
        add     foff, foff, w
fc_n1:  ext     foff, foff, 0, 16
        add     coff, coff, w
        ext     coff, coff, 0, 16
fc_col1:
        add     col, col, #1            | jmp fc_cols
fc_done:
        end     #ERR_NONE
.endscope

; ======================================================================
; RECALC ($40) (README sections 4-5): rows RA..RB, the formulas of columns
; RC..RD evaluated in memory order, each result stored where it changed
; (CHANGED and ERROR in its header, the row's and the round's changed
; counts, the change list).  RZ bit 0: BEGIN (the round's counters from
; 0); bit 1: END (compared with the previous round's list, the lists
; swapped, the round counted).  R[a]: the cells this call changed
.equ VK_Z = 0                   ; value kinds: blank,
.equ VK_I = 1                   ; I64 (fixed point in its k),
.equ VK_F = 2                   ; F64,
.equ VK_T = 3                   ; text,
.equ VK_E = 4                   ; error,
.equ VK_R = 5                   ; a range,
.equ VK_L = 6                   ; a cell list,
.equ VK_NONE = 7                ; (the range walk: nothing to take)
.equ E_DIV0  = 0x01             ; formula errors
.equ E_VALUE = 0x02
.equ E_REF   = 0x03
.equ E_NUM   = 0x04
.equ E_STACK = 0x07
.equ E_NAME  = 0x08
.equ E_COMPILE = 0x09
.equ K_I64   = 4
.equ F_ERROR = 0x20             ; (a header's byte 3)
.equ FP_ADD = 0
.equ FP_SUB = 1
.equ FP_MUL = 2
.equ FP_DIV = 3
.equ DIVHI  = 32                ; (out #DIVHI: the divider's dividend, high half)
; the data RAM: the evaluation stack below the top (entry i: its value at
; EST + 2i, at EST + 2i + 1 its k (7-0), ref (8), kind (11-9), aux (63-32));
; the range walk's stack (TWS + i: depth 53-48, right 47-36, column 35-12,
; granule 11-0); 10^0..10^19
.equ EST  = 1024
.equ TWS  = 1088
.equ P10T = 1152
.data 1152 = 1
.data 1153 = 10
.data 1154 = 100
.data 1155 = 1000
.data 1156 = 10000
.data 1157 = 100000
.data 1158 = 1000000
.data 1159 = 10000000
.data 1160 = 100000000
.data 1161 = 1000000000
.data 1162 = 10000000000
.data 1163 = 100000000000
.data 1164 = 1000000000000
.data 1165 = 10000000000000
.data 1166 = 100000000000000
.data 1167 = 1000000000000000
.data 1168 = 10000000000000000
.data 1169 = 100000000000000000
.data 1170 = 1000000000000000000
.data 1171 = 10000000000000000000
.const F64_NAN = 0xFFF8000000000000
.const F64_ONE = 0x3FF0000000000000
.const F64_100 = 0x4059000000000000
.const F64_M1  = 0xBFF0000000000000
.const SIGN    = 0x8000000000000000

.scope
; the round: the change list and its capacity, the counters (bytes 32-47),
; this call's changes, the row's; the cell's header
.reg cl, cap, n_chg, n_evals, n_errs, d44, call_chg, row_chg, hdr
; the evaluation: the top (kind, value, k, from a reference, aux), the
; stack's depth, the call depth at the start (for an abort); the
; operator's byte (boop)
.reg tkind, tv, tk, tref, taux, esp, ev_sp
; a cell's value (vl_cell): kind, value, k
.reg vkind, vv, vk
; a binary operator: its operands a, b (as numbers: also F64's), the
; result (kind and value in a's registers), aligned integers xa, xb, the
; result's fixed point xk, which was scaled (scb)
.reg boka, bova, bofa, bokb, bovb, bofb, boop, brk, xa, xb, xk, scb
.alias brkind = boka
.alias brv = bova
; F64: fp_op's operands and result; the normaliser's sign, exponent,
; significand, sticky bit, subnormal; a conversion's integer, its fixed
; point, a partial result
.reg fpa, fpb, fpr, fpop, fns, fne, fnsig, fnst, fnsub, cvv, cvk, cvt
; the multiplier's magnitudes' product, its sign; the divider's
.reg mulo, muhi, muneg, dvneg
; a call: the function, its arguments' count, the first, the count of
; values taken, an error in the fold, pc after the call, the result
.reg agfid, agargc, agi, agcnt, agferr, agpc, acckind, accv, acck, agfromc

recalc:
        movx    desc, X
        call    read_desc
        ldq     t0, [desc+16]           ; the change list, its capacity
        ext     cl, t0, 0, 32
        ext     cap, t0, 32, 32
        ldq     t0, [desc+32]           ; the counters
        ext     n_chg, t0, 0, 32
        ext     n_evals, t0, 32, 32
        ldq     t0, [desc+40]
        ext     n_errs, t0, 0, 32
        ext     d44, t0, 32, 32
        movx    t0, RZ
        ext     t0, t0, 0, 1
        bz      t0, rc_1
        li      n_chg, #0               ; BEGIN
        li      n_evals, #0
        li      n_errs, #0
        and     d44, d44, #-4
rc_1:   li      cntl, #1
        li      call_chg, #0
        movx    row, RA
        movx    rlast, RB
        bz      nrows, rc_end
        bltu    rlast, nrows, rc_row    ; (the rows clipped to the sheet)
        sub     rlast, nrows, #1
rc_row: bgtu    row, rlast, rc_end
        ext     t0, row, 0, 26
        ldl     t0, [rowtab+t0*4]
        beq     t0, M32, rc_rnext
        mov     bad, row
        call    open_block
        li      g, #1
        li      row_chg, #0
rc_walk:                                ; the row's cells in memory order
        babt    aborted
        bgeu    g, gfree, rc_rdone
        call    cell_at
        mov     hdr, cg
        shl     t0, g, #4
        add     cell, blk, t0
        ext     cell, cell, 0, 28
        ext     t0, hdr, 24, 4
        bne     t0, #K_FORMULA, rc_cnext
        ext     t0, hdr, 0, 24
        movx    t1, RC
        bltu    t0, t1, rc_cnext
        movx    t1, RD
        bgtu    t0, t1, rc_cnext
        call    eval
rc_cnext:
        add     g, g, len               | jmp rc_walk
rc_rdone:
        sth     [blk+12], row_chg       ; the row's changed count (bytes 12-13)
rc_rnext:
        add     row, row, #1            | jmp rc_row

; the counters back into the descriptor
rc_cw:  ins     t0, n_evals, n_chg, 32, 32
        stq     [desc+32], t0
        ins     t0, d44, n_errs, 32, 32
        stq     [desc+40], t0           | ret

; END: compare with the previous round's list, swap the lists, the round
; counter, this round's count as the previous one
rc_end: call    rc_cw
        movx    t0, RZ
        ext     t0, t0, 1, 1
        bz      t0, rc_fin
        ldq     t0, [desc+24]           ; the previous list, the round counter
        ext     t2, t0, 0, 32           ; (pcl)
        ext     t3, t0, 32, 32
        add     t3, t3, #1
        ext     t3, t3, 0, 32           ; (the round, counted)
        bz      t2, rc_e9               ; (no previous list: no swap)
        ldl     t1, [desc+52]           ; the previous round's count
        li      vl, #0                  ; (vl: same)
        bne     n_chg, t1, rc_e3
        bgtu    n_chg, cap, rc_e3
        li      vl, #1
        li      agi, #0                 ; (agi: the entry)
rc_e2:  bgeu    agi, n_chg, rc_e3
        shl     t0, agi, #3
        ext     t0, t0, 0, 28
        add     t1, cl, t0
        ldq     tv, [t1]
        add     t1, t2, t0
        ldq     t1, [t1]
        add     agi, agi, #1
        beq     tv, t1, rc_e2
        li      vl, #0
rc_e3:  ins     d44, vl, d44, 1, 1      ; the flags again
        ins     t0, d44, n_errs, 32, 32
        stq     [desc+40], t0
        stl     [desc+16], t2           ; the list address: the previous one's
        ins     t0, t3, cl, 32, 32      ; the round counter, and the previous list
        stq     [desc+24], t0           | jmp rc_e10
rc_e9:  stl     [desc+28], t3
rc_e10: stl     [desc+52], n_chg        ; the previous round's count (52-55)
rc_fin: li      cntl, #0
        res     call_chg
        end     #ERR_NONE

; ----------------------------------------------------------------------
; A formula (the cell at cell, its header hdr, at row): evaluated, the
; result stored.  Past the bytecode, or a stack or opcode fault: #STACK!
eval:   movx    ev_sp, SP
        mov     bx_sp, ev_sp
        li      bx_end, #e_estack
        ldh     bclen, [cell+26]
        li      pc, #0
        li      esp, #0
e_next: bgeu    pc, bclen, e_estack    ; the next opcode (fetch, inlined)
        ldb     by, [cell+pc+32]
        add     pc, pc, #1
        jtab    by, e_tab
e_tab:  jmp     e_end                   ; 00 END
        jmp     e_i8                    ; 01 I8
        jmp     e_i32                   ; 02 I32
        jmp     e_i64                   ; 03 I64
        jmp     e_f64c                  ; 04 F64
        jmp     e_str                   ; 05 STR (text: not yet) #NAME?
        jmp     e_fix                   ; 06 FIX
        jmp     e_lref                  ; 07 REF (the long form)
        jmp     e_rect                  ; 08 RECT
        jmp     e_host                  ; 09 HOSTCALL
        jmp     e_jz                    ; 0A JZ
        jmp     e_jmp                   ; 0B JMP
        jmp     e_call                  ; 0C CALL
        jmp     e_cells                 ; 0D CELLS
        jmp     e_estack                ; 0E
        jmp     e_estack                ; 0F
        jmp     e_bin                   ; 10 ADD
        jmp     e_bin                   ; 11 SUB
        jmp     e_bin                   ; 12 MUL
        jmp     e_bin                   ; 13 DIV
        jmp     e_pow                   ; 14 POW: as POWER(a, b)
        jmp     e_neg                   ; 15 NEG
        jmp     e_pct                   ; 16 PCT
        jmp     e_concat                ; 17 CONCAT (not yet)
        jmp     e_bin                   ; 18 EQ
        jmp     e_bin                   ; 19 NE
        jmp     e_bin                   ; 1A LT
        jmp     e_bin                   ; 1B LE
        jmp     e_bin                   ; 1C GT
        jmp     e_bin                   ; 1D GE
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_estack
        jmp     e_sref                  ; (80-FF: short references)
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref
        jmp     e_sref

; the formula's result an error, at once (t1): the calls since the start
; undone
e_estack:
        li      t1, #E_STACK
e_abort:
        setsp   ev_sp
        li      tkind, #VK_E
        mov     tv, t1
        li      esp, #1                 | jmp e_store

; a new top: the old one into the stack RAM (32 deep: #STACK!).  The caller
; then sets tkind, tv, tk, tref, taux (t0, t1 used)
e_push: beq     esp, #32, e_estack
        bz      esp, ep_1
        sub     t0, esp, #1
        shl     t0, t0, #1
        std     [t0+EST], tv
        ins     t1, tref, tk, 8, 1
        ins     t1, tkind, t1, 9, 3
        ins     t1, taux, t1, 32, 32
        std     [t0+EST+1], t1
ep_1:   add     esp, esp, #1            | ret
; the top into the stack RAM too (as e_push does, the depth kept): a call's
; arguments are then all there
e_spill:
        bz      esp, es_1
        sub     t0, esp, #1
        shl     t0, t0, #1
        std     [t0+EST], tv
        ins     t1, tref, tk, 8, 1
        ins     t1, tkind, t1, 9, 3
        ins     t1, taux, t1, 32, 32
        std     [t0+EST+1], t1
es_1:   ret
; entry t0 of the stack RAM: tv, tk, tref, tkind, taux (the top) (t1 used)
e_entry:
        shl     t0, t0, #1
        ldd     tv, [t0+EST]
        ldd     t1, [t0+EST+1]
        ext     tk, t1, 0, 8
        ext     tref, t1, 8, 1
        ext     tkind, t1, 9, 3
        ext     taux, t1, 32, 32        | ret
; push (kind t2, value t3, k 0, not a reference) then the next item
e_push23:
        call    e_push
        mov     tkind, t2
        mov     tv, t3
        li      tk, #0
        li      tref, #0
        li      taux, #0                | jmp e_next

e_end:  bne     esp, #1, e_estack       ; END: one value left
        jmp     e_store

; t3 bytes (1, 2, 4, 8), little-endian, into fi (t0-t2 used): whole groups
; (past the bytecode's end: byte by byte, to stop where the bytes do)
rd_le:  add     t0, pc, t3
        bgtu    t0, bclen, rl_0
        add     t1, cell, pc
        add     t1, t1, #32             ; (the first byte's address)
        mov     pc, t0
        ldq     fi, [t1]                ; (from it to its group's end)
        ext     t2, t1, 0, 3
        add     t0, t2, t3
        bleu    t0, #8, rl_2
        li      t0, #8                  ; (the rest in the next group)
        sub     t2, t0, t2
        ext     t0, t1, 3, 25
        shl     t0, t0, #3
        ldq     t0, [t0+8]
        shl     t2, t2, #3
        shl     t0, t0, t2
        or      fi, fi, t0
rl_2:   beq     t3, #8, rl_3
        li      t0, #64                 ; (t3 bytes kept)
        shl     t2, t3, #3
        sub     t0, t0, t2
        shl     fi, fi, t0
        shr     fi, fi, t0
rl_3:   ret
rl_0:   li      fi, #0
        li      t2, #0
rl_1:   call    fetch
        shl     t0, by, t2
        or      fi, fi, t0
        add     t2, t2, #8
        sub     t3, t3, #1              | nz rl_1
        ret

e_i8:   li      t3, #1
        call    rd_le
        exts    t3, fi, 0, 8
        li      t2, #VK_I               | jmp e_push23
e_i32:  li      t3, #4
        call    rd_le
        exts    t3, fi, 0, 32
        li      t2, #VK_I               | jmp e_push23
e_i64:  li      t3, #8
        call    rd_le
        mov     t3, fi
        li      t2, #VK_I               | jmp e_push23
e_f64c: li      t3, #8                  ; the F64 constant (subnormals flushed)
        call    rd_le
        mov     t3, fi
        ext     t0, fi, 52, 11
        bnz     t0, ef_1
        and     t3, fi, SIGN
ef_1:   li      t2, #VK_F               | jmp e_push23
e_str:  call    rd_count                ; STR: its text skipped, #NAME?
        add     pc, pc, vl
        ext     pc, pc, 0, 16
        li      t2, #VK_E
        li      t3, #E_NAME             | jmp e_push23
e_fix:  call    fetch                   ; FIX: the top, an integer, is fixed point
        bz      esp, e_estack
        li      tref, #0
        bne     tkind, #VK_I, efx_1
        mov     tk, by                  | jmp e_next
efx_1:  beq     tkind, #VK_E, e_next
        li      tkind, #VK_E
        li      tv, #E_VALUE            | jmp e_next
e_jmp:  li      t3, #2                  ; JMP: forward
        call    rd_le
        add     pc, pc, fi
        ext     pc, pc, 0, 16           | jmp e_next
e_jz:   li      t3, #2                  ; JZ: pop; zero (blank, I64 0, F64 +-0): jump
        call    rd_le
        bz      esp, e_estack
        beq     tkind, #VK_E, ejz_e
        beq     tkind, #VK_Z, ejz_j
        beq     tkind, #VK_I, ejz_i
        bne     tkind, #VK_F, ejz_v
        ext     t0, tv, 52, 11          | z ejz_j
        jmp     ejz_p
ejz_e:  ext     t1, tv, 0, 8            | jmp e_abort
ejz_v:  li      t1, #E_VALUE            | jmp e_abort
ejz_i:  mov     t1, tk
        call    badk
        bnz     t0, ejz_n
        bnz     tv, ejz_p
ejz_j:  add     pc, pc, fi
        ext     pc, pc, 0, 16
ejz_p:  bleu    esp, #1, ejz_1          ; (the pop: the entry below to the top)
        sub     t0, esp, #2
        call    e_entry
ejz_1:  sub     esp, esp, #1            | jmp e_next
ejz_n:  li      t1, #E_NUM              | jmp e_abort
e_concat:                               ; CONCAT (not yet): two operands, #NAME?
        bltu    esp, #2, e_estack
        sub     esp, esp, #1
        li      tkind, #VK_E
        li      tv, #E_NAME
        li      tref, #0                | jmp e_next

; references: the cell, relative to the formula's own (row, column);
; deleted (both relative, both at their minimum): past every sheet
e_sref: mov     fi, by                  ; a short reference: 4 bytes
        li      t3, #3
        call    rd_be
        call    sref_q
        jmp     e_resolve
e_lref: li      fi, #0
        li      t3, #6
        call    rd_be
        call    lref_q
        jmp     e_resolve
e_host: call    rd_count                ; HOSTCALL: the text skipped; the result cell
        add     pc, pc, vl
        ext     pc, pc, 0, 16           | jmp e_lref
sref_q: ext     qr, fi, 15, 15
        ext     t0, fi, 30, 1
        bnz     t0, sq_1
        exts    t1, fi, 15, 15
        add     qr, row, t1
        and     qr, qr, #0xFFFFF
sq_1:   ext     qc, fi, 0, 14
        ext     t0, fi, 14, 1
        bnz     t0, sq_2
        exts    t1, fi, 0, 14
        ext     t2, hdr, 0, 24
        add     qc, t2, t1
        and     qc, qc, #0xFFFFFF
sq_2:   bne     fi, DEL_S, sq_3
        mov     qr, M32
sq_3:   ret
lref_q: ext     qr, fi, 24, 20
        ext     t0, fi, 47, 1
        bnz     t0, lq_1
        add     qr, row, qr
        and     qr, qr, #0xFFFFF
lq_1:   ext     qc, fi, 0, 24
        ext     t0, fi, 46, 1
        bnz     t0, lq_2
        ext     t2, hdr, 0, 24
        add     qc, t2, qc
        and     qc, qc, #0xFFFFFF
lq_2:   bne     fi, DEL_L, lq_3
        mov     qr, M32
lq_3:   ret
; a reference (short, or REF and the long form) into qr, qc
rf_ref: call    fetch
        bgeu    by, #0x80, rf_s
        bne     by, #7, e_estack
        li      fi, #0
        li      t3, #6
        call    rd_be
        jmp     lref_q
rf_s:   mov     fi, by
        li      t3, #3
        call    rd_be
        jmp     sref_q
; (qr, qc): its value pushed (outside the sheet: #REF!)
e_resolve:
        bgeu    qr, nrows, er_ref
        bgeu    qc, ncols, er_ref
        call    lookup
        call    vl_cell
        call    e_push
        mov     tkind, vkind
        mov     tv, vv
        mov     tk, vk
        li      tref, #1
        li      taux, #0                | jmp e_next
er_ref: call    e_push
        li      tkind, #VK_E
        li      tv, #E_REF
        li      tk, #0
        li      tref, #1
        li      taux, #0                | jmp e_next

; the value of the cell at qa (0: none) into vkind, vv, vk (t0-t3 used)
vl_cell:
        li      vk, #0
        bz      qa, vl_z
        ldq     t2, [qa]
        ext     t0, t2, 24, 4
        beq     t0, #K_EMPTY, vl_z
        beq     t0, #K_TEXT, vl_t
        beq     t0, #K_UNCOMPILED, vl_u
        bgeu    t0, #8, vl_z
        bltu    t0, #K_FORMULA, vl_z
        ldq     t3, [qa+8]              ; +8: the value (or the format)
        beq     t0, #K_F64, vl_f
        beq     t0, #K_ERROR, vl_e
        beq     t0, #K_FORMULA, vl_fm
        li      vkind, #VK_I            ; I64, I32: with HAS_FORMAT, its fixed point
        mov     vv, t3
        bne     t0, #K_I32, vl_i1
        exts    vv, t3, 0, 32
vl_i1:  ext     t1, t2, 30, 1
        bz      t1, vl_r
        ldb     vk, [qa+18]
vl_r:   ret
vl_f:   li      vkind, #VK_F
        mov     vv, t3
        ext     t1, t3, 52, 11
        bnz     t1, vl_r
        and     vv, t3, SIGN            | ret
vl_e:   li      vkind, #VK_E
        ext     vv, t3, 0, 8            | ret
vl_fm:  ldb     t1, [qa+24]             ; a formula: its result's kind, the result
        ext     t1, t1, 0, 4
        beq     t1, #K_TEXT, vl_t
        bltu    t1, #K_F64, vl_z
        bgtu    t1, #K_ERROR, vl_z
        ldq     t2, [qa+16]
        beq     t1, #K_ERROR, vl_fe
        beq     t1, #K_F64, vl_ff
        li      vkind, #VK_I
        mov     vv, t2
        ext     vk, t3, 16, 8           | ret
vl_ff:  mov     t3, t2                  | jmp vl_f
vl_fe:  mov     t3, t2                  | jmp vl_e
vl_z:   li      vkind, #VK_Z
        li      vv, #0                  | ret
vl_t:   li      vkind, #VK_T
        li      vv, #0                  | ret
vl_u:   li      vkind, #VK_E
        li      vv, #E_COMPILE          | ret

; ----------------------------------------------------------------------
; RECT, CELLS, CALL, POW
.scope
.reg rc_r1, rc_c1, cl_pc, cl_n
e_rect: call    rf_ref
        mov     rc_r1, qr
        mov     rc_c1, qc
        call    rf_ref                  ; the rectangle, normalised
        bgeu    rc_r1, nrows, er_ref0
        bgeu    qr, nrows, er_ref0
        bgeu    rc_c1, ncols, er_ref0
        bgeu    qc, ncols, er_ref0
        ; (value: r1 63-44, c1 43-20, r2 19-0; aux: c2)
        mov     t2, rc_r1               ; (the smaller row, the larger)
        mov     t3, qr
        bleu    rc_r1, qr, rt_1
        mov     t2, qr
        mov     t3, rc_r1
rt_1:   ext     t3, t3, 0, 20
        ins     t3, t2, t3, 44, 20
        mov     t2, rc_c1
        mov     t1, qc
        bleu    rc_c1, qc, rt_2
        mov     t2, qc
        mov     t1, rc_c1
rt_2:   ins     t3, t2, t3, 20, 24
        ext     t2, t1, 0, 24
        mov     rc_r1, t2               ; (c2 kept over e_push)
        call    e_push
        li      tkind, #VK_R
        mov     tv, t3
        li      tk, #0
        li      tref, #0
        mov     taux, rc_r1             | jmp e_next
er_ref0:
        li      t2, #VK_E
        li      t3, #E_REF              | jmp e_push23
e_cells:                                ; CELLS: the list's references walked past
        call    rd_count
        mov     cl_pc, pc
        mov     cl_n, vl
ec_1:   bz      vl, ec_2
        sub     vl, vl, #1
        call    rf_ref
        jmp     ec_1
ec_2:   ins     t3, cl_n, cl_pc, 16, 16
        li      t2, #VK_L               | jmp e_push23
.endscope
e_call: call    rd_count                ; CALL: the function, its arguments' count
        mov     agfid, vl
        call    rd_count
        mov     agargc, vl
        call    e_spill
        jmp     ag_start
e_pow:  li      agfid, #29              ; POW: as POWER(a, b)
        li      agargc, #2
        call    e_spill
        jmp     ag_start
; NEG; % (integers: two more decimals of fixed point, else F64 / 100)
e_neg:  bz      esp, e_estack
        beq     tkind, #VK_Z, en_z
        beq     tkind, #VK_I, en_i
        beq     tkind, #VK_F, en_f
        beq     tkind, #VK_E, e_next
        li      tkind, #VK_E
        li      tv, #E_VALUE            | jmp e_next
en_z:   li      tkind, #VK_I
        li      tv, #0
        li      tref, #0                | jmp e_next
en_i:   li      tref, #0
        mov     t1, tk
        call    badk
        bnz     t0, en_n
        beq     tv, SIGN, en_n
        sub     tv, _, tv               | jmp e_next
en_n:   li      tkind, #VK_E
        li      tv, #E_NUM              | jmp e_next
en_f:   xor     tv, tv, SIGN
        li      tref, #0                | jmp e_next
e_pct:  bz      esp, e_estack
        li      tref, #0
        beq     tkind, #VK_Z, epc_z
        beq     tkind, #VK_E, e_next
        beq     tkind, #VK_I, epc_i
        beq     tkind, #VK_F, epc_f
        li      tkind, #VK_E
        li      tv, #E_VALUE            | jmp e_next
epc_z:  li      tkind, #VK_I
        li      tv, #0
        li      tk, #2                  | jmp e_next
epc_i:  mov     t1, tk
        call    badk
        bnz     t0, en_n
        ext     t0, tk, 0, 7
        bz      t0, epc_1
        ext     t1, tk, 7, 1
        bnz     t1, epc_cv
epc_1:  bgtu    t0, #16, epc_cv
        add     tk, t0, #2              | jmp e_next
epc_cv: mov     cvv, tv
        mov     cvk, tk
        call    cv
        jmp     epc_d
epc_f:  mov     fpr, tv
epc_d:  mov     fpa, fpr                ; F64: x / 100
        mov     fpb, F64_100
        li      fpop, #FP_DIV
        call    fp
        li      tkind, #VK_F
        mov     tv, fpr
        li      tk, #0
        li      tref, #0                | jmp e_next

; binary operators: a (below the top) op b (the top)
e_bin:  mov     boop, by
        bltu    esp, #2, e_estack
        sub     t0, esp, #2
        shl     t0, t0, #1
        ldd     bova, [t0+EST]
        ldd     t1, [t0+EST+1]
        ext     bofa, t1, 0, 8
        ext     boka, t1, 9, 3
        mov     bokb, tkind
        mov     bovb, tv
        mov     bofb, tk
        sub     esp, esp, #1
        call    bo
        mov     tkind, brkind
        mov     tv, brv
        mov     tk, brk
        li      tref, #0                | jmp e_next

; t0 = 1 if fixed point t1 is past its limits (decimal 18, binary 62)
badk:   ext     t0, t1, 0, 7
        ext     t1, t1, 7, 1
        bnz     t1, bk_b
        bgtu    t0, #18, bk_1
        li      t0, #0                  | ret
bk_b:   bgtu    t0, #62, bk_1
        li      t0, #0                  | ret
bk_1:   li      t0, #1                  | ret
; t0 = 10^t1 (t2 = 0) or 2^t1 (t2 /= 0); 0 past 10^18, 2^63
pw:     bnz     t2, pw_b
        bgtu    t1, #18, pw_0
        ldd     t0, [t1+P10T]           | ret
pw_b:   bgtu    t1, #63, pw_0
        li      t0, #1
        shl     t0, t0, t1              | ret
pw_0:   li      t0, #0                  | ret

; ----------------------------------------------------------------------
; A binary operator: boop on (boka, bova, bofa), (bokb, bovb, bofb); the
; result in brkind, brv (a's registers), brk.  Blank is 0, text #VALUE!,
; a fixed point past its limits #NUM!; integers whose fixed points align
; (the same base, or one plain) exactly, else both as F64
bo:     li      brk, #0
        bne     boka, #VK_Z, bo_1
        li      boka, #VK_I
        li      bova, #0
        li      bofa, #0
bo_1:   bne     bokb, #VK_Z, bo_2
        li      bokb, #VK_I
        li      bovb, #0
        li      bofb, #0
bo_2:   mov     xa, bova
        mov     xb, bovb
        beq     boka, #VK_E, bo_r       ; (a's error: the result)
        beq     boka, #VK_F, bo_3
        bne     boka, #VK_I, bo_val
        mov     t1, bofa
        call    badk
        bnz     t0, bo_num
bo_3:   beq     bokb, #VK_E, bo_eb
        beq     bokb, #VK_F, bo_f64
        bne     bokb, #VK_I, bo_val
        mov     t1, bofb
        call    badk
        bnz     t0, bo_num
        bne     boka, #VK_I, bo_f64
        ; both integers: their fixed points aligned?
        ext     t2, bofa, 0, 7          ; (ka)
        ext     t3, bofb, 0, 7          ; (kb)
        ext     scb, bofb, 7, 1         ; (scb: the base, binary)
        bz      t2, bo_4
        ext     scb, bofa, 7, 1
        bz      t3, bo_4
        xor     t0, bofa, bofb
        ext     t0, t0, 7, 1
        bnz     t0, bo_f64              ; (decimal and binary: F64)
bo_4:   beq     boop, #0x12, bo_mul
        beq     boop, #0x13, bo_div
        ; add, subtract, compare: to the larger fixed point (exactly)
        mov     t0, t2
        bgeu    t2, t3, bo_5
        mov     t0, t3
bo_5:   li      xk, #0
        bz      t0, bo_6
        ins     xk, scb, t0, 7, 1
bo_6:   beq     t2, t3, bo_arith
        bltu    t2, t3, bo_sa
        sub     t1, t2, t3              ; b scaled up
        mov     t2, scb
        call    pw
        mov     t1, t0
        mov     t0, bovb
        call    smul
        call    mu_fit
        bnz     t1, bo_num
        mov     xb, t0                  | jmp bo_arith
bo_sa:  sub     t1, t3, t2              ; a scaled up
        mov     t2, scb
        call    pw
        mov     t1, t0
        mov     t0, bova
        call    smul
        call    mu_fit
        bnz     t1, bo_num
        mov     xa, t0
bo_arith:                               ; xa op xb, aligned
        li      brk, #0
        beq     boop, #0x10, ba_add
        beq     boop, #0x11, ba_sub
        li      boka, #VK_I             ; the comparisons: 1 or 0
        li      brv, #1
        beq     boop, #0x18, ba_eq
        beq     boop, #0x19, ba_ne
        beq     boop, #0x1A, ba_lt
        beq     boop, #0x1B, ba_le
        beq     boop, #0x1C, ba_gt
        blt     xa, xb, ba_0            ; GE
        ret
ba_eq:  beq     xa, xb, bo_r
        jmp     ba_0
ba_ne:  bne     xa, xb, bo_r
        jmp     ba_0
ba_lt:  blt     xa, xb, bo_r
        jmp     ba_0
ba_le:  ble     xa, xb, bo_r
        jmp     ba_0
ba_gt:  bgt     xa, xb, bo_r
ba_0:   li      brv, #0                 | ret
ba_add: add     t0, xa, xb              ; (signed overflow: #NUM!)
        xor     t1, t0, xa
        xor     t2, t0, xb
        and     t1, t1, t2
        bmi     t1, bo_num
        jmp     ba_ok
ba_sub: sub     t0, xa, xb
        xor     t1, xa, xb
        xor     t2, t0, xa
        and     t1, t1, t2
        bmi     t1, bo_num
ba_ok:  li      boka, #VK_I
        mov     brv, t0
        mov     brk, xk                 | ret
bo_mul: add     t0, t2, t3              ; multiply: the fixed points add
        bz      scb, bm_d
        bgtu    t0, #62, bo_f64
        jmp     bm_1
bm_d:   bgtu    t0, #18, bo_f64
bm_1:   li      xk, #0
        bz      t0, bm_2
        ins     xk, scb, t0, 7, 1
bm_2:   mov     t0, bova
        mov     t1, bovb
        call    smul
        call    mu_fit
        bnz     t1, bo_num
        li      boka, #VK_I
        mov     brv, t0
        mov     brk, xk                 | ret
bo_div: bz      bovb, bo_div0           ; divide
        bz      t2, bo_f64              ; the same decimal fixed point:
        bnz     scb, bo_f64             ; (a x 10^k) / b, rounded
        bne     bofa, bofb, bo_f64
        mov     xk, bofa
        mov     t1, t2
        li      t2, #0
        call    pw
        mov     t1, t0
        mov     t0, bova
        call    smul                    ; a x 10^k: 128 bits (muhi:mulo), sign muneg
        mov     t2, bovb
        bge     t2, _, bd_1
        sub     t2, _, t2
        xor     muneg, muneg, #1
bd_1:   mov     dvneg, muneg
        out     #DIVHI, muhi
        div     t0, mulo, t2            ; (rounded half away)
        call    dv_round
        movx    t1, DIVQH
        bnz     t1, bo_num
        call    dv_fit
        bnz     t1, bo_num
        li      boka, #VK_I
        mov     brv, t0
        mov     brk, xk                 | ret
bo_div0:
        li      boka, #VK_E
        li      brv, #E_DIV0            | ret
bo_eb:  li      boka, #VK_E             ; (b's error)
        mov     brv, bovb               | ret
bo_val: li      boka, #VK_E
        li      brv, #E_VALUE           | ret
bo_num: li      boka, #VK_E
        li      brv, #E_NUM
bo_r:   ret

; both operands to F64 (fpa, fpb), then fp_op (or a compare)
bo_f64: beq     boka, #VK_F, bf_1
        mov     cvv, bova
        mov     cvk, bofa
        call    cv
        mov     bova, fpr
bf_1:   beq     bokb, #VK_F, bf_2
        mov     cvv, bovb
        mov     cvk, bofb
        call    cv
        mov     bovb, fpr
bf_2:   li      brk, #0
        mov     fpa, bova
        mov     fpb, bovb
        beq     boop, #0x10, bf_add
        beq     boop, #0x11, bf_sub
        beq     boop, #0x12, bf_mul
        beq     boop, #0x13, bf_div
        ; the comparisons (NaN unordered: all false but NE)
        beq     boop, #0x18, bf_eq
        beq     boop, #0x19, bf_ne
        beq     boop, #0x1A, bf_lt
        beq     boop, #0x1B, bf_le
        mov     fpa, bovb               ; GT, GE: b < a, b <= a
        mov     fpb, bova
        beq     boop, #0x1C, bf_lt
bf_le:  call    f_lt
        bnz     t0, bf_1r
bf_eq:  call    f_eq
        jmp     bf_r
bf_ne:  call    f_eq
        xor     t0, t0, #1              | jmp bf_r
bf_lt:  call    f_lt
        jmp     bf_r
bf_1r:  li      t0, #1
bf_r:   li      boka, #VK_I
        mov     brv, t0                 | ret
bf_add: li      fpop, #FP_ADD           | jmp bf_op
bf_sub: li      fpop, #FP_SUB           | jmp bf_op
bf_mul: li      fpop, #FP_MUL           | jmp bf_op
bf_div: ext     t0, fpb, 52, 11         | z bo_div0
        li      fpop, #FP_DIV
bf_op:  call    fp
        li      boka, #VK_F
        mov     brv, fpr                | ret

; a < b (t0), a = b on F64 bits (fpa, fpb): NaN unordered (both false),
; +0 = -0
f_lt:   li      t0, #0
        call    f_nan2
        bnz     t1, fl_r
        call    f_zero2
        bnz     t1, fl_r
        xor     t1, fpa, fpb
        bmi     t1, fl_s                ; (the signs differ: a negative is less)
        and     t2, fpa, SIGN
        andn    t1, fpa, SIGN
        andn    t3, fpb, SIGN
        bnz     t2, fl_n
        bltu    t1, t3, fl_1
        ret
fl_n:   bltu    t3, t1, fl_1
        ret
fl_s:   bpl     fpa, fl_r
fl_1:   li      t0, #1
fl_r:   ret
f_eq:   li      t0, #0
        call    f_nan2
        bnz     t1, fl_r
        call    f_zero2
        bnz     t1, fl_1
        beq     fpa, fpb, fl_1
        ret
; t1 = 1 if fpa or fpb is a NaN; if both are zeros
f_nan2: mov     t2, fpa
        call    f_nan
        bnz     t1, fn2_r
        mov     t2, fpb
        call    f_nan
fn2_r:  ret
f_zero2:
        li      t1, #0
        ext     t2, fpa, 52, 11
        bnz     t2, fz_r
        ext     t2, fpb, 52, 11
        bnz     t2, fz_r
        li      t1, #1
fz_r:   ret
; t1 = 1 if t2 is a NaN, an infinity (t3 used)
f_nan:  li      t1, #0
        ext     t3, t2, 52, 11
        bne     t3, #2047, fz_r
        ext     t3, t2, 0, 52
        bz      t3, fz_r
        li      t1, #1                  | ret
f_inf:  li      t1, #0
        ext     t3, t2, 52, 11
        bne     t3, #2047, fz_r
        ext     t3, t2, 0, 52
        bnz     t3, fz_r
        li      t1, #1                  | ret

; ----------------------------------------------------------------------
; the multiplier on signed operands: |t0| x |t1| into muhi:mulo, the sign
; muneg
smul:   xor     muneg, t0, t1
        shr     muneg, muneg, #63
        bge     t0, _, sm_1
        sub     t0, _, t0
sm_1:   bge     t1, _, sm_2
        sub     t1, _, t1
sm_2:   mul     mulo, t0, t1
        movx    muhi, MULHI             | ret
; the product signed back (t0), t1 = 1 if it overflowed 64 bits
mu_fit: li      t1, #1
        bnz     muhi, mf_r
        mov     t0, mulo
        bpl     mulo, mf_ok
        bz      muneg, mf_r
        bne     mulo, SIGN, mf_r        ; (-2^63 fits)
mf_ok:  li      t1, #0
        bz      muneg, mf_r
        sub     t0, _, t0
mf_r:   ret
; the quotient's low half (t0, from div) rounded half away from zero, 2r
; >= d (the divisor in t2): t3 = 1 if it carried out of the 64 bits
dv_round:
        li      t3, #0
        movx    t1, DIVR
        bmi     t1, dr_1                ; (r's top bit: 2r past d)
        shl     t1, t1, #1
        bltu    t1, t2, dr_r
dr_1:   add     t0, t0, #1              | nz dr_r
        li      t3, #1
dr_r:   ret
; the quotient signed back (t0; its high half 0), t1 = 1 if it overflowed
; (dvneg: the sign)
dv_fit: li      t1, #1
        bnz     t3, df_r                ; (rounding carried past 64 bits)
        bpl     t0, df_ok
        bz      dvneg, df_r
        bne     t0, SIGN, df_r
df_ok:  li      t1, #0
        bz      dvneg, df_r
        sub     t0, _, t0
df_r:   ret

; ----------------------------------------------------------------------
; F64 (IEEE 754 double, round to nearest even, subnormals flushed to zero
; after rounding): fpop on fpa, fpb (no zero divisor) into fpr
fp:     beq     fpop, #FP_MUL, fp_mul
        beq     fpop, #FP_DIV, fp_div
        mov     fns, fpa                ; add, subtract: the signs (b's flipped by SUB)
        shr     fns, fns, #63
        mov     fnst, fpb
        shr     fnst, fnst, #63
        beq     fpop, #FP_ADD, fa_1
        xor     fnst, fnst, #1
fa_1:   call    f_nan2
        bnz     t1, fp_nan
        mov     t2, fpa
        call    f_inf
        mov     t0, t1
        mov     t2, fpb
        call    f_inf
        bz      t0, fa_2
        bz      t1, fa_ra               ; a infinite: a
        xor     t2, fpa, fpb            ; both: (same signs) = (ADD): a, else NaN
        shr     t2, t2, #63
        xor     t2, t2, fpop
        bnz     t2, fp_nan
fa_ra:  mov     fpr, fpa                | ret
fa_2:   bz      t1, fa_3
        mov     fpr, fpb                ; b infinite: b (SUB: flipped)
        beq     fpop, #FP_ADD, fp_r
        xor     fpr, fpr, SIGN          | ret
fa_3:   ; zeros, then the larger first, the smaller aligned to it
        ext     t0, fpa, 52, 11
        ext     t1, fpb, 52, 11
        bnz     t0, fa_4
        bnz     t1, fa_5
        and     fpr, fns, fnst          ; both zero: -0 only if both are
        shl     fpr, fpr, #63           | ret
fa_4:   bnz     t1, fa_6
        mov     fpr, fpa                | ret       ; b zero: a
fa_5:   andn    fpr, fpb, SIGN          ; a zero: b, with its sign
        ins     fpr, fnst, fpr, 63, 1   | ret
fa_6:   andn    t2, fpa, SIGN
        andn    t3, fpb, SIGN
        bgeu    t2, t3, fa_7
        mov     t2, fpa                 ; (b the larger: swapped)
        mov     fpa, fpb
        mov     fpb, t2
        mov     t2, fns
        mov     fns, fnst
        mov     fnst, t2
        mov     t2, t0
        mov     t0, t1
        mov     t1, t2
fa_7:   mov     fne, t0                 ; (a's exponent)
        sub     t0, t0, t1              ; (the shift)
        ext     xa, fpa, 0, 52          ; (the significands: 1.f at bit 63)
        ins     xa, M32, xa, 52, 1
        shl     xa, xa, #11
        ext     xb, fpb, 0, 52
        ins     xb, M32, xb, 52, 1
        shl     xb, xb, #11
        mov     t2, fnst                ; (b's sign; the sticky bit from here)
        li      fnst, #0
        bz      t0, fa_9
        bgtu    t0, #64, fa_8
        beq     t0, #64, fa_8
        li      t3, #64                 ; (the bits shifted out: sticky)
        sub     t3, t3, t0
        shl     t3, xb, t3
        bz      t3, fa_75
        li      fnst, #1
fa_75:  shr     xb, xb, t0              | jmp fa_9
fa_8:   li      fnst, #1                ; (past 64: all sticky)
        li      xb, #0
fa_9:   bne     fns, t2, fa_dif
        add     fnsig, xa, xb           ; the sum (a carry: one more bit)
        bgeu    fnsig, xa, fn_norm
        ext     t0, fnsig, 0, 1
        or      fnst, fnst, t0
        shr     fnsig, fnsig, #1
        ins     fnsig, M32, fnsig, 63, 1
        add     fne, fne, #1            | jmp fn_norm
fa_dif: ; with one bit more, (xa:0) - (xb:st): the lost bits (sticky) make
        ; the difference odd there, so it is never mistaken for a tie.  Its
        ; top 64 bits are xa - xb - st, its bit 0 st
        sub     fnsig, xa, xb
        sub     fnsig, fnsig, fnst
        bnz     fnsig, fn_norm
        bnz     fnst, fn_norm
        li      fpr, #0                 | ret       ; x - x = +0
fp_mul: call    f_nan2
        bnz     t1, fp_nan
        mov     t2, fpa
        call    f_inf
        mov     t0, t1
        mov     t2, fpb
        call    f_inf
        or      t3, t0, t1              ; (an infinity)
        call    f_zero1                 ; (t1: a zero)
        bz      t3, fm_1
        bnz     t1, fp_nan              ; inf x 0
        jmp     fp_inf
fm_1:   bnz     t1, fp_zero
        ext     t0, fpa, 0, 52          ; the 106-bit product of the significands
        ins     t0, M32, t0, 52, 1
        ext     t1, fpb, 0, 52
        ins     t1, M32, t1, 52, 1
        mul     mulo, t0, t1
        movx    muhi, MULHI
        xor     fns, fpa, fpb
        shr     fns, fns, #63
        ext     t0, fpa, 52, 11
        ext     t1, fpb, 52, 11
        add     fne, t0, t1
        ext     t0, muhi, 41, 1         ; (product bit 105)
        bz      t0, fm_2
        shl     fnsig, muhi, #22
        shr     t0, mulo, #42
        or      fnsig, fnsig, t0
        ext     t0, mulo, 0, 42
        sub     fne, fne, #1022         | jmp fm_3
fm_2:   shl     fnsig, muhi, #23
        shr     t0, mulo, #41
        or      fnsig, fnsig, t0
        ext     t0, mulo, 0, 41
        sub     fne, fne, #1023
fm_3:   li      fnst, #0
        bz      t0, fn_norm
        li      fnst, #1                | jmp fn_norm
fp_div: call    f_nan2
        bnz     t1, fp_nan
        mov     t2, fpa
        call    f_inf
        mov     t0, t1
        mov     t2, fpb
        call    f_inf
        and     t3, t0, t1
        bnz     t3, fp_nan              ; inf / inf
        bnz     t0, fp_inf              ; inf / b
        bnz     t1, fp_zero             ; a / inf
        ext     t0, fpa, 52, 11
        bz      t0, fp_zero             ; 0 / b
        ; the quotient of the significands (ma x 2^63 / mb), its remainder sticky
        ext     t0, fpa, 0, 52
        ins     t0, M32, t0, 52, 1      ; (ma)
        shr     t1, t0, #1
        out     #DIVHI, t1
        shl     t0, t0, #63
        ext     t2, fpb, 0, 52
        ins     t2, M32, t2, 52, 1      ; (mb)
        div     fnsig, t0, t2
        movx    t1, DIVR
        li      fnst, #0
        bz      t1, fdv_1
        li      fnst, #1
fdv_1:  xor     fns, fpa, fpb
        shr     fns, fns, #63
        ext     t0, fpa, 52, 11
        ext     t1, fpb, 52, 11
        sub     fne, t0, t1
        bmi     fnsig, fdv_2
        shl     fnsig, fnsig, #1
        add     fne, fne, #1022         | jmp fn_norm
fdv_2:  add     fne, fne, #1023         | jmp fn_norm
fp_nan: mov     fpr, F64_NAN            | ret
fp_inf: xor     fpr, fpa, fpb           ; (the signs' xor) infinity
        and     fpr, fpr, SIGN
        li      t0, #2047
        ins     fpr, t0, fpr, 52, 11    | ret
fp_zero:
        xor     fpr, fpa, fpb
        and     fpr, fpr, SIGN          | ret
fp_r:   ret
; t1 = 1 if fpa or fpb is zero
f_zero1:
        li      t1, #1
        ext     t2, fpa, 52, 11
        bz      t2, fz1_r
        ext     t2, fpb, 52, 11
        bz      t2, fz1_r
        li      t1, #0
fz1_r:  ret

; normalise (the leading 1 to bit 63), round to nearest even, subnormal
; results rounded as IEEE then flushed: fns, fne (signed), fnsig, fnst into
; fpr.  (value = fnsig / 2^63 x 2^(fne - 1023))
fn_norm:
        bnz     fnsig, fnn_1
        shl     fpr, fns, #63           | ret       ; (a zero: never, but safe)
fnn_1:  clz     t0, fnsig
        shl     fnsig, fnsig, t0
        sub     fne, fne, t0
        li      fnsub, #0
        bge     fne, #1, fn_rnd
        li      fnsub, #1               ; below the normal range: to exponent 1
        li      t0, #1
        sub     t0, t0, fne             ; (the shift)
        bltu    t0, #64, fnn_2
        bz      fnsig, fnn_3            ; (64 or more: all sticky)
        li      fnst, #1
fnn_3:  li      fnsig, #0               | jmp fnn_4
fnn_2:  li      t1, #64
        sub     t1, t1, t0
        shl     t1, fnsig, t1
        bz      t1, fnn_5
        li      fnst, #1
fnn_5:  shr     fnsig, fnsig, t0
fnn_4:  li      fne, #1
fn_rnd: ext     t0, fnsig, 10, 1        ; 53 bits: lsb 11, guard 10, sticky below
        bz      t0, fn_pack
        ext     t0, fnsig, 11, 1
        ext     t1, fnsig, 0, 10
        or      t0, t0, t1
        or      t0, t0, fnst
        bz      t0, fn_pack
        add     t0, fnsig, #2048
        bgeu    t0, fnsig, fnr_1
        mov     fnsig, SIGN             ; (carried out: 1.0 x 2)
        add     fne, fne, #1            | jmp fn_pack
fnr_1:  mov     fnsig, t0
fn_pack:
        bz      fnsub, fnp_1
        bmi     fnsig, fnp_1
        shl     fpr, fns, #63           | ret       ; a subnormal: flushed
fnp_1:  bge     fne, #2047, fnp_inf
        shl     fpr, fns, #63
        ins     fpr, fne, fpr, 52, 11
        shr     t0, fnsig, #11
        ins     fpr, t0, fpr, 0, 52     | ret
fnp_inf:
        shl     fpr, fns, #63
        li      t0, #2047
        ins     fpr, t0, fpr, 52, 11    | ret

; conversions: cvv (an integer, fixed point cvk) to F64 in fpr: F64(v),
; then / F64(10^k) (decimal) or scaled by 2^-k (binary)
cv:     bnz     cvv, cv_1
        li      fpr, #0                 | ret
cv_1:   shr     fns, cvv, #63
        mov     fnsig, cvv
        bz      fns, cv_2
        sub     fnsig, _, cvv
cv_2:   li      fne, #1086              ; (1023 + 63)
        li      fnst, #0
        call    fn_norm
        ext     t0, cvk, 0, 7
        bz      t0, cv_r
        ext     t1, cvk, 7, 1
        bz      t1, cv_dec
        shr     fns, fpr, #63           ; binary: the exponent, rounded again
        ext     fnsig, fpr, 0, 52
        ins     fnsig, M32, fnsig, 52, 1
        shl     fnsig, fnsig, #11
        ext     fne, fpr, 52, 11
        sub     fne, fne, t0
        li      fnst, #0
        jmp     fn_norm
cv_dec: mov     cvt, fpr                ; decimal: / F64(10^k)
        li      fns, #0
        ldd     fnsig, [t0+P10T]
        li      fne, #1086
        li      fnst, #0
        call    fn_norm
        mov     fpa, cvt
        mov     fpb, fpr
        li      fpop, #FP_DIV
        jmp     fp
cv_r:   ret

; ----------------------------------------------------------------------
; The result (the top) as stored: (nrk, nv); an integer rescaled to the
; cell's own fixed point fk (the format's byte 2) (section 4)
.alias nrk = vkind
.alias nv = vv
.alias fk = vk
e_store:
        add     n_evals, n_evals, #1
        ext     n_evals, n_evals, 0, 32
        ldb     fk, [cell+10]
        beq     tkind, #VK_Z, st_z
        beq     tkind, #VK_I, st_i
        beq     tkind, #VK_F, st_f
        beq     tkind, #VK_E, st_e
        li      nrk, #6
        li      nv, #E_VALUE            | jmp st_w1
st_z:   li      tv, #0                  ; (blank: as I64 0, the cell's fixed point checked)
        li      tk, #0                  | jmp st_i
st_f:   ext     t0, tv, 52, 11
        beq     t0, #2047, st_num
        li      nrk, #3
        mov     nv, tv                  | jmp st_w1
st_e:   li      nrk, #6
        ext     nv, tv, 0, 8            | jmp st_w1
st_num: li      nrk, #6
        li      nv, #E_NUM              | jmp st_w1
st_i:   li      nrk, #4
        mov     nv, tv
        mov     t1, tk
        call    badk
        bnz     t0, st_num
        mov     t1, fk
        call    badk
        bnz     t0, st_num
        ext     t2, tk, 0, 7
        ext     t3, fk, 0, 7
        bz      t2, st_i0
        bz      t3, st_cv               ; (no matching fixed point in the cell: F64)
        xor     t0, tk, fk
        ext     t0, t0, 7, 1
        bnz     t0, st_cv
        bgeu    t3, t2, st_up
        sub     t1, t2, t3              ; down, rounded
        ext     t2, fk, 7, 1
        call    pw
        mov     t2, t0
        mov     t0, tv
        li      dvneg, #0
        bge     t0, _, sd_1
        sub     t0, _, t0
        li      dvneg, #1
sd_1:   out     #DIVHI, _
        div     t0, t0, t2
        call    dv_round
        bz      dvneg, sd_2
        sub     t0, _, t0
sd_2:   mov     nv, t0                  | jmp st_w1
st_i0:  bz      t3, st_w1               ; (both plain: as it is)
        mov     t1, t3                  | jmp st_up1
st_up:  sub     t1, t3, t2              ; up, exactly
st_up1: ext     t2, fk, 7, 1
        call    pw
        mov     t1, t0
        mov     t0, tv
        call    smul
        call    mu_fit
        bnz     t1, st_num
        mov     nv, t0                  | jmp st_w1
st_cv:  mov     cvv, tv
        mov     cvk, tk
        call    cv
        li      nrk, #3
        mov     nv, fpr
st_w1:  bne     nrk, #6, sw_1
        add     n_errs, n_errs, #1
        ext     n_errs, n_errs, 0, 32
sw_1:   ldq     t0, [cell+16]           ; as stored: unchanged?
        ldb     t1, [cell+24]
        bne     nv, t0, sw_2
        beq     nrk, t1, sw_r
sw_2:   stq     [cell+16], nv
        stb     [cell+24], nrk
        ext     t0, hdr, 24, 8          ; the header's flags: CHANGED, ERROR
        and     t0, t0, #0xCF
        or      t0, t0, #F_CHANGED
        bne     nrk, #6, sw_3
        or      t0, t0, #F_ERROR
sw_3:   stb     [cell+3], t0
        add     row_chg, row_chg, #1
        add     call_chg, call_chg, #1
        ext     call_chg, call_chg, 0, 32
        bgeu    n_chg, cap, sw_ovf      ; the change list
        shl     t0, n_chg, #3
        ext     t0, t0, 0, 28
        add     t0, cl, t0
        ext     t1, hdr, 0, 24
        shl     t1, t1, #32
        or      t1, t1, row
        stq     [t0], t1                | jmp sw_n
sw_ovf: or      d44, d44, #1
sw_n:   add     n_chg, n_chg, #1
        ext     n_chg, n_chg, 0, 32
sw_r:   ret

; ----------------------------------------------------------------------
; Aggregates (section 4) and the scalar functions (5.7): CALL's arguments,
; the top of them at esp - 1, all in the stack RAM.  An error among them
; ends the formula; a fold's error is kept as the result
ag_start:
        bgtu    agargc, esp, e_estack
        sub     agi, esp, agargc
        li      agcnt, #0
        li      agferr, #0
        li      acckind, #VK_I
        li      accv, #0
        li      acck, #0
        mov     agpc, pc
        bne     agfid, #6, ags_1
        li      accv, #1                ; PRODUCT: from 1
ags_1:  bleu    agfid, #6, ag_agg
        beq     agfid, #14, ag_agg
        beq     agfid, #15, ag_agg
        beq     agfid, #16, sf_start
        beq     agfid, #29, sf_start
        bltu    agfid, #7, ag_name
        bleu    agfid, #13, sf_start
ag_name:
        li      acckind, #VK_E
        li      accv, #E_NAME           | jmp ag_result

; the result in place of the arguments
ag_result:
        mov     pc, agpc
        bnz     agargc, agr_1
        call    e_push
        jmp     agr_2
agr_1:  sub     esp, esp, agargc
        add     esp, esp, #1
agr_2:  mov     tkind, acckind
        mov     tv, accv
        mov     tk, acck
        li      tref, #0
        li      taux, #0                | jmp e_next

.scope
; a range walk: rows agrow..agrlast, columns agc1..agc2, an in-order walk
; of each row's tree (its stack in the data RAM, at most 32 deep); AND, OR;
; MIN, MAX's best so far
.reg agrow, agrlast, agc1, agc2, agblk, agln, twsp, twcur, twd, twnxt, twnd
.reg agall, agany, agbad, bestkind, bestv, bestk
ag_agg: li      agall, #1
        li      agany, #0
        li      agbad, #0
ag_arg: beq     agi, esp, ag_fin
        shl     t0, agi, #1             ; argument agi
        ldd     vv, [t0+EST]
        ldd     t1, [t0+EST+1]
        ext     vkind, t1, 9, 3
        ext     vk, t1, 0, 8
        ext     agfromc, t1, 8, 1
        ext     t2, t1, 32, 24          ; (a range's last column)
        beq     vkind, #VK_R, ag_rng
        beq     vkind, #VK_L, ag_lst
        call    ag_take
ag_nxt: add     agi, agi, #1            | jmp ag_arg

ag_rng: ext     agrow, vv, 44, 20
        ext     agrlast, vv, 0, 20
        mov     agc2, t2
        ext     agc1, vv, 20, 24
        ext     t1, nrows, 20, 12
        bnz     t1, agr_r
        ext     t1, nrows, 0, 20
        bltu    agrlast, t1, agr_r
        sub     agrlast, nrows, #1
        and     agrlast, agrlast, M32
agr_r:  bgtu    agrow, agrlast, ag_nxt
        mov     t0, agrow
        call    row_entry
        beq     t0, M32, agr_n
        ext     agblk, t0, 0, 28
        ldh     twcur, [agblk+8]        ; the root: the walk starts
        ext     twcur, twcur, 0, 12
        li      twd, #1
        li      twsp, #0
ag_tw:  bz      twcur, agt_pop
        bgtu    twd, #32, agt_deep
        ldq     t1, [agblk+twcur*16]    ; a node: kept, then its left (if needed)
        ext     t0, t1, 52, 12
        ins     t2, t0, twcur, 36, 12
        ext     t0, t1, 0, 24
        ins     t2, t0, t2, 12, 24
        ins     t2, twd, t2, 48, 6
        std     [twsp+TWS], t2
        add     twsp, twsp, #1
        ext     t0, t1, 0, 24
        bleu    t0, agc1, agt_nl
        ext     twcur, t1, 40, 12
        add     twd, twd, #1            | jmp ag_tw
agt_nl: li      twcur, #0               | jmp ag_tw
agt_pop:
        bz      twsp, agr_n             ; (the row's walk is over)
        sub     twsp, twsp, #1          ; the next node in order: visit it (in
        ldd     t1, [twsp+TWS]          ; the columns), then its right
        ext     t2, t1, 12, 24
        li      twnxt, #0
        li      twnd, #0
        bgeu    t2, agc2, agt_p1
        ext     twnxt, t1, 36, 12
        ext     twnd, t1, 48, 6
        add     twnd, twnd, #1
agt_p1: bltu    t2, agc1, agt_v
        bgtu    t2, agc2, agt_v
        ext     t0, t1, 0, 12
        shl     t0, t0, #4
        add     qa, agblk, t0
        ext     qa, qa, 0, 28
        call    vl_cell
        li      agfromc, #1
        call    ag_take
agt_v:  mov     twcur, twnxt
        mov     twd, twnd               | jmp ag_tw
agt_deep:
        mov     bad, agrow              | jmp format_fault    ; (a tree deeper than 32)
agr_n:  add     agrow, agrow, #1        | jmp agr_r

ag_lst: ext     pc, vv, 0, 16           ; a cell list: agln references from pc
        ext     agln, vv, 16, 16
agl_1:  bz      agln, agl_9
        sub     agln, agln, #1
        call    rf_ref
        bgeu    qr, nrows, agl_ref
        bgeu    qc, ncols, agl_ref
        call    lookup
        call    vl_cell
        li      agfromc, #1
        call    ag_take
        jmp     agl_1
agl_ref:
        li      t1, #E_REF              | jmp e_abort
agl_9:  mov     pc, agpc                | jmp ag_nxt

; one value (vkind, vv, vk; agfromc: from cells, whose text and blanks are
; skipped) into the aggregate
ag_take:
        bne     agfid, #5, agt_1        ; COUNTA: everything but blanks
        beq     vkind, #VK_Z, agt_r
        add     agcnt, agcnt, #1
        ext     agcnt, agcnt, 0, 32     | ret
agt_1:  beq     vkind, #VK_E, agt_err
        beq     vkind, #VK_I, agt_num
        beq     vkind, #VK_F, agt_num
        bz      agfromc, agt_val
        beq     vkind, #VK_T, agt_r
        beq     vkind, #VK_Z, agt_r
agt_val:
        li      t1, #E_VALUE            | jmp e_abort
agt_err:
        ext     t1, vv, 0, 8            | jmp e_abort
agt_num:
        add     agcnt, agcnt, #1
        ext     agcnt, agcnt, 0, 32
        bleu    agfid, #1, agt_sum      ; SUM, AVERAGE (+), PRODUCT (*)
        beq     agfid, #6, agt_sum
        beq     agfid, #14, agt_ao
        beq     agfid, #15, agt_ao
        beq     agfid, #2, agt_mm
        beq     agfid, #3, agt_mm
agt_r:  ret
agt_sum:
        bnz     agferr, agt_r
        mov     boka, acckind
        mov     bova, accv
        mov     bofa, acck
        mov     bokb, vkind
        mov     bovb, vv
        mov     bofb, vk
        li      boop, #0x10
        bne     agfid, #6, ats_1
        li      boop, #0x12
ats_1:  call    bo
        mov     acckind, brkind
        mov     accv, brv
        mov     acck, brk
        bne     acckind, #VK_E, agt_r
        li      agferr, #1              | ret
agt_ao: bne     vkind, #VK_I, ata_1     ; AND, OR
        mov     t1, vk
        call    badk
        bz      t0, ata_1
        li      agbad, #1
ata_1:  beq     vkind, #VK_I, ata_i
        ext     t0, vv, 52, 11          | z ata_0       ; (F64 +-0)
        jmp     ata_nz
ata_i:  bz      vv, ata_0
ata_nz: li      agany, #1               | ret
ata_0:  li      agall, #0               | ret
agt_mm: bne     agcnt, #1, atm_1        ; MIN, MAX: the first is the best so far
        mov     bestkind, vkind
        mov     bestv, vv
        mov     bestk, vk               | ret
atm_1:  bnz     agferr, agt_r
        mov     boka, vkind
        mov     bova, vv
        mov     bofa, vk
        mov     bokb, bestkind
        mov     bovb, bestv
        mov     bofb, bestk
        li      boop, #0x1A
        beq     agfid, #2, atm_2
        li      boop, #0x1C
atm_2:  call    bo
        bne     brkind, #VK_E, atm_3
        li      agferr, #1
        mov     bestkind, brkind
        mov     bestv, brv
        mov     bestk, brk              | ret
atm_3:  ext     t0, brv, 0, 1
        bz      t0, agt_r
        mov     bestkind, vkind
        mov     bestv, vv
        mov     bestk, vk               | ret

ag_fin: beq     agfid, #14, agf_ao
        beq     agfid, #15, agf_ao
        ext     t0, agfid, 0, 3
        beq     t0, #4, agf_cnt
        beq     t0, #5, agf_cnt
        beq     t0, #6, agf_prod
        beq     t0, #2, agf_mm
        beq     t0, #3, agf_mm
        beq     t0, #1, agf_avg
        jmp     ag_result               ; SUM
agf_cnt:
        li      acckind, #VK_I          ; COUNT, COUNTA
        mov     accv, agcnt
        li      acck, #0                | jmp ag_result
agf_prod:
        bnz     agcnt, ag_result        ; PRODUCT (no numbers: 0)
agf_0:  li      acckind, #VK_I
        li      accv, #0
        li      acck, #0                | jmp ag_result
agf_mm: bz      agcnt, agf_0            ; MIN, MAX
        mov     acckind, bestkind
        mov     accv, bestv
        mov     acck, bestk             | jmp ag_result
agf_avg:
        bnz     agferr, ag_result       ; AVERAGE: SUM / COUNT
        bnz     agcnt, afa_1
        li      acckind, #VK_E
        li      accv, #E_DIV0           | jmp ag_result
afa_1:  mov     boka, acckind
        mov     bova, accv
        mov     bofa, acck
        li      bokb, #VK_I
        mov     bovb, agcnt
        li      bofb, #0
        li      boop, #0x13
        call    bo
        mov     acckind, brkind
        mov     accv, brv
        mov     acck, brk               | jmp ag_result
agf_ao: li      acckind, #VK_I          ; AND, OR
        li      acck, #0
        bnz     agcnt, afo_1
        li      acckind, #VK_E
        li      accv, #E_VALUE          | jmp ag_result
afo_1:  bz      agbad, afo_2
        li      acckind, #VK_E
        li      accv, #E_NUM            | jmp ag_result
afo_2:  mov     accv, agall
        beq     agfid, #14, ag_result
        mov     accv, agany             | jmp ag_result
.endscope

; ----------------------------------------------------------------------
; Scalar functions (5.7): ABS INT TRUNC SIGN SQRT NOT (one argument), MOD
; ROUND POWER (two): their arguments as numbers (blank 0; text, ranges
; #VALUE!; a fixed point past its limits #NUM!)
.scope
; the arguments as numbers; ROUND's (n, the 128-bit product and its
; shift, the bit shifted out, x, its sign, the result in fpr, a
; magnitude); MOD's a and b, POWER's (n, r, b, n negative) and SQRT's
; (rfhi..rfrb, pwr, pwn) in the same registers: never at once
.reg sakind, sav, sak, sbkind, sbv, sbk
.reg rnn, rfhi, rflo, rfsh, rfrb, rfneg, rfx, rffp, rfmag
.alias mfa = rfhi
.alias mfb = rflo
.alias pwn = rfx
.alias pwr = rffp
.alias pwb = rfmag
.alias pwneg = rfneg
sf_start:
        li      t0, #1
        beq     agfid, #13, sfs_2
        beq     agfid, #10, sfs_2
        bne     agfid, #29, sfs_c
sfs_2:  li      t0, #2
sfs_c:  bne     agargc, t0, sf_val
        mov     t0, agi                 ; the argument (or the first of two)
        call    sf_arg
        mov     sakind, t1
        mov     sav, t2
        mov     sak, t3
        li      acckind, #VK_I
        li      acck, #0
        beq     sakind, #VK_E, sf_err
        bne     sakind, #VK_I, sfs_3
        mov     t1, sak
        call    badk
        bnz     t0, sf_num
        jmp     sfs_4
sfs_3:  bne     sakind, #VK_F, sf_val
sfs_4:  beq     agfid, #16, sf_not
        beq     agfid, #7, sf_abs
        beq     agfid, #11, sf_sign
        beq     agfid, #8, sf_int
        beq     agfid, #9, sf_int
        beq     agfid, #12, sf_sqrt0
        jmp     sf_arg2                 ; MOD, ROUND, POWER: the second argument
sf_err: li      acckind, #VK_E          ; (an argument's error: the result)
        mov     accv, t2                | jmp ag_result
sf_val: li      acckind, #VK_E
        li      accv, #E_VALUE          | jmp ag_result
sf_num: li      acckind, #VK_E
        li      accv, #E_NUM            | jmp ag_result
sf_div0:
        li      acckind, #VK_E
        li      accv, #E_DIV0           | jmp ag_result
sf_nm:  li      acckind, #VK_E
        li      accv, #E_NAME           | jmp ag_result
; argument t0 of the stack RAM as a number: kind t1, value t2, k t3 (blank: 0)
sf_arg: shl     t0, t0, #1
        ldd     t2, [t0+EST]
        ldd     t3, [t0+EST+1]
        ext     t1, t3, 9, 3
        ext     t3, t3, 0, 8
        bne     t1, #VK_Z, sfa_r
        li      t1, #VK_I
        li      t2, #0
        li      t3, #0
sfa_r:  ret
; t0 = 1 if (kind t1, value t2) is zero (I 0, F +-0)
sf_zero:
        li      t0, #0
        beq     t1, #VK_I, sfz_i
        ext     t3, t2, 52, 11
        bnz     t3, sfz_r
        li      t0, #1                  | ret
sfz_i:  bnz     t2, sfz_r
        li      t0, #1
sfz_r:  ret

sf_not: mov     t1, sakind              ; NOT
        mov     t2, sav
        call    sf_zero
        mov     accv, t0                | jmp ag_result
sf_abs: bne     sakind, #VK_F, sab_i    ; ABS
        li      acckind, #VK_F
        andn    accv, sav, SIGN         | jmp ag_result
sab_i:  beq     sav, SIGN, sf_num
        mov     acck, sak
        mov     accv, sav
        bpl     sav, ag_result
        sub     accv, _, sav            | jmp ag_result
sf_sign:                                ; SIGN
        bne     sakind, #VK_F, ssg_1
        mov     t2, sav
        call    f_nan
        bnz     t1, sf_num
ssg_1:  mov     t1, sakind
        mov     t2, sav
        call    sf_zero
        li      accv, #0
        bnz     t0, ag_result
        li      accv, #1
        bpl     sav, ag_result
        li      accv, #-1               | jmp ag_result
sf_int: bne     sakind, #VK_F, sin_i    ; INT (rounds down), TRUNC (toward zero)
        li      acckind, #VK_F
        mov     t2, sav
        beq     agfid, #9, sin_t
        call    f_floor
        mov     accv, t0                | jmp ag_result
sin_t:  call    f_trunc
        mov     accv, t0                | jmp ag_result
sin_i:  ext     t0, sak, 0, 7
        mov     accv, sav
        bz      t0, ag_result
        ext     t1, sak, 7, 1
        bz      t1, sin_d
        beq     agfid, #9, sin_bt       ; binary: a shift
        sar     accv, sav, t0           | jmp ag_result
sin_bt: bpl     sav, sin_b2
        sub     accv, _, sav
        shr     accv, accv, t0
        sub     accv, _, accv           | jmp ag_result
sin_b2: shr     accv, sav, t0           | jmp ag_result
sin_d:  mov     t1, t0                  ; decimal: |v| / 10^k
        li      t2, #0
        call    pw
        mov     t2, t0
        mov     t0, sav
        bpl     t0, sin_d1
        sub     t0, _, t0
sin_d1: out     #DIVHI, _
        div     t0, t0, t2
        bpl     sav, sin_d3
        beq     agfid, #9, sin_d2
        movx    t1, DIVR
        bz      t1, sin_d2
        add     t0, t0, #1
sin_d2: sub     t0, _, t0
sin_d3: mov     accv, t0                | jmp ag_result
sf_sqrt0:
        mov     fpr, sav                ; SQRT: as F64
        bne     sakind, #VK_I, sf_sqrt
        mov     cvv, sav
        mov     cvk, sak
        call    cv
        jmp     sf_sqrt

sf_arg2:                                ; MOD's b (and ROUND's n, POWER's b)
        add     t0, agi, #1
        call    sf_arg
        mov     sbkind, t1
        mov     sbv, t2
        mov     sbk, t3
        beq     sbkind, #VK_E, sf_err
        bne     sbkind, #VK_I, sfb_1
        mov     t1, sbk
        call    badk
        bnz     t0, sf_num
        jmp     sfb_2
sfb_1:  bne     sbkind, #VK_F, sf_val
sfb_2:  beq     agfid, #10, sf_round
        beq     agfid, #29, sf_power
        mov     t1, sbkind              ; MOD: b zero: #DIV/0!
        mov     t2, sbv
        call    sf_zero
        bnz     t0, sf_div0
        bne     sakind, #VK_I, sfm_f
        bne     sbkind, #VK_I, sfm_f
        ext     t0, sak, 0, 7
        bz      t0, sfm_i
        ext     t0, sbk, 0, 7
        bz      t0, sfm_i
        xor     t0, sak, sbk
        ext     t0, t0, 7, 1
        bnz     t0, sfm_f
sfm_i:  mov     boka, sakind            ; integers: aligned through the operators'
        mov     bova, sav               ; path (EQ's alignment)
        mov     bofa, sak
        mov     bokb, sbkind
        mov     bovb, sbv
        mov     bofb, sbk
        li      boop, #0x18
        call    bo
        bne     brkind, #VK_E, sfm_i2
        li      acckind, #VK_E
        mov     accv, brv               | jmp ag_result
sfm_i2: mov     t0, xa                  ; |a| mod |b|; floor mod: the divisor's sign
        bpl     t0, sfm_i3
        sub     t0, _, t0
sfm_i3: mov     t2, xb
        bpl     t2, sfm_i4
        sub     t2, _, t2
sfm_i4: out     #DIVHI, _
        div     t0, t0, t2
        movx    t1, DIVR                ; (r)
        li      acckind, #VK_I
        mov     acck, xk
        li      accv, #0
        bz      t1, ag_result
        xor     t0, xa, xb
        bmi     t0, sfm_i5
        mov     accv, t1                ; the same signs: r, with b's
        bpl     xb, ag_result
        sub     accv, _, t1             | jmp ag_result
sfm_i5: sub     accv, t2, t1            ; else d - r, with b's
        bpl     xb, ag_result
        sub     accv, _, accv           | jmp ag_result
sfm_f:  mov     cvv, sav                ; F64: a - b x floor(a / b)
        mov     cvk, sak
        mov     fpr, sav
        bne     sakind, #VK_I, sfm_f1
        call    cv
sfm_f1: mov     mfa, fpr
        mov     cvv, sbv
        mov     cvk, sbk
        mov     fpr, sbv
        bne     sbkind, #VK_I, sfm_f2
        call    cv
sfm_f2: mov     mfb, fpr
        mov     fpa, mfa
        mov     fpb, mfb
        li      fpop, #FP_DIV
        call    fp
        ext     t0, fpr, 52, 11         ; (q infinite or NaN: the result NaN)
        bne     t0, #2047, sfm_f3
        li      acckind, #VK_F
        mov     accv, F64_NAN           | jmp ag_result
sfm_f3: mov     t2, fpr
        call    f_floor
        mov     fpa, mfb
        mov     fpb, t0
        li      fpop, #FP_MUL
        call    fp
        mov     fpa, mfa
        mov     fpb, fpr
        li      fpop, #FP_SUB
        call    fp
sf_fres:
        li      acckind, #VK_F
        mov     accv, fpr
        li      acck, #0                | jmp ag_result

; ROUND(x, n): n an integer in -18..18
sf_round:
        bne     sbkind, #VK_I, sf_num
        ext     t0, sbk, 0, 7
        bnz     t0, sf_num
        bgt     sbv, #18, sf_num
        blt     sbv, #-18, sf_num
        exts    rnn, sbv, 0, 8
        bne     sakind, #VK_I, sfr_f
        ext     t0, sak, 0, 7
        bz      t0, sfr_i
        ext     t0, sak, 7, 1
        bz      t0, sfr_i
        mov     cvv, sav                ; (binary fixed point: as F64)
        mov     cvk, sak
        call    cv
        jmp     sfr_f1
sfr_f:  mov     fpr, sav
sfr_f1: jmp     sf_rndf
; integers (decimal fixed point k): to n decimals, half away
sfr_i:  ext     t2, sak, 0, 7           ; (k)
        mov     acck, sak
        mov     accv, sav
        bge     rnn, t2, ag_result
        sub     t1, t2, rnn             ; (k - n)
        bleu    t1, #19, sfr_i1
        li      accv, #0                ; (rounds to 0)
        li      acck, #0
        blt     rnn, _, ag_result
        mov     acck, rnn               | jmp ag_result
sfr_i1: ldd     t2, [t1+P10T]
        mov     t0, sav
        li      dvneg, #0
        bpl     t0, sfr_i2
        sub     t0, _, t0
        li      dvneg, #1
sfr_i2: out     #DIVHI, _
        div     t0, t0, t2
        call    dv_round
        bz      dvneg, sfr_i3
        sub     t0, _, t0
sfr_i3: blt     rnn, _, sfr_i4
        mov     accv, t0                ; n >= 0: q
        mov     acck, rnn               | jmp ag_result
sfr_i4: li      acck, #0                ; n < 0: q x 10^-n
        sub     t1, _, rnn
        ldd     t1, [t1+P10T]
        call    smul
        call    mu_fit
        bnz     t1, sf_num
        mov     accv, t0                | jmp ag_result
; ROUND, F64, exactly.  |x| = m x 2^E.  n >= 0: p = m x 10^n, N = p / 2^-E
; rounded half away (unless no digits are below 10^-n, or |x| x 10^n >=
; 2^53: x itself), then F64(N) / F64(10^n).  n < 0: |x|'s integer part,
; rounded at 10^-n, times 10^-n (|x| >= 2^63: x)
sf_rndf:
        mov     rfx, fpr
        shr     rfneg, fpr, #63
        li      rffp, #0
        li      rfmag, #0
        li      acckind, #VK_F
        li      acck, #0
        mov     accv, fpr
        ext     t0, fpr, 52, 11         ; (zeros, infinities, NaN: as they are)
        bz      t0, sfr_4
        beq     t0, #2047, sfr_4
        li      rfsh, #1075
        sub     rfsh, rfsh, t0          ; (-E)
        ext     t1, fpr, 0, 52
        ins     t1, M32, t1, 52, 1      ; (m)
        blt     rnn, _, sfr_neg
        bge     t0, #1075, sfr_4        ; E >= 0: integral, nothing below 10^-n
        ldd     t0, [rnn+P10T]          ; p = m x 10^n (128 bits)
        mul     rflo, t1, t0
        movx    rfhi, MULHI
        li      rfrb, #0
        blt     rfsh, #115, sfr_sh
        li      rfhi, #0                ; (p < 2^113: rounds to 0)
        li      rflo, #0
        li      rfsh, #0
sfr_sh: bz      rfsh, sfr_n             ; p >> -E, the last bit out kept
        sub     t0, rfsh, #1            ; (shifted by sh - 1, then the bit)
        call    rf_shr
        ext     rfrb, rflo, 0, 1
        li      t0, #1
        call    rf_shr
sfr_n:  ; N = floor + the rounding bit
        shr     t0, rflo, #53
        or      t0, t0, rfhi
        bz      t0, sfr_n1
        mov     accv, rfx               | jmp sfr_4     ; |x| x 10^n >= 2^53: x
sfr_n1: add     fnsig, rflo, rfrb
        bnz     fnsig, sfr_n2
        li      accv, #0                ; (rounds to 0)
        li      rfmag, #1               | jmp sfr_4
sfr_n2: li      fns, #0
        li      fne, #1086
        li      fnst, #0
        call    fn_norm                 ; F64(N); then F64(10^n)
        mov     cvt, fpr
        li      fns, #0
        ldd     fnsig, [rnn+P10T]
        li      fne, #1086
        li      fnst, #0
        call    fn_norm
        mov     fpa, cvt
        mov     fpb, fpr
        li      fpop, #FP_DIV
        call    fp
        li      rffp, #1
        li      rfmag, #1               | jmp sfr_4
sfr_neg:                                ; n < 0
        bge     t0, #1086, sfr_4        ; |x| >= 2^63: x
        li      rfhi, #0                ; the integer part: m shifted
        mov     rflo, t1
        blt     rfsh, _, sfr_ng1
        bltu    rfsh, #64, sfr_ng0
        li      rflo, #0                | jmp sfr_ng2   ; (m < 2^53: nothing left)
sfr_ng0:
        mov     t0, rfsh
        call    rf_shr
        jmp     sfr_ng2
sfr_ng1:
        sub     t0, _, rfsh             ; (E > 0: left, at most 10)
        shl     rflo, rflo, t0
sfr_ng2:
        sub     t1, _, rnn              ; (k = -n)
        ldd     t2, [t1+P10T]
        out     #DIVHI, rfhi
        div     t0, rflo, t2            ; q, r: N = q + (r >= 5 x 10^(k-1))
        movx    t3, DIVR
        sub     t1, t1, #1
        ldd     t1, [t1+P10T]
        shl     rfrb, t1, #2
        add     t1, rfrb, t1            ; (5 x 10^(k-1))
        bltu    t3, t1, sfr_ng3
        add     t0, t0, #1
sfr_ng3:
        mul     t0, t0, t2              ; N x 10^k (< 2^64), to F64
        li      rfmag, #1
        li      accv, #0
        bz      t0, sfr_4
        li      fns, #0
        mov     fnsig, t0
        li      fne, #1086
        li      fnst, #0
        call    fn_norm
        li      rffp, #1
sfr_4:  ; the result, with x's sign on a magnitude
        bz      rffp, sfr_41
        mov     accv, fpr
sfr_41: bz      rfmag, sfr_42
        ins     accv, rfneg, accv, 63, 1
sfr_42: li      acckind, #VK_F
        li      acck, #0                | jmp ag_result
; rfhi:rflo >> t0 (t0 0-127)
rf_shr: bz      t0, rfs_r
        bltu    t0, #64, rfs_1
        sub     t0, t0, #64
        shr     rflo, rfhi, t0
        li      rfhi, #0                | ret
rfs_1:  shr     rflo, rflo, t0
        li      t1, #64
        sub     t1, t1, t0
        shl     t1, rfhi, t1
        or      rflo, rflo, t1
        shr     rfhi, rfhi, t0
rfs_r:  ret

; POWER(a, n): n an integer (a fraction: not yet)
sf_power:
        bne     sbkind, #VK_I, sf_nm
        ext     t0, sbk, 0, 7
        bnz     t0, sf_nm
        mov     t1, sakind
        mov     t2, sav
        call    sf_zero
        bz      t0, spw_1
        bz      sbv, sf_num             ; 0 ^ 0
        bmi     sbv, sf_div0            ; 0 ^ negative
spw_1:  shr     pwneg, sbv, #63
        mov     pwn, sbv
        bz      pwneg, spw_2
        sub     pwn, _, sbv
spw_2:  ; integers to a non-negative power, exactly, while the fixed point fits
        bne     sakind, #VK_I, spw_f
        bnz     pwneg, spw_f
        ext     t2, sak, 0, 7
        bz      t2, spw_i
        bgeu    sbv, #63, spw_f
        ext     t1, sbv, 0, 6
        mul     t1, t2, t1              ; (k x n)
        ext     t3, sak, 7, 1
        bz      t3, spw_d
        bgtu    t1, #62, spw_f
        jmp     spw_i
spw_d:  bgtu    t1, #18, spw_f
spw_i:  li      acckind, #VK_I
        li      accv, #1
        li      acck, #0
        bz      t2, spw_i1
        bz      sbv, spw_i1
        ext     t3, sbv, 0, 6
        mul     t3, t2, t3
        ext     t0, sak, 7, 1
        ins     acck, t0, t3, 7, 1
spw_i1: bz      sbv, ag_result
        bleu    sav, #1, spw_i2
        beq     sav, #-1, spw_m1        ; (-1: by the exponent's parity)
        bgtu    sbv, #63, sf_num
spw_lp: bz      pwn, ag_result          ; acc x a, n times
        mov     t0, accv
        mov     t1, sav
        call    smul
        call    mu_fit
        bnz     t1, sf_num
        mov     accv, t0
        sub     pwn, pwn, #1            | jmp spw_lp
spw_i2: mov     accv, sav               | jmp ag_result
spw_m1: ext     t0, sbv, 0, 1
        bz      t0, ag_result
        mov     accv, sav               | jmp ag_result
spw_f:  mov     fpr, sav                ; F64: square and multiply from the low bit,
        bne     sakind, #VK_I, spw_f1   ; then 1 / r for n < 0
        mov     cvv, sav
        mov     cvk, sak
        call    cv
spw_f1: mov     pwb, fpr
        mov     pwr, F64_ONE
spw_f2: bz      pwn, spw_f5
        ext     t0, pwn, 0, 1
        bz      t0, spw_f3
        mov     fpa, pwr
        mov     fpb, pwb
        li      fpop, #FP_MUL
        call    fp
        mov     pwr, fpr
spw_f3: shr     pwn, pwn, #1            | z spw_f2      ; the next bit; a square only if one remains
        mov     fpa, pwb
        mov     fpb, pwb
        li      fpop, #FP_MUL
        call    fp
        mov     pwb, fpr                | jmp spw_f2
spw_f5: li      acckind, #VK_F
        li      acck, #0
        mov     accv, pwr
        bz      pwneg, ag_result
        ext     t0, pwr, 52, 11         ; 1 / +-0: +-inf
        bnz     t0, spw_f6
        and     accv, pwr, SIGN
        li      t0, #2047
        ins     accv, t0, accv, 52, 11  | jmp ag_result
spw_f6: mov     fpa, F64_ONE
        mov     fpb, pwr
        li      fpop, #FP_DIV
        call    fp
        jmp     sf_fres

; SQRT, F64 (fpr): negatives #NUM!; NaN, infinity, zeros as they are
sf_sqrt:
        li      acckind, #VK_F
        li      acck, #0
        mov     accv, fpr
        mov     t2, fpr
        call    f_nan
        bnz     t1, ag_result
        ext     t0, fpr, 52, 11
        bz      t0, ag_result
        bpl     fpr, sqt_1
        li      acckind, #VK_E
        li      accv, #E_NUM            | jmp ag_result
sqt_1:   beq     t0, #2047, ag_result    ; (+inf)
        ; the significand times 2^74 (an odd exponent: 2^75), into rfhi:rflo
        ext     t1, fpr, 0, 52
        ins     t1, M32, t1, 52, 1      ; (m, 53 bits)
        ext     t2, fpr, 52, 1
        li      t3, #10                 ; (m x 2^74: m << 10 in the high word)
        bnz     t2, sqt_2
        li      t3, #11
sqt_2:   shl     rfhi, t1, t3
        li      rflo, #0
        sub     t0, t0, #1023           ; the exponent: 1023 + (e - 1023) / 2
        sar     t0, t0, #1
        add     fne, t0, #1023
        out     #DIVHI, rfhi            ; the root (restoring, a bit a cycle), its remainder
        sqrt    pwr, rflo
        movx    rfrb, SQRH
        movx    rfsh, DIVR
        li      fns, #0
        mov     fnsig, pwr
        or      t0, rfrb, rfsh
        li      fnst, #0
        bz      t0, sqt_3
        li      fnst, #1
sqt_3:   call    fn_norm
        jmp     sf_fres
.endscope

; F64 helpers on t2 (inputs never subnormal), the result in t0 (t1, t3 used):
; rounded toward zero (the fraction bits cleared); down
f_trunc:
        mov     t0, t2
        ext     t1, t2, 52, 11
        beq     t1, #2047, ft_r         ; (inf, NaN)
        sub     t1, t1, #1023           ; (e)
        bge     t1, #52, ft_r           ; (integral)
        bge     t1, _, ft_1
        and     t0, t2, SIGN            | ret       ; |x| < 1: a signed zero
ft_1:   li      t3, #52
        sub     t3, t3, t1              ; (the fraction's bits: 52 - e)
        shr     t0, t2, t3
        shl     t0, t0, t3
ft_r:   ret
f_floor:
        call    f_trunc
        bpl     t2, ff_r                ; a negative with a fraction: one further
        beq     t0, t2, ff_r            ; (no fraction)
        ext     t1, t2, 52, 11
        bz      t1, ff_r
        sub     t1, t1, #1023
        bge     t1, _, ff_1
        mov     t0, F64_M1              | ret       ; (-1 when |x| < 1)
ff_1:   li      t3, #52
        sub     t3, t3, t1
        li      t1, #1
        shl     t1, t1, t3
        add     t0, t0, t1              ; (|t| + one unit: the exponent may carry)
ff_r:   ret
.endscope
