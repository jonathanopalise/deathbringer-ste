    ORG $cc02

cc02_redirect_super_wrapper:
    move.l a0,a0_backup
    move.l a1,a1_backup
    move.l a2,a2_backup
    move.l d0,d0_backup
    move.l d1,d1_backup
    move.l d2,d2_backup

    pea cc02_redirect
    move.w #$26,-(sp)
    trap #14
    addq.l #6,sp
    rts

a0_backup:
    dc.l 0
a1_backup:
    dc.l 0
a2_backup:
    dc.l 0
d0_backup:
    dc.l 0
d1_backup:
    dc.l 0
d2_backup:
    dc.l 0

cc02_redirect:
    move.l a0_backup,a0
    move.l a1_backup,a1
    move.l a2_backup,a2
    move.l d0_backup,d0
    move.l d1_backup,d1
    move.l d2_backup,d2

    ; init blitter
    lea $ffff8a20.w,a3
    move.w #6,(a3)+            ; source x increment 8a20
    move.w #-118,(a3)          ; source y increment 8a22
    addq.l #6,a3               ; source address 8a24
    move.w #-1,(a3)+           ; endmask1 8a28
    move.w #-1,(a3)+           ; endmask2 8a2a
    move.w #-1,(a3)+           ; endmask3 8a2c
    move.w #8,(a3)+            ; dest x increment 8a2e
    move.w #-150,(a3)          ; dest y increment 8a30
    addq.l #6,a3               ; dest address 8a32
    move.w #20,(a3)            ; xcount 8a36
    addq.l #4,a3               ; ycount 8a38
    move.w #$0203,(a3)         ; hop/op 8a3a
    ;move.b #0,3(a3)            ; skew etc 8a3d

    moveq     #$23,d7

label_cc04:
    move.w    (a2)+,d0
    add.w     (a2)+,d0
    move.w    d0,d5
    not.w     d5
    lsr.w     #4,d0
    move.w    d0,d1
    add.w     d0,d0
    add.w     d1,d0
    add.w     d0,d0
    movea.l   (a0)+,a3
    adda.w    d0,a3
    movea.l   a3,a4
    moveq     #-1,d2
    moveq     #$13,d6
    andi.w    #$f,d5
    ;beq       $cc8a
    ;cmp.w     #8,d5
    ;bge       $cc5a
    ;addq.w    #6,a4

    ; now draw 3 bitplanes from source a4 to destination a1
    ; d5 contains skew value

    move.l a4,$ffff8a24.w      ; source address
    move.l a1,$ffff8a32.w      ; destination address
    move.w #$0203,$ffff8a3a.w  ; hop/op
    or.w #$c080,d5             ; hog mode, fxsr

    move.w #1,$ffff8a38.w      ; ycount
    move.w d5,$ffff8a3c.w      ; start blitter

    move.w #1,$ffff8a38.w      ; ycount
    move.w d5,$ffff8a3c.w      ; start blitter

    move.w #1,$ffff8a38.w      ; ycount
    move.w d5,$ffff8a3c.w      ; start blitter

    move.w #$f,$ffff8a3a.w      ; hop/op
    move.w #1,$ffff8a38.w      ; ycount
    move.w d5,$ffff8a3c.w      ; start blitter

    lea 160(a1),a1

;label_cc32:
;    move.l    (a3)+,d0
;    move.w    d0,d1
;    move.w    (a4)+,d0
;    lsr.l     d5,d0
;    move.w    d0,(a1)+
;    swap      d1
;    move.w    (a4)+,d1
;    lsr.l     d5,d1
;    move.w    d1,(a1)+
;    move.w    (a3)+,d0
;    swap      d0
;    move.w    (a4)+,d0
;    lsr.l     d5,d0
;    move.w    d0,(a1)+
;    move.w    d2,(a1)+
;    dbra      d6,label_cc32

    dbra      d7,label_cc04
    rts       



