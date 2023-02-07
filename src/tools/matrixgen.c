#include <stdio.h>

char *normal = " .byte $14,$0d,$1d,$88,$85,$86,$87,$11  ;del ret rt  f7  f1  f3  f5  dn"
               " .byte $33,$57,$41,$34,$5a,$53,$45,$01  ; 3   w   a   4   z   s   e  shf"
               " .byte $35,$52,$44,$36,$43,$46,$54,$58  ; 5   r   d   6   c   f   t   x"
               " .byte $37,$59,$47,$38,$42,$48,$55,$56  ; 7   y   g   8   b   h   u   v"
               " .byte $39,$49,$4a,$30,$4d,$4b,$4f,$4e  ; 9   i   j   0   m   k   o   n"
               " .byte $2b,$50,$4c,$2d,$2e,$3a,$40,$2c  ; +   p   l   -   .   :   @   ,"
               " .byte $5c,$2a,$3b,$13,$01,$3d,$5e,$2f  ;lb.  *   ;  hom shf  =   ^   /"
               " .byte $31,$5f,$04,$32,$20,$02,$51,$03  ; 1  <-- ctl  2  spc  C=  q stop"
               " .byte $ff,$09,$08,$84,$10,$16,$19,$1b  ;scl tab alt hlp  f9 f11 f13 esc"
               " .byte $ff";

char *shifted = "  mode2      ;English shifted keys (right keycap graphics)"
                ""
                " .byte $94,$8d,$9d,$8c,$89,$8a,$8b,$91  ;ins RTN lft f8  f2  f4  f6  up"
                " .byte $23,$d7,$c1,$24,$da,$d3,$c5,$01  ; #   W   A   $   Z   S   E  shf"
                " .byte $25,$d2,$c4,$26,$c3,$c6,$d4,$d8  ; %   R   D   &   C   F   T   X"
                " .byte $27,$d9,$c7,$28,$c2,$c8,$d5,$d6  ; '   Y   G   (   B   H   U   V"
                " .byte $29,$c9,$ca,$30,$cd,$cb,$cf,$ce  ; )   I   J   0   M   K   O   N"
                " .byte $db,$d0,$cc,$dd,$3e,$5b,$ba,$3c  ;+gr  P   L  -gr  >   [  @gr  <"
                " .byte $a9,$c0,$5d,$93,$01,$3d,$de,$3f  ;lbg *gr  ]  clr shf  =  pi   ?"
                " .byte $21,$5f,$04,$22,$a0,$02,$d1,$83  ; !  <-- ctl  \"  SPC  C=  Q  run"
                " .byte $ff,$1a,$08,$84,$15,$17,$1a,$1b  ;scl TAB alt hlp f10 f12 f14 esc"
                " .byte $ff";

char *mega = "mode3      ;English C= keys (left keycap graphics)"
             ""
             " .byte $94,$8d,$9d,$8c,$89,$8a,$8b,$91  ;ins RTN lft f8  f2  f4  f6  up"
             " .byte $96,$b3,$b0,$97,$ad,$ae,$b1,$01  ;red  W   A  cyn  Z   S   E  shf"
             " .byte $98,$b2,$ac,$99,$bc,$bb,$a3,$bd  ;pur  R   D  grn  C   F   T   X"
             " .byte $9a,$b7,$a5,$9b,$bf,$b4,$b8,$be  ;blu  Y   G  yel  B   H   U   V"
             " .byte $29,$a2,$b5,$30,$a7,$a1,$b9,$aa  ; )   I   J   0   M   K   O   N"
             " .byte $a6,$af,$b6,$dc,$7c,$7b,$a4,$7e  ;+gr  P   L  -gr  |   {  @gr  ~"
             " .byte $a8,$df,$7d,$93,$01,$5f,$de,$5c  ;lbg *gr  }  clr SHF  _  pi   \\"
             " .byte $81,$60,$04,$95,$a0,$02,$ab,$03  ;blk <-- ctl wht spc  C=  Q  run"
             " .byte $ff,$18,$08,$84,$15,$17,$1a,$1b  ;scl TAB alt hlp f10 f12 f14 esc"
             " .byte $ff";

char *control = "mode4      ;English control keys"
                ""
                " .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff  ; ~   ~   ~   ~   ~   ~   ~   ~"
                " .byte $1c,$17,$01,$9f,$1a,$13,$05,$ff  ;red /w  /a  cyn /z  /s  /e   ~"
                " .byte $9c,$12,$04,$1e,$03,$06,$14,$18  ;pur /r  /d  grn /c  /f  /t  /x"
                " .byte $1f,$19,$07,$9e,$02,$08,$15,$16  ;blu /y  /g  yel /b  /h  /u  /v"
                " .byte $12,$09,$0a,$92,$0d,$0b,$0f,$0e  ;ron /i  /j  rof /m  /k  /o  /n"
                " .byte $ff,$10,$0c,$ff,$ff,$1b,$00,$ff  ; ~  /p  /l   ~   ~  /[  /@   ~"
                " .byte $1c,$ff,$1d,$ff,$ff,$1f,$1e,$ff  ;/lb  ~  /]   ~   ~  /=  /pi  ~"
                " .byte $90,$60,$ff,$05,$ff,$ff,$11,$ff  ;blk /<-  ~  wht  ~   ~  /q   ~"
                " .byte $ff,$09,$08,$84,$ff,$ff,$ff,$1b  ;scl tab alt hlp  ~   ~   ~  esc"
                " .byte $ff";

char *capslock = "mode5      ;English caps lock mode"
                 ""
                 " .byte $14,$0d,$1d,$88,$85,$86,$87,$11  ;del ret rt  f7  f1  f3  f5  dn"
                 " .byte $33,$d7,$c1,$34,$da,$d3,$c5,$01  ; 3   w   a   4   z   s   e  shf"
                 " .byte $35,$d2,$c4,$36,$c3,$c6,$d4,$d8  ; 5   r   d   6   c   f   t   x"
                 " .byte $37,$d9,$c7,$38,$c2,$c8,$d5,$d6  ; 7   y   g   8   b   h   u   v"
                 " .byte $39,$c9,$ca,$30,$cd,$cb,$cf,$ce  ; 9   i   j   0   m   k   o   n"
                 " .byte $2b,$d0,$cc,$2d,$2e,$3a,$40,$2c  ; +   p   l   -   .   :   @   ,"
                 " .byte $5c,$2a,$3b,$13,$01,$3d,$5e,$2f  ;lb.  *   ;  hom shf  =   ^   /"
                 " .byte $31,$5f,$04,$32,$20,$02,$d1,$03  ; 1  <-- ctl  2  spc  C=  q stop"
                 " .byte $ff,$09,$08,$84,$10,$16,$19,$1b  ;scl tab alt hlp  f9 f11 f13 esc"
                 " .byte $ff";

int convert(char *name, char *s)
{
  printf("  signal matrix_petscii_%s : key_matrix_t := (\n", name);
  for (int i = 0; i < 72; i++) {
    s = strchr(s, '$');
    char hex[3];
    hex[0] = s[1];
    hex[1] = s[2];
    hex[2] = 0;
    int v = strtoll(hex, NULL, 16);
    s++;
    printf("    %d => x\"%02x\",\n", i, v);
  }
  printf("    others => x\"ff\"\n"
         "  );\n\n");
}

int main(int argc, char **argv)
{
  convert("normal", normal);
  convert("shifted", shifted);
  convert("control", control);
  convert("mega", mega);
  convert("capslock", capslock);

  return 0;
}
