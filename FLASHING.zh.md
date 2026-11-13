# 刷机资料

[English](FLASHING.md) | 中文

下面每一条数字都是在 fastboot 序列号 `b53c187d`（代号 `warsaw`，SM8750）这块板子上实测得到的。
名词定义在 [README.zh.md](README.zh.md) 第 1 节；借鉴来源清单在同一份文件的第 10 节。

## 1. 一轮在设备上真正写了什么

| | |
| --- | --- |
| 多数轮次写入 | `misc` — 一个 2,048 字节的 BCB，内容是 `boot-fastboot` 这条命令 |
| 写入过 1 次 | `userdata` — 2026-11-07，动手前先把整块分区 dump 成 9,382,658,048 字节当备份 |
| 从没写过 | `boot`、`vendor_boot`、`vbmeta`、`dtbo` 以及其余 A/B 分区 |
| XNU 怎么起 | `fastboot boot <bootimg>`。镜像下载到 RAM 里直接执行，闪存上不落任何东西 |
| 回到原生安卓 | `fastboot erase misc`，然后 `fastboot reboot` |

BCB 里带的是 `boot-fastboot`，所以一轮结束后第一次复位会落进 fastboot 而不是安卓。清掉 `misc`
就取消这个效果；又因为每轮发火前都用 `fastboot --set-active=a` 把 A 槽设成活动槽，之后安卓正常启动。

## 2. 每次发火前的预检

```sh
fastboot -s b53c187d getvar is-userspace     # 必须是：no
fastboot -s b53c187d getvar product          # 必须是：warsaw
fastboot -s b53c187d getvar max-download-size # 跟 136,474,624 字节比一下
```

`is-userspace: no` 表示应答的是厂商 ABL 里的 fastboot，而本机只有它能接受 `fastboot boot`。
如果答 `yes`，说明设备在用户态 `fastbootd` 里；`fastboot reboot bootloader` 把它退回 ABL，然后再查一遍。

两个主机侧的坑，我们都因此白烧过轮次：同一台主机上安卓手机一般还挂在 `adb` 上，所以每条命令都得带
`-s`；`cd dir && nohup ./build.sh > log 2>&1 &` 会把整个 `cd &&` 列表一起丢进后台，紧跟其后的 `tail`
在家目录里跑，于是报「日志文件不存在」，而构建其实活着。

## 3. 发火一次

```sh
fastboot -s b53c187d flash misc misc-bcb-fb.img
fastboot -s b53c187d boot boot-m5c-diag250.img
```

`scripts/chain250.sh` 和 `scripts/chain251.sh` 是完整的单轮脚本：预检、写 BCB、发火一次，
然后按时间点给报表屏拍照。它们是存档记录，不是一套能直接跑的套件：里面写死了我们自己的绝对路径，
以及一台架在三脚架上的手机摄像头。

## 4. 三轮实测的时间

| 量 | 值 |
| --- | --- |
| `fired` → 读到读数 | 50 分 39 秒 / 48 分 39 秒 / 52 分 49 秒 |
| 报表屏画上屏 | `el` 2704 到 2766 之间 |
| 板子回到 fastboot | `el` 3040 到 3050 之间 |
| 回去之前的停留 | 300 秒，由内核源码里宕机报表的代码段决定，不由板级配置决定 |

那 300 秒停留是读数能拿到的前提：报表屏一直留着，直到板子自己交还给 fastboot。

## 5. 镜像怎么构建

`scripts/build-diag250.sh` 逐字收录，里面就是三条上游调用：`./unixnu kernel`、
`./unixnu payload --data-ramdisk <种子镜像>`、`./unixnu bootimg --uefi <uefi-dada> --dtb <活设备树>`。
改两个 `.c` 文件，内核 + payload + bootimg 共 63 秒，零 warning。

两条会改变你论证方式的事实：

- 我们那个 pin 上，内核构建**不是**字节可复现的。源码没变，重编三次得到三个不同哈希，
  所以「内核没变」这句话只能靠 `kernel.macho` 里的格式串字面量加源码 `mtime` 来主张，不能靠哈希。
- 脚本里的 `UNIXNU_UNIQUE_CHIP_ID=0x0123556789abcdef` 是我们自己填的占位值，不是设备真实的 chip ID。

