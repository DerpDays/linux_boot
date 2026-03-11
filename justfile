spawn-direct:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux /mnt/boot/vmlinuz-linux --initrd /mnt/boot/initramfs-linux.img

spawn-direct-initramfs:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux /mnt/boot/vmlinuz-linux --initrd /mnt/boot/initramfs.cpio.gz


mount:
  mkdir -p /mnt/boot /mnt/root
  LO_DEVICE=$(losetup --find --show --partscan root.img) mount ${LO_DEVICE}p1 /mnt/boot && mount ${LO_DEVICE}p2 /mnt/root

unmount:
  losetup -D

bootloader-copy:
  mkdir -p /mnt/boot/efi/boot
  cd uefi-boot && cargo build --target x86_64-unknown-uefi --release && cp target/x86_64-unknown-uefi/release/uefi-boot.efi /mnt/boot/efi/boot/bootx64.efi && sync

initramfs-copy:
  ./mkinitramfs
  cp initramfs.cpio.gz /mnt/boot
  

spawn-boot:
  systemd-vmspawn --network-user-mode -i root.img

spawn-boot-gui:
  systemd-vmspawn --network-user-mode -i root.img --console gui


