const common = @import("common.zig");

const inb = common.inb;
const outb = common.outb;

const pic1_cmd = 0x20;
const pic1_data = 0x21;
const pic2_cmd = 0xA0;
const pic2_data = 0xA1;

// 0x10 meant init, ox11 means ICW4 is present
const pic_init = 0x11;
const pic_8086 = 0x1; // No one really knows what this does

// See: 8259 PIC datasheet

pub fn initPic(offset: u32, irq_mask: u16) void {
    outb(pic1_cmd, pic_init);
    outb(pic2_cmd, pic_init);

    outb(pic1_data, offset);
    outb(pic2_data, offset + 8);

    outb(pic1_data, 4); // There is a slave PIC on IRQ2
    outb(pic2_data, 2); // There is a master PIC

    outb(pic1_data, pic_8086);
    outb(pic2_data, pic_8086);

    outb(pic1_data, irq_mask & 0xFF);
    outb(pic2_data, irq_mask >> 8);
}

const pic_eoi = 0x20; // End of Interrupt

pub fn picEOI(irq: u8) void {
    if (irq >= 8) outb(pic2_cmd, pic_eoi);
    outb(pic1_cmd, pic_eoi);
}
