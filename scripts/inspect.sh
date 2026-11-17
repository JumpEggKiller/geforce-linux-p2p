#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Read-only. Review output locally before sharing.
set -euo pipefail
lspci -Dnn -d 10de: | awk '/VGA compatible controller|3D controller/'
nvidia-smi topo -m
for dev in /sys/bus/pci/devices/*; do
 [[ -r "$dev/vendor" && $(cat "$dev/vendor") == 0x10de ]] || continue
 [[ -r "$dev/class" && $(cat "$dev/class") == 0x030[02]00 ]] || continue
 echo "PCI ${dev##*/} parent $(basename "$(dirname "$(readlink -f "$dev")")")"
 awk 'NR==2 {printf "BAR1 resource start=%s end=%s flags=%s\n",$1,$2,$3}' "$dev/resource"
 [[ ! -r "$dev/resource1_resize" ]] || cat "$dev/resource1_resize"
done
