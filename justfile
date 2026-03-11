kernel:
  git clone --depth=1 --branch v7.0-rc2 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

spawn-direct:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux arch_root/vmlinuz-linux --initrd arch_root/initramfs-linux.img --firmware $SYSTEMD_VM_FIRMWARE_DIR/50-edk2-x86_64-secure.json 

spawn-direct-initramfs:
  sudo systemd-vmspawn --network-user-mode -i root.img --linux arch_root/vmlinuz-linux --initrd initramfs.cpio.gz --firmware $SYSTEMD_VM_FIRMWARE_DIR/50-edk2-x86_64-secure.json 

spawn-boot:
  systemd-vmspawn --network-user-mode -i root.img --firmware $SYSTEMD_VM_FIRMWARE_DIR/50-edk2-x86_64-secure.json
spawn-boot-gui:
  systemd-vmspawn --network-user-mode -i root.img --firmware $SYSTEMD_VM_FIRMWARE_DIR/50-edk2-x86_64-secure.json --console gui




uefi:
  mkdir -p esp/efi/boot
  cd uefi-boot && cargo build --target x86_64-unknown-uefi --release
  cp uefi-boot/target/x86_64-unknown-uefi/release/uefi-boot.efi esp/efi/boot/bootx64.efi
  qemu-system-x86_64 -enable-kvm -m 4G \
      -drive if=pflash,format=raw,readonly=on,file={{join("${SYSTEMD_VM_FIRMWARE_DIR}","..", "edk2-x86_64-code.fd")}} \
      -drive if=pflash,format=raw,readonly=on,file={{join("${SYSTEMD_VM_FIRMWARE_DIR}","..", "edk2-i386-vars.fd")}} \
      -drive format=raw,file=fat:rw:esp
