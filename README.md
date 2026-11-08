# TFS-Android  v1.11.0-sh

把 **Tiny Fastboot Script v1.10.6 (Windows, by AlphaEva)** 的刷机流程搬成手机端 shell。
原版是 `flash.bat` + `tools/include/*.cmd` 的 Windows 批处理；本版用 **aarch64 原生 fastboot/adb**
+ 纯 POSIX sh 重写同一套逻辑，可在 **MT 管理器扩展包**、Termux、root 终端里直接执行。

---

## 1. 目录

```
/sdcard/TFS_Android/
├── tfs.sh          主脚本（菜单 + XML 刷写引擎 + 日志）
├── deploy.sh       一次性部署：把 bin/lib/tfs.sh 装到 /data/local/tmp/tfs
├── run.sh          部署后生成，MT 扩展包入口（su 提权后调用主脚本）
├── bin/fastboot    android-tools 37.0.0p1 aarch64
├── bin/adb         同上（adb 1.0.41 / 37.0.0p1）
├── lib/            fastboot 依赖：libfmt.so libc++_shared.so libz.so.1
│                   adb 依赖：libabsl_*.so libprotobuf.so libbrotli*.so libzstd.so.1 liblz4.so
├── docs/           内置文档（cid / faq / changelog）
├── rom/            默认 ROM 目录
└── logs/           每次运行一份 tfs_*.log（不可写时降级到 /sdcard/TFS_Android/logs）
```

`/sdcard` 是 fuse 文件系统，`chmod` 无效 → **二进制必须复制到 /data/local/tmp 才能执行**，
这就是 `deploy.sh` 存在的原因；主脚本启动时也会自己检测并自举。

---

## 2. 先部署（只要一次）

```sh
su -c "sh /sdcard/TFS_Android/deploy.sh"
```

看到 `fastboot: fastboot version 37.0.0p1-android-tools` 就算好了。

---

## 3. MT 管理器扩展包配置

1. MT 管理器 → 侧滑菜单 → **设置** → **扩展包**（不同版本叫「自定义命令」/「脚本」）→ 新建。
2. 命令填：

```sh
sh /sdcard/TFS_Android/run.sh
```

3. 名称填 `TFS刷机`，勾选「需要 root / 提权」（没有这项也没关系，脚本自己 `su` 重入）。
4. 用的时候：把 ROM 解压到某个目录（里面有 `flashfile.xml` / `servicefile.xml`）→
   长按那个**目录** → 扩展包 → TFS刷机。

> 想固定 ROM 目录，可以在命令里加环境变量：
> `TFS_ROMDIR=/sdcard/rom/avr sh /sdcard/TFS_Android/run.sh`
> 脚本启动后菜单里的默认目录就是这个。

---

## 4. 菜单

屏幕上每项占两行：第一行是功能名，第二行是 `[键]` 加参数说明，输入键加回车执行。


| 键 | 功能 |
|----|------|
| 1 | 一键刷整包（自动解析 flashfile/servicefile.xml） |
| 2 | 只刷 AP（跳过 BP/BL） |
| 3 | 只刷 BL（bootloader 部分） |
| 4 | 刷单个镜像（自动推断分区，magisk_patched→boot，twrp/recovery→recovery） |
| 5 | 刷目录内全部 img（跳过 super.img 和 *_b.img） |
| 6 | 刷 super（整包 super.img 或 super.img_sparsechunk.* 按序号） |
| 7 | 擦除 userdata + metadata（恢复出厂） |
| 8 | 擦除 modemst1/modemst2/fsg/frp（基带缓存） |
| 9 | 切 A/B 槽（`set_active`） |
| i | 设备信息：product/variant/serialno/current-slot/unlock 状态，可导出 getvar all |
| s | 重启：bootloader / system / recovery / fb_mode_clear |
| u | 解锁：get_unlock_data / oem unlock / flashing unlock |
| d | ADB：设备列表 / 重启到 bootloader / shell / push / pull / 杀 server |
| b | 查内置文档 faq（fastboot 报错分析） |
| c | 查内置文档 cid（Motorola CID 说明） |
| f | 环境自检（二进制、库、uid、设备数） |
| c | 配置：跳过分区表、保留数据、危险确认、干跑 |
| 0 | 退出 |

---

## 5. 非交互（脚本里调、批处理、自动化）

```sh
sh /data/local/tmp/tfs/tfs.sh check                  # 环境自检
sh /data/local/tmp/tfs/tfs.sh devices                # fastboot devices
sh /data/local/tmp/tfs/tfs.sh info                   # 设备信息
sh /data/local/tmp/tfs/tfs.sh flash <目录|xml> [ALL|AP|BP|BL]
sh /data/local/tmp/tfs/tfs.sh ap <目录>              # 只刷 AP
sh /data/local/tmp/tfs/tfs.sh bl <目录>              # 只刷 BL
sh /data/local/tmp/tfs/tfs.sh img <文件> [分区]      # 单文件
sh /data/local/tmp/tfs/tfs.sh super <目录>           # super 稀疏分片
sh /data/local/tmp/tfs/tfs.sh erase data|modem
sh /data/local/tmp/tfs/tfs.sh slot a|b
sh /data/local/tmp/tfs/tfs.sh reboot sys|bl|rec|edl|fbcl
sh /data/local/tmp/tfs/tfs.sh unlock data|ul|fl
sh /data/local/tmp/tfs/tfs.sh adb list|bl|rc|sh|push|pull|kill
sh /data/local/tmp/tfs/tfs.sh doc                      # 列出内置文档
sh /data/local/tmp/tfs/tfs.sh doc cid|faq|changelog   # 直接看某篇
```

全局开关：`--dry`（干跑只打印）、`--factory`（不保留数据，会执行 erase）、
`--yes`（跳过所有危险确认）、`--serial <序列号>`（多设备时指定）。

