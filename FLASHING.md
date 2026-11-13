# Flashing artefacts

English | [中文](FLASHING.zh.md)

Everything below was measured on the board with fastboot serial `b53c187d` (codename `warsaw`,
SM8750). Term definitions are in [README.md](README.md) §1; the attribution list is §10 of the same file.

## 1. What one round writes on the device

| | |
| --- | --- |
| Written in most rounds | `misc` — one 2,048-byte BCB holding the `boot-fastboot` command |
| Written once | `userdata` — 2026-11-07, after the whole partition had been dumped to 9,382,658,048 bytes as a backup |
| Never written | `boot`, `vendor_boot`, `vbmeta`, `dtbo` and the rest of the A/B set |
| How XNU starts | `fastboot boot <bootimg>`. The image is downloaded to RAM and started; nothing is stored on the flash |
| Back to stock Android | `fastboot erase misc`, then `fastboot reboot` |

Because the BCB carries `boot-fastboot`, the first reset after a round lands in fastboot instead of
Android. Clearing `misc` removes that effect, and since slot A was announced before every round with
`fastboot --set-active=a`, Android boots normally afterwards.

## 2. Preflight, before every fire

```sh
fastboot -s b53c187d getvar is-userspace     # must answer: no
fastboot -s b53c187d getvar product          # must answer: warsaw
fastboot -s b53c187d getvar max-download-size # compare against 136,474,624 bytes
```

`is-userspace: no` means the vendor ABL fastboot is answering, and that is the only implementation
here that accepts `fastboot boot`. If it answers `yes`, the device is in userspace `fastbootd`;
`fastboot reboot bootloader` moves it back to the ABL, then check again.

Two host-side traps that cost us rounds: an Android phone is usually attached to `adb` on the same
host, so every command needs `-s`, and `cd dir && nohup ./build.sh > log 2>&1 &` puts the whole
`cd &&` list in the background, so the `tail` that follows runs in the home directory and reports a
log file that does not exist while the build is running.

## 3. Fire once

```sh
fastboot -s b53c187d flash misc misc-bcb-fb.img
fastboot -s b53c187d boot boot-m5c-diag250.img
```

`scripts/chain250.sh` and `scripts/chain251.sh` are the complete per-round scripts: preflight, BCB
write, one fire, then timed photo capture of the report screen. They are records, not a runnable kit:
they reference our own absolute paths and a phone camera on a tripod.

## 4. Timing, measured over three rounds

| Quantity | Value |
| --- | --- |
| `fired` → readout | 50 min 39 s / 48 min 39 s / 52 min 49 s |
| Report screen drawn | between `el` 2704 and 2766 |
| Board returns to fastboot | between `el` 3040 and 3050 |
| Park before the return | 300 s, set by the panic-screen code bands in the kernel source, not by board configuration |

The 300-second park is what makes a readout possible at all, because the report screen stays up until
the board hands itself back to fastboot.

## 5. How the image is built

`scripts/build-diag250.sh` is verbatim: three upstream invocations, `./unixnu kernel`,
`./unixnu payload --data-ramdisk <seed image>`, `./unixnu bootimg --uefi <uefi-dada> --dtb <live dtb>`.
Two changed `.c` files rebuild kernel + payload + bootimg in 63 s with zero warnings.

Two facts that change how you assert things:

- The kernel build is **not** byte-reproducible at our pin. Three rebuilds from unchanged source
  produced three different hashes, so "the kernel did not change" is argued from format-string
  literals inside `kernel.macho` plus source `mtime`, never from a hash.
- `UNIXNU_UNIQUE_CHIP_ID=0x0123556789abcdef` in that script is our own placeholder value, not the
  device's real chip ID.

## 6. The Data seed, and the Linux-only recipe

The image `data-seed250-gpt70.img` (74,481,664 bytes, sha256 `3571667e…cbce8c4`) is a GPT-wrapped
70 MiB APFS container holding the initial `private/var` directory skeleton from the IPSW:
176 directories, 1 symlink, 0 regular files; `tmp` and `run` mode 1777, `mobile` owned by 501:501.

How it was produced without a Mac:

