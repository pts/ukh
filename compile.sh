#! /bin/sh --
set -ex
test "$0" = "${0%/*}" && cd "${0%/*}"

upxbc="$HOME/prg/upxbc/upxbc"  # https://github.com/pts/upxbc

if ! test -f memtest86+-5.01-dist-lzma.bin; then
  dd if=memtest86+-5.01-dist.bin bs=512 skip=5 of=upxbc1.tmp
  "$upxbc" --upx=upx.pts --flat32 --lzma -f -o upxbc2.tmp upxbc1.tmp
  (dd if=/dev/zero bs=512 count=5 && cat upxbc2.tmp) >memtest86+-5.01-dist-lzma.bin || exit "$?"
fi

# Just for size comparison with memtest86+-5.01-dist-lzma.bin. This one is 1083 bytes larger LZMA-cumpressed and ~32 KiB larger uncompressed.
if ! test -f memtest86+-5.01-lzma.bin; then
  dd if=memtest86+-5.01.bin bs=512 skip=5 of=upxbc1.tmp  # !! -- skip=512 etc.
  "$upxbc" --upx=upx.pts --flat32 --lzma -f -o upxbc2.tmp upxbc1.tmp
  (dd if=/dev/zero bs=512 count=5 && cat upxbc2.tmp) >memtest86+-5.01-lzma.bin || exit "$?"
fi

if ! test -f memtest86+-5.01-dist-nrv.bin; then
  dd if=memtest86+-5.01-dist.bin bs=512 skip=5 of=upxbc1.tmp
  "$upxbc" --upx=upx.pts --flat32 --ultra-brute --no-lzma -f -o upxbc2.tmp upxbc1.tmp
  (dd if=/dev/zero bs=512 count=5 && cat upxbc2.tmp) >memtest86+-5.01-dist-nrv.bin || exit "$?"
fi

#nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'ubuntu-16.04-grub-0.97-29ubuntu68-stage2'" -DGRUB1 -o grub1.multiboot.bin grub1.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'stage2'" -DGRUB1 -o grub1.multiboot.bin grub1.nasm   # !!!
"$upxbc" --upx=upx.pts --flat32 --lzma --prefix=0x470 -f -o grub1.lzma.badsize.bin grub1.multiboot.bin  # This will boot, but the UKH boot code would memmove(...) unnecessarily many bytes.
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'grub1.lzma.badsize.bin'" -DUKH_PAYLOAD_FILE_SKIP=0x400 -DUKH_VERSION_STRING="'grub1-0.97-ubuntu'" -DUKH_MULTIBOOT -o grub1.lzma.bin ukh.nasm
#"$upxbc" --upx=upx.pts --flat32 --ultra-brute --no-lzma --prefix=0x470 -f -o grub1.nrv.bin grub1.multiboot.bin  # Larger than with --lzma by <900 bytes. Also the memmove(...) is unnecessarily large.
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DSTAGE2_IN="'grub4dos.uncompressed.bs'" -DGRUB4DOS0_4_4 -o grub4dos4.multiboot.bin grub1.nasm
"$upxbc" --upx=upx.pts --flat32 --lzma --prefix=0x470 -f -o grub4dos4.lzma.badsize.bin grub4dos4.multiboot.bin  # This will boot, but the UKH boot code would memmove(...) unnecessarily many bytes.
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'grub4dos4.lzma.badsize.bin'" -DUKH_PAYLOAD_FILE_SKIP=0x400 -DUKH_VERSION_STRING="'grub4dos-0.4.4pts'" -DUKH_MULTIBOOT -o grub4dos4.lzma.bin ukh.nasm

nasm-0.98.39 -O0 -w+orphan-labels -f bin -DLDLINUX_RAW_IN="'ldlinux.raw'" -o syslinux4.multiboot.bin syslinux4.nasm

# Tested and works with memtest86+-5.01*.bin and memtest85+5.31b*.bin.
nasm-0.98.39 -O0 -w+orphan-labels -f bin -o testk1.multiboot.bin testk1.nasm  # Includes ukh.nasm.
 nasm-0.98.39 -O0 -w+orphan-labels -f bin -o testk16.multiboot.bin testk16.nasm  # Includes ukh.nasm.
# cmp testk1.multiboot.bin.good testk1.multiboot.bin
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'memtest86+-5.01-dist.bin'"      -DUKH_PAYLOAD_FILE_SKIP=0xa00 -DUKH_VERSION_STRING="'memtest86+-5.01'"        -DUKH_NO_MULTIBOOT -o memtest86+.kernel.bin ukh.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'memtest86+-5.01-dist.bin'"      -DUKH_PAYLOAD_FILE_SKIP=0xa00 -DUKH_VERSION_STRING="'memtest86+-5.01-mb'"     -DUKH_MULTIBOOT    -o memtest86+.multiboot.bin ukh.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'memtest86+-5.01-dist-lzma.bin'" -DUKH_PAYLOAD_FILE_SKIP=0xa00 -DUKH_VERSION_STRING="'memtest86+-5.01-lzma'"   -DUKH_NO_MULTIBOOT -o memtest86+.lzma.kernel.bin ukh.nasm
nasm-0.98.39 -O0 -w+orphan-labels -f bin -DUKH_PAYLOAD_32_FILE="'memtest86+-5.01-dist-nrv.bin'"  -DUKH_PAYLOAD_FILE_SKIP=0xa00 -DUKH_VERSION_STRING="'memtest86+-5.01-nrv-mb'" -DUKH_MULTIBOOT    -o memtest86+.nrv.kernel.bin ukh.nasm
ls -ld memtest86+.kernel.bin memtest86+.lzma.kernel.bin

