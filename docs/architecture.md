# ReBAR、窗口与动态 BAR1 P2P

1. `upstream/bar1/scripts/geforce-bar1-resize` 检查能力和 S1–S6，选择 resize-only 或受结构检查约束的 0x610 路线；通过 resource1_resize 请求目标窗口。不可跨硬件抄写寄存器。
2. 检查 PCIe parent/root port 及整个上游 MMIO 窗口、对齐和容量。当前四卡均直连各自 Root Port，内核 pci_resize_resource 扩大直接父桥窗口；Stage 8 **gbr_layout 未触发**。早期报告推断必需 gbr_layout 已被最终报告更正。PCIe switch 拓扑是另一个实验条件，不能照搬本基线。
3. 对每卡 RMForceStaticBar1=0，BAR1 至少覆盖 VRAM。大 BAR1 是当前动态路线的前提，并非能用 P2P 的充分证明。
4. patched 615.71.09 负责动态 peer 映射、拒绝不满足条件的卡对；用户态 CUDA 程序仍需启用 peer access。驱动源码及补丁实现保存在固定版 upstream/driver，构建、回退、启动选择脚本在其 contrib/。
5. CUDA 两方向 canAccessPeer 后，必须验证直接 SM load/store 与 push/pull 的数据完整性，不能只看 CUDA 返回 1。

四卡拓扑为跨 Host Bridge 的 NODE 路线，测得远端 dependent-read 约 1.19–1.28 µs，本地约 139–150 ns。高复制带宽不意味着细粒度远端读取没有代价。
