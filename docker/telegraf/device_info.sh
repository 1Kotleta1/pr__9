#!/bin/bash
# Сведения о Linux-хосте в формате InfluxDB line protocol (для inputs.exec).
H=${HOST_MOUNT_PREFIX:-}
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

. "$H/etc/os-release" 2>/dev/null
os="${PRETTY_NAME:-Linux}"
osver="${VERSION_ID:-?}"
kernel="$(uname -r)"
arch="$(uname -m)"
if [ -f "$H/etc/timezone" ]; then tz="$(cat "$H/etc/timezone")";
else tz="$(readlink "$H/etc/localtime" 2>/dev/null | sed 's#.*/zoneinfo/##')"; fi
tz="${tz:-${TZ:-UTC}} (UTC$(date +%:z))"
cpu="$(grep -m1 'model name' "$H/proc/cpuinfo" | cut -d: -f2- | sed 's/^ *//')"
threads="$(grep -c '^processor' "$H/proc/cpuinfo")"
cores="$(grep -m1 'cpu cores' "$H/proc/cpuinfo" | awk '{print $4}')"; cores="${cores:-$threads}"
ram=$(( $(awk '/MemTotal/ {print $2}' "$H/proc/meminfo") * 1024 ))
vendor="$(cat "$H/sys/class/dmi/id/sys_vendor" 2>/dev/null) $(cat "$H/sys/class/dmi/id/product_name" 2>/dev/null)"
btime="$(awk '/btime/ {print $2}' "$H/proc/stat")"
boot="$(date -d "@$btime" '+%Y-%m-%d %H:%M:%S')"

echo "device_info os=\"$(esc "$os")\",os_version=\"$(esc "$osver")\",kernel=\"$(esc "$kernel")\",arch=\"$arch\",timezone=\"$(esc "$tz")\",cpu_model=\"$(esc "$cpu")\",cpu_cores=${cores}i,cpu_threads=${threads}i,ram_total=${ram}i,manufacturer=\"$(esc "$vendor")\",last_boot=\"$boot\",user=\"-\""
