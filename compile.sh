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
rm -f liigboot.zip
cp -a liigboot.zip.orig liigboot.zip
mcopy -bsomp -i liigboot.zip memtest86+.multiboot.bin ::M.MB
mcopy -bsomp -i liigboot.zip memtest86+.kernel.bin ::M.K
mcopy -bsomp -i liigboot.zip syslinux.cfg ::SYSLINUX.CFG
mcopy -bsomp -i liigboot.zip menu.lst ::MENU.LST

: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -kernel memtest86+.kernel.bin
: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -drive file=liigboot.zip,format=raw -boot c

: "$0" OK.
