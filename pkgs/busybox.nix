{
  pkgs ? import <nixpkgs> { },
}:
pkgs.busybox.override {
  enableStatic = true;
}
