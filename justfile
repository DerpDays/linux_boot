spawn-direct:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux /mnt/boot/vmlinuz-linux --initrd /mnt/boot/initramfs-linux.img

spawn-direct-initramfs:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux /mnt/boot/vmlinuz-linux --initrd /mnt/boot/initramfs.cpio.gz


mount:
  mkdir -p /mnt/boot /mnt/root
  LO_DEVICE=$(losetup --find --show --partscan root.img) mount ${LO_DEVICE}p1 /mnt/boot && mount ${LO_DEVICE}p2 /mnt/root

unmount:
  losetup -D

spawn-boot:
  systemd-vmspawn --network-user-mode -i root.img

spawn-boot-gui:
  systemd-vmspawn --network-user-mode -i root.img --console gui


