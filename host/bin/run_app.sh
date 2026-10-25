#!/bin/bash

bindir="$(dirname $0)"

dev=$(lspci -d 22c2:1100)

[ -z "$dev" ] && {
  echo "Could not find the Gowin's PCIe device."
  exit 1
}

echo -e "Find PCIe device:\n$dev\n"

grep -e 'Gowin' -e 'GOWIN' /usr/share/misc/pci.ids -q || {
  sudo sed -i '/Illegal Vendor ID/i\
22c2  Gowin Semiconductor Corporation' /usr/share/misc/pci.ids
}

lsmod | grep -q 'gowin_pcie' || {
  sudo insmod ${bindir}/../driver/gowin_pcie_drv.ko
}

width=256
height=8
kernel=3
block=128
dump=0

if [ $# -ge 1 ]; then
  width=$1
  height=${2:-$height}
  kernel=${3:-$kernel}
  block=${4:-$block}
  dump=${5:-$dump}
else
  read -r -p "Image  width [$width]: " value
  width=${value:-$width}
  read -r -p "Image height [  $height]: " value
  height=${value:-$height}
  read -r -p "Kernel  size [  $kernel]: " value
  kernel=${value:-$kernel}
  read -r -p "Block   size [$block]: " value
  block=${value:-$block}
  read -r -p "Enable  dump [  $dump]: " value
  dump=${value:-$dump}
fi

echo "width=$width height=$height kernel=$kernel block=$block dump=$dump"

sudo ${bindir}/conv "$width" "$height" "$kernel" "$block" "$dump"
