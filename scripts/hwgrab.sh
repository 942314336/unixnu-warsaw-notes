#!/bin/bash
# hwgrab.sh [out.jpg] -- the Huawei P50 Pro is the eye: wake it, open the still
# camera, press the shutter, wait for the new DCIM file, pull it.
#
# The phone sits on a tripod with its main lens at the warsaw screen, so nothing
# here tries to aim; it only makes sure the screen is awake and the camera app
# is in front.  adb's remote paths need MSYS_NO_PATHCONV or Git Bash rewrites
# /sdcard/... into C:/Program Files/Git/sdcard/...
export MSYS_NO_PATHCONV=1
S=L2E0222401016332			# JAD-AL00 = the P50 Pro, not warsaw
OUT=${1:-hw-photo.jpg}
DIR=/sdcard/DCIM/Camera

if ! adb -s $S get-state >/dev/null 2>&1; then
  echo "no-eye: P50 Pro not on adb"
  exit 2
fi

# diag230b: the HarmonyOS updater dialog (hwouc) started stealing focus at
# 06:5x and the cold camera app needed more than 3 s, so the shutter fired on
# an app that was not in front yet.  Both are capture-chain bugs, not board
# state, so they are fixed here and nowhere else.
adb -s $S shell am force-stop com.huawei.android.hwouc >/dev/null 2>&1	# kill update dialog
adb -s $S shell input keyevent 224 >/dev/null 2>&1		# WAKEUP
sleep 1
adb -s $S shell input swipe 540 1900 540 800 250 >/dev/null 2>&1	# unlock
sleep 1
adb -s $S shell am start -a android.media.action.STILL_IMAGE_CAMERA >/dev/null 2>&1
sleep 5
adb -s $S shell input keyevent 139 >/dev/null 2>&1			# FOCUS: pin AF on the warsaw screen
sleep 1

before=$(adb -s $S shell "ls -t1 $DIR | grep -m1 '^IMG_.*jpg'" 2>/dev/null | tr -d '\r')
adb -s $S shell input keyevent 27 >/dev/null 2>&1		# CAMERA_SHUTTER

newest=""
for i in $(seq 1 25); do
  sleep 1
  newest=$(adb -s $S shell "ls -t1 $DIR | grep -m1 '^IMG_.*jpg'" 2>/dev/null | tr -d '\r')
  if [ -n "$newest" ] && [ "$newest" != "$before" ]; then break; fi
done
if [ -z "$newest" ] || [ "$newest" = "$before" ]; then
  echo "no-shot: nothing new in $DIR (last=$before)"
  exit 3
fi

rm -f "$OUT"
adb -s $S pull "$DIR/$newest" "$OUT" >/dev/null 2>&1
if [ ! -s "$OUT" ]; then
  echo "pull-failed: $newest"
  exit 4
fi
echo "shot=$newest out=$OUT $(stat -c %s "$OUT") bytes"
