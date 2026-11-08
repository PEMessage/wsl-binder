# NixOS module: load the out-of-tree Android binder module and mount binderfs.
#
# NixOS-WSL sets boot.kernel.enable = false, so boot.kernelModules is inert
# (the modules-load.d file it would write is gated behind that option). This
# module writes the file itself and uses modprobe's `install` directive, so
# `modprobe binder_linux` insmods straight from the store. WSL's own
# /lib/modules overlay is never written to.
#
# With the binderfs-only patches, the module registers no static misc device:
# /dev/binder is a symlink into the binderfs mount.
self:
{ config, lib, pkgs, ... }:
let
  cfg = config.services.wsl-binder;

  load = pkgs.writeShellScript "wsl-binder-load" ''
    if ! ${pkgs.kmod}/bin/lsmod | grep -q '^binder_linux '; then
      ko=${cfg.package}/lib/modules/$(uname -r)/extra/binder_linux.ko
      if [ ! -e "$ko" ]; then
        echo "wsl-binder: no module for $(uname -r)" >&2
        exit 0
      fi
      ${pkgs.kmod}/bin/insmod "$ko"
    fi

    chmod ${cfg.mode} /dev/binderfs/binder 2>/dev/null || true
  '';
in
{
  options.services.wsl-binder = {
    enable = lib.mkEnableOption "the out-of-tree Android binder module";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "wsl-binder.packages.<system>.default";
      description = ''
        Binder package to load. It must be built for the running kernel; the
        default is the newest version known to the wsl-binder flake.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.str;
      default = "0666";
      description = ''
        Permissions for the binderfs devices (binder, hwbinder, vndbinder).
        Android conventionally uses 0666 so unprivileged processes can open
        them.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."modules-load.d/wsl-binder.conf".text = "binder_linux\n";

    environment.etc."modprobe.d/wsl-binder.conf".text = ''
      install binder_linux ${load}
      remove binder_linux ${pkgs.kmod}/bin/rmmod binder_linux
    '';

    systemd.services.wsl-binder-binderfs = {
      description = "Mount binderfs for wsl-binder";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
      requires = [ "systemd-modules-load.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "-${pkgs.util-linux}/bin/umount /dev/binderfs";
      };
      script = ''
        if ! grep -qw binder /proc/filesystems; then
          echo "wsl-binder: binderfs not available for $(uname -r)" >&2
          exit 0
        fi

        mkdir -p /dev/binderfs
        ${pkgs.util-linux}/bin/mountpoint -q /dev/binderfs ||
          ${pkgs.util-linux}/bin/mount -t binder binder /dev/binderfs

        for dev in binder hwbinder vndbinder; do
          ln -sfn /dev/binderfs/$dev /dev/$dev
          chmod ${cfg.mode} /dev/binderfs/$dev 2>/dev/null || true
        done
      '';
    };
  };
}