gunzip -cd <fd1440k.bin.gz >fd1440k.bin
cp -a fd1440k.bin fddr703.img && truncate -s 1440K fddr703.img && dd of=fddr703.img if=bs/dr-dos-7.03-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fddr703.img memtest86+.multiboot.bin   ::IBMBIO.COM || exit "$?"  # Does not work, allows only <=29 KiB kernel.
cp -a fd1440k.bin fdedr8.img  && truncate -s 1440K fdedr8.img  && dd of=fdedr8.img  if=bs/edr-dos-7.01.08-fat12-bs.bin            bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdedr8.img  memtest86+.nrv.kernel.bin  ::DRBIO.SYS  || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB. !! The compressed kernel is small enough without -fixed.
cp -a fd1440k.bin fdfd10.img  && truncate -s 1440K fdfd10.img  && dd of=fdfd10.img  if=bs/freedos-1.2-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd10.img  memtest86+.nrv.kernel.bin  ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd11.img  && truncate -s 1440K fdfd11.img  && dd of=fdfd11.img  if=bs/freedos-1.3-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd11.img  memtest86+.nrv.kernel.bin  ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd12.img  && truncate -s 1440K fdfd12.img  && dd of=fdfd12.img  if=bs/freedos-1.2-fat12-bs.bin                bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd12.img  memtest86+.nrv.kernel.bin  ::KERNEL.SYS || exit "$?"
cp -a fd1440k.bin fdfd13.img  && truncate -s 1440K fdfd13.img  && dd of=fdfd13.img  if=bs/freedos-1.3-fixed-fat12-bs.bin          bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdfd13.img  memtest86+.lzma.kernel.bin ::KERNEL.SYS || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB. !! The compressed kernel is small enough without -fixed.
cp -a fd1440k.bin fdsv249.img && truncate -s 1440K fdsv249.img && dd of=fdsv249.img if=bs/svardos-20240915-fixed-fat12-bs.bin     bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdsv249.img memtest86+.nrv.kernel.bin  ::KERNEL.SYS || exit "$?"  # -fixed: Allows 198.5 KiB kernel instead of just 134.5 KiB. !! The compressed kernel is small enough without -fixed.
cp -a fd1440k.bin fdg4d4.img  && truncate -s 1440K fdg4d4.img  && dd of=fdg4d4.img  if=bs/grub4dos-0.4.4-fixed-fat12-fat16-bs.bin bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdg4d4.img  memtest86+.multiboot.bin   ::GRLDR      || exit "$?"  # -fixed: Drive number remains in DL.
cp -a fd1440k.bin fdg4d6a.img && truncate -s 1440K fdg4d6a.img && dd of=fdg4d6a.img if=bs/grub4dos-0.4.6a-fat12-fat16-bs.bin      bs=2 skip=31 seek=31 count=225 conv=notrunc && mcopy -bsomp -i fdg4d6a.img memtest86+.multiboot.bin   ::GRLDR      || exit "$?"
mcopy -bsomp -i fdg4d4.img testk1.multiboot.bin ::R.K
truncate -s 1440K fd1440k.bin

rm -f liigboot.zip
cp -a liigboot.zip.orig liigboot.zip
mdel -i liigboot.zip ::NETBOOTX.K ::GRUB4DOS.BS
mcopy -bsomp -i liigboot.zip testk1.multiboot.bin ::R.K
mcopy -bsomp -i liigboot.zip testk16.multiboot.bin ::R16.K
mcopy -bsomp -i liigboot.zip memtest86+.nrv.kernel.bin ::M.MB  # Also multiboot.
mcopy -bsomp -i liigboot.zip memtest86+.kernel.bin ::M.K  # One kernel command-line flag: btrace
mcopy -bsomp -i liigboot.zip memtest86+.lzma.kernel.bin ::ML.K  # Not multiboot, just for testing.
mcopy -bsomp -i liigboot.zip grub1.lzma.bin ::GRUB1.MB
#mcopy -bsomp -i liigboot.zip grub1.multiboot.bin ::GRUB1.MB  # !!!
mcopy -bsomp -i liigboot.zip grub4dos4.lzma.bin ::G4D4.MB
mcopy -bsomp -i liigboot.zip syslinux4.multiboot.bin ::SYSL4.MB
mcopy -bsomp -i liigboot.zip syslinux.cfg ::SYSLINUX.CFG
mcopy -bsomp -i liigboot.zip menu.lst ::MENU.LST

# Please note that memtest86+-5.01 needs least 4 MiB of memory in QEMU 2.11.1 (QEMU fails with 3 MiB), hence the `-m 4'.
: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -kernel memtest86+.kernel.bin
: qemu-system-i386 -M pc-1.0 -m 4 -nodefaults -vga cirrus -drive file=liigboot.zip,format=raw -boot c

: "$0" OK.
