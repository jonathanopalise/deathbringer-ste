    ORG $80000 ; tell the assembler that this code is intended to be located at address $80000

draw_blitter_ground_super_wrapper:
    ; Deathbringer seems to run in the 68000's user mode for the most part, including at the point where the ground
    ; is normally drawn. If we try to write to the Blitter registers when in user mode, we'll crash the machine. We
    ; therefore need to temporarily switch to supervisor mode in order to draw the ground using the Blitter.

    movem.l a0-a2/d0-d2,regs_backup      ; backup registers before switching to supervisor mode

    pea draw_blitter_ground              ; xbios call to call draw_blitter_ground subroutine in supervisor mode
    move.w #$26,-(sp)
    trap #14
    addq.l #6,sp
    rts                                  ; return to main (unmodified) body of game code

regs_backup:
    ds.l 6                               ; 6 long words of storage for backup of regs during supervisor mode switch

draw_blitter_ground:
    movem.l regs_backup,a0-a2/d0-d2      ; restore registers following switch to supervisor mode

    ; First, set up all of the blitter registers. For many of the registers, we only need to do this once, and we can
    ; then perform multiple blits.
    ; 
    ; The Blitter seems to work roughly as follows:
    ;
    ; for (y = 1; y <= y_count; y++) {
    ;     for (x = 1; x <= x_count; x++) {
    ;         transfer word from source_address to destination_address using selected hop/op
    ;         if (x == x_count) {
    ;             source_address += source_x_increment;
    ;             destination_address += dest_x_increment;
    ;         } else {
    ;             source_address += source_y_increment;
    ;             destination_address += dest_y_increment;
    ;         }
    ;     }
    ; }
    ;
    ; As part of this initial setup, we're setting the following registers:
    ;
    ; source_x_increment 8a20:
    ;   how many bytes to add to the source address after writing each word. We set to 6 because we're drawing one
    ;   bitplane at a time, and the source data contains 3 interleaved bitplanes.
    ;
    ; source_y_increment 8a22:
    ;   how many bytes to add to the source address after writing each line. We decrement by 118 as this returns the
    ;   source address to the start of the source data for the next bitplane once a line has been drawn, meaning that
    ;   the source address is in the correct place ready for the next bitplane to be drawn.
    ;
    ; endmask1 8a28/endmask2 8a2a/endmask3 8a2c:
    ;   masking for the beginning, middle and end of each line. Leaving all three values at $ffff means that no source
    ;   values get masked out when writing to the destination.
    ;
    ; dest_x_increment 8a2e:
    ;   how many bytes to add to the destination address after writing each word. We set this to 8 because we're
    ;   drawing one bitplane at a time on a destination containing 4 interleaved bitplanes.
    ;
    ; dest_y_increment 8a30:
    ;   how many bytes to add to the destination address after writing each line. We set this to decrement by 150 as
    ;   this returns the destination address to the correct location for the next bitplane once a bitplane has been
    ;   drawn.
    ;
    ; x_count 8a36:
    ;   how many words to transfer from the source to the destination on each line. We set this to 20 as we'll be
    ;   drawing 20 words (40 bytes) in each of the 4 destination bitplanes, giving a total 160 bytes, which is the
    ;   number of bytes in a single line of the ST's screen buffer.

    lea $ffff8a20.w,a3
    move.w #6,(a3)+                      ; source x increment 8a20
    move.w #-118,(a3)                    ; source y increment 8a22
    addq.l #6,a3                         ; skip source address 8a24 - we'll set it later
    move.w #$ffff,(a3)+                  ; endmask1 8a28
    move.w #$ffff,(a3)+                  ; endmask2 8a2a
    move.w #$ffff,(a3)+                  ; endmask3 8a2c
    move.w #8,(a3)+                      ; dest x increment 8a2e
    move.w #-150,(a3)                    ; dest y increment 8a30
    addq.l #6,a3                         ; skip dest address 8a32 - we'll set it later
    move.w #20,(a3)                      ; xcount 8a36 - 20 words is one line in one bitplane

    ; As with the original code, we need a loop to draw 35 lines. The d7 register will track the number of lines
    ; remaining.
    ;
    ; Note that at this point, the original game code has set the a1 register as the destination address at which
    ; we need to start drawing the ground. The a2 register contains the address of the data needed to determine the
    ; horizontal scroll position of each line we'll be drawing.

    moveq.l #$23,d7                      ; use d7 as counter - we're going to draw 35 lines of ground

