# 分阶段安装（不依赖 Unlock）

先读 [适用范围](compatibility.md)。需要 Above-4G decoding、足够的 64-bit MMIO 窗口、systemd、pciutils、当前内核 headers／编译器、匹配的 NVIDIA 615.71.09 用户态与原厂模块回退，以及该版本 GSP 固件。固件按上游要求从合法 NVIDIA 安装介质获取，不随本仓库分发。IOMMU 需满足上游 passthrough 条件；Secure Boot 关闭或模块经过可信签名。CUDA Toolkit 用于验证。

## 1. 检查与 BAR1

首页先下载固定源码。下面 BDFS 必须换成自己通过 lspci 核实的完整地址；单卡也可只做 BAR1。32G 是 BAR1 映射窗口，不会把 24 GiB 显存变为 32 GiB。

```bash
BDFS='0000:21:00.0 0000:22:00.0'
sudo upstream/bar1/scripts/geforce-bar1-resize check --vram 24G --report
sudo upstream/bar1/install.sh --dry-run --cards "$BDFS" --size 32G --driver-option on --layout off
```

逐卡核查 S1–S6、ReBAR capability、计划目标、父桥窗口和地址空间；结构检查失败或空间不足就停止，不手工复制固定 `0x610` 值。保留将修改文件的备份和原内核。通过后：

```bash
sudo upstream/bar1/install.sh --enable --cards "$BDFS" --size 32G --driver-option on --layout off
sudo geforce-bar1-resize plan
```

驱动必须从 root filesystem 在 BAR1 服务后加载，initramfs 中不能提前加载 NVIDIA；按上游 docs 检查和修正本机加载顺序，不盲目套用。人工重启后，确认每卡真实 PCI Region 1 是 32G、每卡 RMForceStaticBar1=0。

## 2. 构建 patched 驱动

```bash
(cd upstream/driver && make modules -j"$(nproc)")
(cd upstream/driver/kernel-open && sha256sum nvidia*.ko > SHA256SUMS)
export GPUS="$BDFS"
export OUT="$PWD/upstream/driver/kernel-open"
sudo env GPUS="$GPUS" OUT="$OUT" upstream/driver/contrib/p2p-install.sh --dry-run
```

检查原厂回退模块、固件、模块 hash／版本／内核和 modprobe 配置。任何拒绝条件都应处理原因；不要删除检查来强装。GA102 在固定 patched 驱动中默认走动态 BAR1 P2P。只有上一步全部通过后：

```bash
sudo env GPUS="$GPUS" OUT="$OUT" upstream/driver/contrib/p2p-install.sh --yes
```

在可本机恢复时人工重启；按 [验证](validation.md) 检查完整方向和实际数据。驱动安装脚本面向当前内核，升级后必须重编译和重验。不要将另一仓库的 gpu_unlock.targets 当作 P2P 前提。

## 3. 开机恢复

geforce-bar1-resize.service 在 NVIDIA 加载前重新施加 BAR1，per-device RMForceStaticBar1=0 写入其配置；p2p-install 的 depmod override 选择当前内核的 patched 模块。一次启动成功不能证明持久性，须人工 warm reboot 后重复检查。冷启动属于单独未测项。
