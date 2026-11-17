# 验证

先从两卡、小尺寸开始，再完整验收，始终逐对串行，不默认运行四卡高负载。日志只留在忽略的 local-logs/，对外分享前必须脱敏。

```bash
mkdir -p build local-logs
bash upstream/driver/contrib/integrity/build.sh
upstream/driver/contrib/integrity/p2p-integrity --selftest
upstream/driver/contrib/integrity/p2p-integrity --list
# 地址为语法示例：
upstream/driver/contrib/integrity/p2p-integrity --pair 0000:21:00.0 0000:22:00.0 --max-mib 4 --repeat 1
upstream/driver/contrib/integrity/p2p-integrity --pair 0000:21:00.0 0000:22:00.0 --max-mib 4096 --repeat 3 --timeout 2400
nvcc -O2 -std=c++17 -gencode arch=compute_86,code=sm_86 -o build/p2p_latency src/p2p_latency.cu
./build/p2p_latency --pair 0000:21:00.0 0000:22:00.0 --iters 500
```

完整工具拒绝无真实双向 peer access 的卡对；覆盖 cudaMalloc／cuMem、6 patterns、guard bands、push／pull／SM store／load、两方向逐字节比对及复制带宽。检查末行 RESULT PASS 和退出码；FAIL／NO_P2P／timeout 均不可算通过。存在 skipped 尺寸时不能声称达到 Stage 8 的同等覆盖，必须核对 max-mib、cases 和 transfers。

4 卡需测 6 个无序卡对，每对覆盖两方向，共 12 方向。逐对保存退出码和统计；Stage 8 每对 792 cases／6336 transfers／4210.9 GiB，总 4752 cases／38016 transfers。

每次重启检查：`journalctl -b -u geforce-bar1-resize`、`lspci -Dvv` Region 1、`modinfo -n nvidia` 与版本、`nvidia-smi topo -m`、完整 --list。每卡实际 sysfs resource 的第二行给出 BAR1 start/end，大小为 end-start+1；不要只用 nvidia-smi 宣告 32G。

测试前后用 root 检查每卡及上游端口的 aer_dev_* 计数和 `sudo journalctl -k -b` 的 Xid／AER；无法读取时应记 UNKNOWN，不能当作零错误。延迟程序的 copy 指标包含提交和完成开销，pointer chase 是依赖读取延迟，不能混为链路线速。

Stage 8 warm reboot 后仅抽样复测两对，MAX_MIB=1024／REPEAT=2；它证明抽样持久性，不替代首次完整六对验收。
