# Stage 8 脱敏实测摘要

来源：本机最终 QUAD_P2P_INTEGRITY.md、QUAD_P2P_BANDWIDTH_LATENCY.csv、QUAD_PERSISTENCE_FINAL.md、QUAD_ROLLBACK_AND_RECOVERY.md。仅摘录核对后的公开统计，原始私有日志不上传；不是公开原始日志的独立审计证明。

- 四张 RTX 3090，各 32 GiB BAR1；6/6 卡对、12/12 方向。
- 每对 max-mib 4096、repeat 3，792 cases、6336 transfers、4210.9 GiB；合计 4752 cases、38016 transfers、25,265.4 GiB = 24.67 TiB，零错误。
- cudaMalloc／cuMem、6 patterns、guard bands、两方向 push／pull／SM store／load，逐字节比对。
- 单向 26.04–26.39 GB/s，双向 51.38–52.14 GB/s；[逐对带宽和延迟](bandwidth-latency.csv)。GB/s 为十进制，GiB/TiB 为二进制。
- 测试后报告 AER Fatal／Non-Fatal、Xid 均 0。
- warm reboot 后 4×32 GiB、12/12 Peer Access 保持，抽样 0↔3、1↔2（各 504.8 GiB）通过；不是重启后重新完整测试六对。
- 断电冷启动、四卡满载、六对并发带宽未测。回滚未实际执行。
- 本机未触发 gbr_layout，由内核扩大直连 Root Port 窗口。

P2P 允许程序跨卡访问，显存仍分属各卡，不等于透明统一 96 GB 显存。本次发布整理未重新改动驱动或运行硬件负载。
