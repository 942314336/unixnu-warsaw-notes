#!/bin/bash
# diag251（唯一杠杆＝撤掉 PerfPowerServices 的 posix_spawn deny：只删 error=ENOENT;goto bad; 两句，诊断点与 ps : n/t 计数器原样留着，n= 语义改成「认出次数」；种子＝diag250 那颗 data-seed250-gpt70.img 逐字未换（payload.json data_ramdisk_sha256=3571667e…）、boot-arg 未动、面板格式串未动＝行数与 diag247/250 逐字相同；判据闭集见 header251.txt；表头 [wd247 -> [wd251；bootimg sha ef2a16bc…
cd "$(dirname "$0")" || exit 1
DEV=${DEV:-b53c187d}
IMG=boot-m5c-diag251.img
OFFS="150 210 270 330 390 450 540 660 900 1500 2400 2700 2760 2820 2880 2940 3000 3060"

g=$(timeout 10 fastboot -s $DEV getvar is-userspace 2>&1 | head -1)
echo "$(date +%H:%M:%S) pre-flight getvar: $g"
case "$g" in
  *"userspace: yes"*) echo "$(date +%H:%M:%S) in fastbootd (userspace fastboot 不认 boot) -> pre-hopping to ABL"
    timeout 30 fastboot -s $DEV reboot bootloader >/dev/null 2>&1; sleep 12
    g=$(timeout 10 fastboot -s $DEV getvar is-userspace 2>&1 | head -1)
    echo "$(date +%H:%M:%S) after pre-hop: $g" ;;
esac
case "$g" in
  *"userspace: no"*) : ;;
  *) echo "ABORT: not answering in ABL ($g) -- no fire"; exit 1 ;;
esac

echo "$(date +%H:%M:%S) arming misc (boot-fastboot)"
timeout 60 fastboot -s $DEV flash misc misc-bcb-fb.img 2>&1 | tail -2
echo "$(date +%H:%M:%S) firing $IMG"
date +%s > diag251-t0.txt
timeout 40 fastboot -s $DEV boot $IMG 2>&1 | tail -2
t0=$(cat diag251-t0.txt)
echo "$(date +%H:%M:%S) fired el=$(( $(date +%s) - t0 ))"

for off in $OFFS; do
  eval "done$off=0"
done
for i in $(seq 1 1700); do
  now=$(date +%s); el=$((now - t0)); hh=$(date +%H:%M:%S)
  out=$(timeout 6 fastboot -s $DEV getvar is-userspace 2>&1)
  if echo "$out" | grep -q "userspace: yes"; then
    echo "$hh el=$el FASTBOOTD -- hopping to ABL"
    timeout 30 fastboot -s $DEV reboot bootloader >/dev/null 2>&1
    sleep 12
    echo "$(date +%H:%M:%S) AFTER-HOP $(timeout 10 fastboot -s $DEV getvar is-userspace 2>&1 | head -1)"
    echo "READ el=$el"
    exit 0
  elif echo "$out" | grep -q "userspace: no"; then
    if [ "$el" -gt 210 ]; then
      echo "$hh el=$el BACK-IN-ABL (no hop needed)"
      echo "READ el=$el"
      exit 0
    fi
    echo "$hh el=$el still ABL, too early to count"
  fi
  for off in $OFFS; do
    eval "d=\$done$off"
    if [ "$d" = "0" ] && [ "$el" -ge "$off" ]; then
      echo "$hh SHOT$off el=$el $(bash hwgrab.sh diag251-shot$off.jpg 2>&1 | tail -1)"
      eval "done$off=1"
    fi
  done
  sleep 2
done
echo "TIMEOUT: no return after $el s"
