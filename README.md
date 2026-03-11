# VM Image

The VM image was created using the Arch Linux bootstrap tarball.

- Download and extract arch-bootstrap-x86_64.tar.zst from a mirror (https://archlinux.org/download)

  - Extract with `tar xf /path-to-bootstrap-image/archlinux-bootstrap-x86_64.tar.zst --numeric-owner`
  - Select a few pacman mirrors in `/etc/pacman.d/mirrorlist`
  - Mount the root `sudo mount --bind ./root.x86_64 ./root.x86_64`
  - chroot using `arch-chroot` (install scripts are provided in this nix shell)

- Install `linux` (kernel), `dracut` (for later demonstrations), `neovim`, `sudo-rs` (and relevant setup)

- Make user `duscc` with password `duscc`

- Set locale, time, hostname

Create an image we can boot from:

- dd if=/dev/zero of=root.img bs=1M count=4096
- cfdisk root.img

> Here we create a GPT partition table, with two partitions (1GB EFI, 3GB Linux Root (x86_64) - this is so SystemD can find it for direct boot)

- Mount the image as a loopback device

  - `ROOT_LO_DEVICE=$(sudo losetup --find --show --partscan root.img)`

- Create filesystems

  - `mkfs.fat -F 32 -n BOOT ${ROOT_LO_DEVICE}p1`
  - `mkfs.ext4 -l ROOT ${ROOT_LO_DEVICE}p2`

- Finally, copying our bootstrapped arch root to

  - `sudo mount ${ROOT_LO_DEVICE}p1 /mnt`
  - `sudo cp -rp ./root.x86_64/* /mnt`

# Resources

- https://0xax.gitbooks.io/linux-insides/content/Initialization/
- https://docs.kernel.org/arch/x86/boot.html#pe-coff-entry-point
- https://docs.kernel.org/admin-guide/efi-stub.html