例：先干跑看一眼要动哪些分区，再真刷

```sh
sh /data/local/tmp/tfs/tfs.sh --dry --factory flash /sdcard/rom/avr ALL
sh /data/local/tmp/tfs/tfs.sh --factory flash /sdcard/rom/avr ALL
```

把某个文件/目录直接当参数丢进去也行（MT 扩展包就是这么用的）：

```sh
sh /data/local/tmp/tfs/tfs.sh /sdcard/rom/avr        # 目录 → 找 xml 全刷
sh /data/local/tmp/tfs/tfs.sh /sdcard/boot.img       # img → 推断分区刷
```

---

## 6. 安全默认值（对齐 TFS 的「保留数据」逻辑）

- **KEEP_DATA=1**：XML 里的 `erase` 一律跳过；要清数据用 `--factory` 或菜单 [7]。
- **跳过分区表**：`cid carrier cdt utags devinfo frp persist modemst1 modemst2 fsg logo_a logo_b`
- 危险操作（erase userdata/metadata、unlock）非交互环境下**默认不执行**，必须 `--yes`。
- 每次运行写日志到 `logs/tfs_*.log`，fastboot 原始输出也在里面。

改配置：菜单 [c]，或直接编辑 `/data/local/tmp/tfs/config.conf`。

---

## 7. 与原版 TFS 的差异

| 原版（Windows） | 本版（Android sh） |
|---|---|
| `tools/bin/*.exe`（grep/awk/sed/tr/paste/sort） | 用系统 toybox/mksh 内建 + 纯 sh 字符串处理，不额外带 GNU 工具 |
| `xml2batflash.bat` 转批处理再执行 | 直接流式解析 XML，边读边刷，不落地中间 bat |
| 按 `-n` 排序执行 | 保持 XML 原始顺序执行（与 TFS sort -n 等效） |
| MTK/QCOM/SLSI 分类刷 BL/BP | 用 XML 的 `interface="AP/BP/BL"` 字段分范围，覆盖三类平台 |
| mfastboot 多版本（26/28/34） | 单一 fastboot 37.0.0p1，`-s` 指定序列号 |
| 只能 Windows 主机 + USB | 手机当 host，需 root + OTG，目标机进 fastboot 模式 |
| 无 | 额外：`--dry` 干跑、彩色输出、日志、环境自检、adb 子菜单 |

---

## 8. 常见问题

- **`err: 未检测到 fastboot 设备`** → 目标机没进 bootloader、OTG 线是充电线、或没 root。
- **`CANNOT LINK EXECUTABLE`** → `lib/` 没复制全，重跑 `deploy.sh`。
- **adb 报 `Cannot mkdir '//.android'`** → HOME 不可写；本版已自动把 HOME 指到 `/data/local/tmp/tfs`。
- **刷 super 卡住** → 稀疏分片要按序号刷，用菜单 [6] 别手点单文件。
- **换机/换平台** → 只改 `SKIP_LIST`，XML 引擎不分平台。

---
## 9. 本地增强（相对原版 TFS 1.10.6）

| 项目 | 行为 |
|---|---|
| 内置文档 | `tfs.sh doc` 列清单，`tfs.sh doc cid\|faq\|changelog` 直读；菜单 `b`/`c`；在 `$HOME_DIR/docs`、脚本目录、`/sdcard/TFS_Android/docs` 三级查找，找不到直接报错 |
| 日志目录回退 | 优先 `$HOME_DIR/logs`，不可写→`/sdcard/TFS_Android/logs`→`${TMPDIR:-/tmp}`；写日志重定向整组包住，权限不足不刷屏 |
| 非交互返回码 | `tfs.sh <子命令>` 失败直接返回非 0，不再落到「改为环境自检」分支 |
| 路径自举 | `TFS_HOME` / `FASTBOOT_HOME` 可覆盖，一份脚本可多处部署 |
| 干跑 | 所有写操作前 `--dry` 只打印 fastboot 命令行不执行 |

改完先语法检查：
```sh
sh -n /sdcard/TFS_Android/tfs.sh && echo syntax_ok
```

---

## 仓库文件清单（可直接 clone 使用）

本仓库只放纯文本源码，二进制不进版本库（避免历史臃肿）。

```
tfs.sh                     主脚本，921 行 POSIX sh
run.sh                     入口包装（MT 管理器扩展包指向它）
deploy.sh                  部署到 /data/local/tmp/tfs 并 chmod
config.conf                跳过分区 / 保留数据 / 覆盖确认等开关
docs/cid.txt               CID 对照表
docs/faq.txt               常见问题
docs/changelog.txt         变更记录
rom/sample/flashfile.xml   刷机 XML 样例（erase all）
rom/sample/servicefile.xml 刷机 XML 样例（保数据）
```

## 拉取与运行

```sh
git clone https://github.com/Wan1337/tfs-android.git ~/tfs
cd ~/tfs
```

`bin/`（fastboot + adb）与 `lib/`（107 个 aarch64 依赖库）共 18MB，不入仓库，
从 Release 取完整包：

```sh
curl -L -o /tmp/tfs-full.tar.gz \
 https://github.com/Wan1337/tfs-android/releases/download/v1.11.0-sh/TFS-Android-aarch64-v1.11.0-sh.tar.gz
tar -xzf /tmp/tfs-full.tar.gz -C ~/tfs --skip-old-files
chmod +x ~/tfs/tfs.sh ~/tfs/bin/*
sh ~/tfs/deploy.sh
sh ~/tfs/tfs.sh
```

`chmod +x` 不能省，漏了就是 `adb: Permission denied`。

## License

MIT License，见仓库根目录 LICENSE 文件。Copyright (c) 2026 Wan1337。
