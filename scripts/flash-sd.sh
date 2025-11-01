#!/usr/bin/env sh
img="$1"
sdcard="$2"
read -p "Will copy $1 to $2; continue? [yN]" choice
if [ "$choice" == "y" ]
then
  dd if=result/sd-image/nixos-image-sd-card-25.11.20251031.2fb006b-aarch64-linux.img |
    pv --size @result/sd-image/nixos-image-sd-card-25.11.20251031.2fb006b-aarch64-linux.img -u shaded |
    sudo dd of=/dev/sdc bs=1M conv=fsync
fi
