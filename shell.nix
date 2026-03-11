{
  pkgs ? import <nixpkgs> { },
}:
let
  buildInputs = [
    # linux kernel
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.ncurses
    pkgs.bison
    pkgs.flex
    pkgs.bc
    pkgs.elfutils

    # initramfs (utils-linux, dash)
    pkgs.gcc
    pkgs.autoconf
    pkgs.gettext
    pkgs.libtool
    pkgs.automake

    pkgs.cpio
    pkgs.gzip
    pkgs.fd

    pkgs.cargo # uutils

    # simple command runner
    pkgs.just

    pkgs.arch-install-scripts

    # qemu for our linux/efi vm
    pkgs.qemu
    pkgs.virtiofsd
  ];
in
pkgs.mkShell {
  inherit buildInputs;
  shellHook = ''
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${builtins.toString (pkgs.lib.makeLibraryPath buildInputs)}";
    export PKG_CONFIG_PATH="$PKG_CONFIG_PATH:${pkgs.ncurses.dev}/lib/pkgconfig:"
    export SYSTEMD_VM_FIRMWARE_DIR=${pkgs.qemu}/share/qemu/firmware
  '';
}