1. `mkapfs` (from `linux-apfs/apfsprogs`) creates the container. It does not create files, so
   `truncate` the target first.
2. `mkapfs` writes the container superblock at container + 0x20, because it emits a 32-byte checkpoint
   header in front of every 8 KiB group. **Do not add a 32-byte rotation on top of that**: a rotated
   image fails `apfsck` and does not mount.
3. To fill it with real directory entries, `apfs-dkms` 0.3.18 was unpacked with `dpkg-deb -x`, built
   out of tree and `insmod`-ed. The mount **must** pass the option `readwrite`; without it the driver
   mounts read-only and prints `experimental writes disabled to avoid data loss`.
4. `apfsck` from `apfsprogs` is the off-board judge: it must return 0 at all three stages before the
   image is worth a board round.
5. The payload stage **refuses** rather than warns when staged content exceeds `size_mib × 0.95`
   (`scripts/unixnu/payload.py`). A 72 MiB container measured 122 MiB staged and was rejected, so the
   70 MiB size is a consequence of that ceiling, not a choice.
6. `scripts/unixnu/runtime.py` **rewrites** `CONFIG_XNU_OWNER_DATA_VOLUME_UUID` instead of erroring
   when the seed's volume UUID differs from the compiled value. The kernel is built before the payload
   reads the seed, so a payload-only seed swap must pin the seed's volume UUID to the value already
   compiled into the kernel: `7F00D031-C00B-4368-A3FF-D4788A1323D6`.

The consequence worth stealing: XNU's own APFS driver mounted this container — last written by Linux
`apfs-dkms` 0.3.18 — read-write on the board. `hdiutil` is only required to run the upstream
`--init-data` generator, not to build a Data seed at all.

`scripts/apfs_volume_uuid.py` reads APFS volume superblocks out of an image window and prints their
UUIDs, which is how the pin in point 6 is checked before a build.

## 7. What is published where

| Artefact | Bytes | Where |
| --- | --- | --- |
| `data-seed250-gpt70.img.gz` | 87,005 | Release asset of tag `v250` on this repository; `gunzip` gives the 74,481,664-byte `data-seed250-gpt70.img` |
| `misc-bcb-fb.img` | 2,048 | `flash/misc-bcb-fb.img` in this repository |
| `kernel.macho` | 51,417,088 | hash only (in `manifest-sha256.txt`) |
| `boot-m5c-diag250.img`, `boot-m5c-diag251.img` | 136,474,624 each | hash only |
| 234 intermediate boot images from rounds up to 250 | 29 GB total | not published |
| `userdata-root.img` (the backup) | 9,382,658,048 | not published |
| `userdata-m5b.simg` (the image flashed on 2026-11-07) | 3,187,697,912 | hash only |

A single boot image is 136,474,624 bytes, above the 100 MB per-file limit that a git host enforces,
and the 234 intermediate images total 29 GB, so boot images are published as a hash plus the build
command above rather than as binaries.

Two facts about the published seed:

- The asset is gzipped because the upload widget refuses the `.img` suffix: it answers `We don't
  support that file type.` and lists the accepted suffixes, among them `gz` and `zip`, with no
  `.img`. `gunzip` restores the image byte for byte.
- `gzip -9` turns 74,481,664 bytes into 87,005 bytes, 0.12 % of the image, because the container is
  almost entirely zero-filled. That ratio is a property of the seed, not of the compression settings.

The tag `v250` is an annotated tag on commit `c51d1b1`, pushed with `git push origin v250` before the
release was published, because the form's tag picker had to be handed an existing ref.

## 8. One escape hatch we did not need yet

The same-SoC peer `lenzhang/UniXNU-xiaomipad8pro` uses `size_mib = 160` with a packed data ramdisk and
`--ramdisk none` on the boot image, then delivers the payload with `fastboot stage` plus
`oem ramdisk`, because the vendor ABL refuses a 160 MiB ramdownload. Our boot image currently carries
its ramdisk inside the 130 MB download. That is the exit to take if the Data seed has to grow past
what `size_mib × 0.95` allows. Attribution: `lenzhang/UniXNU-xiaomipad8pro`, README §10.