draw_ground_line:

    ; This is the start of the code that draws each line of the ground.
    ;
    ; Note that this following block of 12 lines is mostly taken from the original game code. We don't need to have
    ; an in-depth understanding of how this code works - we just need to know that it's purpose is to determine two
    ; things:
    ;
    ; 1) The source start address in memory that we'll be copying graphics data from for this line
    ;
    ;    This address will be a multiple of 8, as the planar graphics arrangement on the ST arranges screen data in
    ;    blocks of 16 pixels, and each pixel takes up half a byte or 4 bits. The resulting value is placed in the a3
    ;    register, ready to be dropped into the Blitter destination register 8a32 further down.
    ;
    ; 2) The number of pixels that we'll need to skew the source data to the right before writing it to the
    ;    destination
    ;
    ;    This is where the real magic of the Blitter happens. The CPU has to jump through some long-winded hoops in
    ;    order to perform per-pixel horizontal scrolling as evidenced by the original code running from address cc32
    ;    to cc4e. The Blitter, on the other hand, can perform this task for free through use of the Skew function! The
    ;    resulting Skew value as generated by this code is placed in the d5 register, ready to be dropped into the
    ;    Skew register 8a3d further down.

    move.w (a2)+,d0
    add.w (a2)+,d0
    move.w d0,d5
    not.w d5
    lsr.w #4,d0
    move.w d0,d1
    add.w d0,d0
    add.w d1,d0
    add.w d0,d0
    move.l (a0)+,a3
    add.w d0,a3
    and.w #$f,d5

    ; Now that we know where we need to copy data from, and how many pixels to skew to the right, we need to populate
    ; Blitter registers accordingly and start the blit.
    ;
    ; The source data contains three bitplanes, and we're writing to a destination buffer that contains four
    ; bitplanes. We therefore perform two seperate Blitter passes. The first pass copies three bitplanes (lines) of 
    ; source data to the corresponding bitplanes in the destination, and the second sets the fourth bitplane of the
    ; destination to all ones.
    ;
    ; Once both Blitter passes have completed (i.e. we've managed to draw 320 pixels), we advance the destination
    ; pointer (a1) to the next line, and decrement the line counter (d7). If no further lines need to be drawn, we
    ; return back to the code that called this subroutine.
    ;
    ; Note that the only Blitter registers that must be reinitialised to start a Blitter pass are ycount 8a38 (to
    ; set the number of lines) and control 8a3c (to actually start the transfer) - the Blitter will act upon the
    ; existing value of all other registers.
 
    move.l a3,$ffff8a24.w      ; source address 8a24
    move.l a1,$ffff8a32.w      ; destination address 8a32
    or.b #$80,d5               ; generate a value for skew 8a3d - fxsr combined with d5 skew value from above
    move.b d5,$ffff8a3d.w      ; skew 8a3d

    move.w #3,$ffff8a38.w      ; ycount 8a38 - draw 3 lines (i.e. 3 bitplanes)
    move.w #$0203,$ffff8a3a.w  ; hop/op 8a3a - set blitter to copy from source to destination
    move.b #$c0,$ffff8a3c.w    ; control 8a3c - start blitter in hog mode

    move.w #1,$ffff8a38.w      ; ycount 8a38 - draw one line (i.e. 4th and final bitplane)
    move.w #$f,$ffff8a3a.w     ; hop/op 8a38 - set blitter to write all 1's for bitplane 4
    move.b #$c0,$ffff8a3c.w    ; control 8a3c - start blitter in hog mode

    lea 160(a1),a1             ; advance destination address by one line

    dbra d7,draw_ground_line   ; loop around to start drawing the next line
    rts

