# GeForce Linux P2P

独立复现 GeForce 的 **ReBAR／BAR1 扩容 → PCIe 资源窗口 → patched 驱动 → CUDA P2P → 完整性／带宽／延迟验收**。不需要安装 Tensor Unlock。BAR1 检查可单卡运行；GPU 间 P2P **至少两卡**。

**唯一严格验收基线**：Ubuntu 24.04.5 · kernel 6.8.0-149 · patched NVIDIA 615.71.09 · 4×RTX 3090。

| 项目 | Stage 8 实测 |
|---|---|
| BAR1 | 4×32 GiB |
| P2P | 6/6 卡对、12/12 方向 |
| 完整性 | 25,265.4 GiB = 24.67 TiB，零错误 |
| 带宽 | 单向约 26 GB/s，双向 51–52 GB/s |
| 启动恢复 | warm reboot PASS；冷启动未测 |

### 开始

```bash
bash scripts/fetch-upstream.sh bar1 driver
bash scripts/inspect.sh
sudo upstream/bar1/scripts/geforce-bar1-resize check --vram 24G
```

安装会修改启动和驱动配置，请按 [安装步骤](docs/install.md) 逐步执行检查、dry-run、安装与人工重启。本仓库不声称存在通用一键安装器。

### 验证

```bash
bash upstream/driver/contrib/integrity/build.sh
upstream/driver/contrib/integrity/p2p-integrity --list
# 下列两个地址请换成你自己的卡：
upstream/driver/contrib/integrity/p2p-integrity --pair 0000:21:00.0 0000:22:00.0 --max-mib 4096 --repeat 3
```

[完整验收与延迟](docs/validation.md) · [启动／资源窗口](docs/architecture.md) · [回滚](docs/rollback.md) · [实测](reports/stage8.md) · [适用范围](docs/compatibility.md) · [上游／许可证](THIRD_PARTY.md)

**P2P 不会把四张卡合并为统一 96 GB 显存。** 四卡满载与六对并发吞吐未测；每对带宽不能直接相加。

English: standalone BAR1 and PCIe P2P reproduction; peer testing requires at least two GPUs. Only the baseline above was accepted here.
