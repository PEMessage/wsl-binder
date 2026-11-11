# wsl-binder

Android binder kernel module for WSL2 distributions.

The kernel that ships with WSL does not include the Android binder driver, so
Android containers and runtimes (Waydroid, Anbox, OpenHarmony tooling, ...)
cannot run there out of the box. This repository provides `binder_linux.ko`
for the kernel WSL is actually running, with binderfs exposing `binder`,
`hwbinder` and `vndbinder`.

A kernel module only loads into the kernel it was built for. Every module here
is therefore tied to one kernel release (`uname -r`); after a WSL update a new
release is needed.

## Install

### Ubuntu (or another distribution)

#### Load the module

Grab the `binder-<release>.tar.gz` asset whose name matches `uname -r` from
the releases page. It contains a self-contained modules tree, so nothing is
written to the system's `/lib/modules`:

```sh
uname -r
sudo mkdir -p /opt/wsl-binder
sudo tar -C /opt/wsl-binder -xzf binder-<release>.tar.gz
sudo modprobe -C /dev/null -d /opt/wsl-binder binder_linux
```

#### binderfs and device nodes

```sh
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
for dev in binder hwbinder vndbinder; do
  sudo ln -sfn "/dev/binderfs/$dev" "/dev/$dev"
  sudo chmod 0666 "/dev/binderfs/$dev"
done
```

To do this at boot, add `binder_linux` to `/etc/modules-load.d/binder.conf`
and mount binderfs from `/etc/fstab` (or a systemd mount unit).

### NixOS

The flake pins the kernel source, compiler and module together, and prebuilt
outputs are published to this repository's releases. An existing NixOS flake
only needs the input, the cache and the module:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    wsl-binder.url = "github:PEMessage/wsl-binder";
  };

  nixConfig = {
    extra-substituters = [
      "https://github.com/PEMessage/wsl-binder/releases/latest/download"
    ];
    extra-trusted-public-keys = [
      "wsl-binder-1:+J56oPBLvItpSBAJ3RBDy6G9vxzPEP8VwXqJ6aIo2sI="
    ];
  };

  outputs = { self, nixpkgs, wsl-binder, ... }: {
    nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        wsl-binder.nixosModules.default
        { services.wsl-binder.enable = true; }
        ./configuration.nix
      ];
    };
  };
}
```

`services.wsl-binder` loads the module at boot, mounts binderfs and creates
`/dev/binder`, `/dev/hwbinder` and `/dev/vndbinder`. It never writes to
`/lib/modules`. The two halves can be controlled separately with
`services.wsl-binder.load.enable` and `services.wsl-binder.binderfs.enable`.
