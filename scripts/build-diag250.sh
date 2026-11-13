#!/bin/bash
set -e
export PATH=/home/dong/unixnu/venv/bin:$HOME/.local/bin:/usr/bin:$PATH
export UNIXNU_TOOLCHAIN=/opt/unixnu-linux
export UNIXNU_IPSW=/home/dong/unixnu/ipsw/iPad_Pro_HFR_17.7.11_21H461.ipsw
export UNIXNU_UEFI=/home/dong/unixnu/uefi-dada
export UNIXNU_UNIQUE_CHIP_ID=0x0123556789abcdef
export UNIXNU_KERNELCACHE=/home/dong/unixnu/UniXNU/out/ipsw/21H461/kernelcache.decompressed
cd /home/dong/unixnu/UniXNU
echo "== kernel $(date -u +%H:%M:%SZ)"
./unixnu kernel -D ../UniXNU-warsaw --target DEBUG
echo "== payload $(date -u +%H:%M:%SZ)"
./unixnu payload -D ../UniXNU-warsaw --trust-cache /home/dong/unixnu/out-warsaw-trust.bin --data-ramdisk /home/dong/unixnu/data-seed250-gpt70.img
echo "== bootimg $(date -u +%H:%M:%SZ)"
./unixnu bootimg -D ../UniXNU-warsaw --uefi /home/dong/unixnu/uefi-dada --target DEBUG --dtb /home/dong/unixnu/UniXNU-warsaw/inputs/live-fdt.dtb -o /home/dong/unixnu/staging/boot-m5c-diag250.img
echo "== done $(date -u +%H:%M:%SZ)"