## 6. Data 种子，以及纯 Linux 的做法

镜像 `data-seed250-gpt70.img`（74,481,664 字节，sha256 `3571667e…cbce8c4`）是一个 GPT 包起来的
70 MiB APFS 容器，里面是 IPSW 里那份 `private/var` 初始目录骨架：176 个目录、1 个符号链接、
0 个普通文件；`tmp` 和 `run` 是 1777，`mobile` 归属 501:501。

没有 Mac 的情况下怎么造出来的：

1. `mkapfs`（来自 `linux-apfs/apfsprogs`）建容器。它不建文件，所以先 `truncate` 出目标文件。
2. `mkapfs` 把容器超块写在 container + 0x20，因为它在每个 8 KiB 组前面都放了一个 32 字节的
   checkpoint 头。**别再在上面叠一次 32 字节旋转**：旋转过的镜像 `apfsck` 过不去，也挂不上。
3. 要往里写真目录项，得把 `apfs-dkms` 0.3.18 用 `dpkg-deb -x` 解开、树外编译、`insmod` 进去。
   挂载**必须**带选项 `readwrite`；不带的话驱动只读挂载并打
   `experimental writes disabled to avoid data loss`。
4. `apfsprogs` 的 `apfsck` 是板外裁判：三段都必须返回 0，这个镜像才值得花一块板。
5. payload 阶段在灌入内容超过 `size_mib × 0.95` 时是**直接拒**、不是警告
   （`scripts/unixnu/payload.py`）。72 MiB 容器实测灌入 122 MiB 被拒，所以 70 MiB 这个尺寸是被
   这条上限逼出来的，不是选的。
6. `scripts/unixnu/runtime.py` 在种子的 volume UUID 与编进去的值不一致时**改写**
   `CONFIG_XNU_OWNER_DATA_VOLUME_UUID`，不报错。内核在 payload 读种子之前就已经编完了，
   所以只换 payload 阶段的种子时，必须把种子的 volume UUID 钉成内核里已有的那个值：
   `7F00D031-C00B-4368-A3FF-D4788A1323D6`。

值得抄走的结论：XNU 自己的 APFS 驱动在板子上以读写方式挂载了这个容器 —— 而它最后是被 Linux
`apfs-dkms` 0.3.18 写的。`hdiutil` 只是跑上游 `--init-data` 生成器时需要，造 Data 种子本身不需要。

`scripts/apfs_volume_uuid.py` 从镜像窗口里读出 APFS 卷超块并打印它们的 UUID，
构建前就靠它核对第 6 条里那个钉值。

## 7. 什么发在哪里

| 资料 | 字节 | 位置 |
| --- | --- | --- |
| `data-seed250-gpt70.img` | 74,481,664 | 本仓库的 Release 资产 |
| `misc-bcb-fb.img` | 2,048 | 本仓库 `flash/misc-bcb-fb.img` |
| `kernel.macho` | 51,417,088 | 只给哈希（在 `manifest-sha256.txt` 里） |
| `boot-m5c-diag250.img`、`boot-m5c-diag251.img` | 各 136,474,624 | 只给哈希 |
| 前 250 轮的 234 个中间 bootimg | 共 29 GB | 不发布 |
| `userdata-root.img`（那份备份） | 9,382,658,048 | 不发布 |
| `userdata-m5b.simg`（2026-11-07 刷进去的那个） | 3,187,697,912 | 只给哈希 |

单个 bootimg 是 136,474,624 字节，超过 git 托管方单文件 100 MB 限制；234 个中间镜像合计 29 GB。
所以 bootimg 只发布哈希加上面那条构建命令，不发二进制。

## 8. 一个我们还没用上的出口

同 SoC 的 peer `lenzhang/UniXNU-xiaomipad8pro` 用 `size_mib = 160` 加打包的 data ramdisk，
bootimg 上给 `--ramdisk none`，然后用 `fastboot stage` 加 `oem ramdisk` 投递 payload，
因为厂商 ABL 拒收 160 MiB 的 ramdownload。我们现在的 bootimg 把 ramdisk 装在这个 130 MB 下载里。
当 Data 种子必须长到超过 `size_mib × 0.95` 时，走的就是这条路。
来源：`lenzhang/UniXNU-xiaomipad8pro`，见 README 第 10 节。
