# 回滚与恢复

回滚不要求安装 Unlock，也不改动其他项目的 targets。先将 GPUS 设置为自己的卡地址，OUT 设置为构建目录。原厂 615.71.09 内核模块必须仍在；任何前置检查拒绝时停止。

```bash
export GPUS='0000:21:00.0 0000:22:00.0'
export OUT="$PWD/upstream/driver/kernel-open"
sudo env GPUS="$GPUS" OUT="$OUT" upstream/driver/contrib/p2p-fallback.sh --dry-run
# 检查通过后，撤掉 patched 模块的开机选择，不请求 live 卸载：
sudo env GPUS="$GPUS" OUT="$OUT" upstream/driver/contrib/p2p-fallback.sh --yes
sudo upstream/bar1/uninstall.sh --dry-run
sudo upstream/bar1/uninstall.sh
```

顺序是 **先 driver fallback，再 BAR1 uninstall**，fallback 仍需原有 per-device 配置。检查卸载提示、保留的用户 registry keys 和备份；检查服务不再 enabled、initramfs 不再提前加载旧模块、depmod 不再指向 updates/p2p，再人工重启并验证原厂驱动和原 BAR1。卸载不会即时缩小当前运行中的 BAR1。

紧急一次启动：GRUB 增加 `systemd.mask=geforce-bar1-resize.service` 可阻止该次 BAR1 恢复，但不会自动撤销 patched 驱动选择；需要时选择保留的原厂驱动内核／恢复模式并还原配置。单纯断电不等于持久回滚，启用的服务下次还会施加。

本次整理未执行真实回滚。Stage 8 记录中的 dry-run／故障注入不等于实机回滚成功，也不推广其中包含 Unlock 的私有整机脚本。
