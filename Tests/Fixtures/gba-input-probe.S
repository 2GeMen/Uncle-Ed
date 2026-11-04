/* SPDX-License-Identifier: GPL-3.0-or-later
 * Original synthetic GBA probe. No Nintendo logo, BIOS or game assets.
 * Mode 3: red background, green while A is held. SRAM byte tracks A.
 */
.syntax unified
.arm
.section .text
.global _start
_start:
 b reset
 .space 0xb2-4
 .byte 0x96
 .space 0xc0-0xb3
reset:
 ldr r0, =0x04000000
 ldr r1, =0x0403
 strh r1, [r0]
loop:
 ldr r0, =0x04000130
 ldrh r1, [r0]
 tst r1, #1
 moveq r3, #1
 movne r3, #0
 ldr r0, =0x0e000000
 strb r3, [r0]
 ldr r0, =0x06000000
 ldreq r1, =0x03e0
 ldrne r1, =0x001f
 ldr r2, =38400
fill:
 strh r1, [r0], #2
 subs r2, r2, #1
 bne fill
 b loop
 .ltorg
