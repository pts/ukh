#! /bin/sh --
set -ex
test "$0" = "${0%/*}" && cd "${0%/*}"

if ! test -f memtest86+-5.01-dist-lzma.bin; then
  dd if=memtest86+-5.01.bin bs=512 skip=5 of=upxbc1.tmp
  upxbc --upx=upx.pts --flat32 --lzma -f -o upxbc2.tmp upxbc1.tmp
  (dd if=/dev/zero bs=512 count=5 && cat upxbc2.tmp) >memtest86+-5.01-dist-lzma.bin || exit "$?"
fi

nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -o memtest86+.kernel.bin ukh.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist.bin'" -DMULTIBOOT -o memtest86+.multiboot.bin ukh.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DMEMTEST86PLUS5 -DMEMTEST86PLUS5_BIN="'memtest86+-5.01-dist-lzma.bin'" -o memtest86+.lzma.kernel.bin ukh.nasm  # !! This doesn't work yet.
ls -ld memtest86+.kernel.bin memtest86+.lzma.kernel.bin

gunzip -cd <fd1440k.bin.gz >fd1440k.bin
cp -a fd1440k.bin fddr703.img && truncate -s 1440K fddr703.img && dd of=fddr703.img if=bs/dr-dos-7.03-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fddr703.img memtest86+.multiboot.bin ::IBMBIO.COM || exit "$?"  # Does not work, allows only <=29 KiB kernel.
cp -a fd1440k.bin fdedr8.img  && truncate -s 1440K fdedr8.img  && dd of=fdedr8.img  if=bs/edr-dos-7.01.08-fixed-fat12-bs.bin      bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdedr8.img  memtest86+.multiboot.bin ::DRBIO.SYS  || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB.
cp -a fd1440k.bin fdfd10.img  && truncate -s 1440K fdfd10.img  && dd of=fdfd10.img  if=bs/freedos-1.2-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd10.img  memtest86+.multiboot.bin ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd11.img  && truncate -s 1440K fdfd11.img  && dd of=fdfd11.img  if=bs/freedos-1.3-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd11.img  memtest86+.multiboot.bin ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd12.img  && truncate -s 1440K fdfd12.img  && dd of=fdfd12.img  if=bs/freedos-1.2-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd12.img  memtest86+.multiboot.bin ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd13.img  && truncate -s 1440K fdfd13.img  && dd of=fdfd13.img  if=bs/freedos-1.3-fixed-fat12-bs.bin          bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd13.img  memtest86+.multiboot.bin ::KERNEL.SYS || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB.
cp -a fd1440k.bin fdsv249.img && truncate -s 1440K fdsv249.img && dd of=fdsv249.img if=bs/svardos-20240915-fixed-fat12-bs.bin     bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdsv249.img memtest86+.multiboot.bin ::KERNEL.SYS || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB.
cp -a fd1440k.bin fdg4d4.img  && truncate -s 1440K fdg4d4.img  && dd of=fdg4d4.img  if=bs/grub4dos-0.4.4-fixed-fat12-fat16-bs.bin bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdg4d4.img  memtest86+.multiboot.bin ::GRLDR      || exit "$?"  # -fixed: Drive number remains in DL.
cp -a fd1440k.bin fdg4d6a.img && truncate -s 1440K fdg4d6a.img && dd of=fdg4d6a.img if=bs/grub4dos-0.4.6a-fat12-fat16-bs.bin      bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdg4d6a.img memtest86+.multiboot.bin ::GRLDR      || exit "$?"
truncate -s 1440K fd1440k.bin

rm -f liigboot.zip
cp -a liigboot.zip.orig liigboot.zip
mcopy -bsomp -i liigboot.zip memtest86+.multiboot.bin ::M.MB
mcopy -bsomp -i liigboot.zip memtest86+.kernel.bin ::M.K
mcopy -bsomp -i liigboot.zip syslinux.cfg ::SYSLINUX.CFG
mcopy -bsomp -i liigboot.zip menu.lst ::MENU.LST

: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -kernel memtest86+.kernel.bin
: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -drive file=liigboot.zip,format=raw -boot c

: "$0" OK.
