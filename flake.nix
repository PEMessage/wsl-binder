{
  description = "WSL2 out-of-tree binder, one package set per kernel version";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    binder-src = {
      url = "github:choff/anbox-modules";
      flake = false;
    };

    # One entry per supported kernel version; must match the `kernels` table
    # in outputs.
    "kernel-6.18.35.2" = {
      url = "github:microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.18.35.2";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, binder-src, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      # Everything that differs per kernel version lives in this table.
      kernels = {
        "6.18.35.2" = {
          version = "6.18.35.2";
          kernel-src = inputs."kernel-6.18.35.2";
          release = "6.18.35.2-microsoft-standard-WSL2";

          # The vendor kernel is built with GCC 13.2; genksyms CRCs depend on
          # CONFIG_GCC_VERSION, so the compiler major is part of the module ABI.
          stdenv = pkgs.stdenvAdapters.overrideCC pkgs.stdenv pkgs.gcc13;

          nativeBuildInputs = with pkgs; [ bc bison flex perl pkg-config pahole kmod python3 ];
          hostLibs = with pkgs; [ elfutils zlib openssl ];
        };
      };

      defaultVersion = "6.18.35.2";

      mkKernel =
        cfg:
        cfg.stdenv.mkDerivation {
          pname = "wsl2-kernel";
          version = cfg.version;
          src = cfg.kernel-src;

          outputs = [ "out" "dev" ];

          nativeBuildInputs = cfg.nativeBuildInputs;
          buildInputs = cfg.hostLibs;

          postPatch = ''
            # scripts/bpf_doc.py has no /usr/bin/env to point at in the sandbox
            patchShebangs scripts tools/bpf
          '';

          configurePhase = ''
            runHook preConfigure
            cp arch/x86/configs/config-wsl .config
            make olddefconfig
            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild
            make -j$NIX_BUILD_CORES bzImage modules
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp arch/x86/boot/bzImage System.map Module.symvers $out/
            make INSTALL_MOD_PATH=$out modules_install
            rm -f $out/lib/modules/*/build $out/lib/modules/*/source

            # Prepared tree for out-of-tree modules (make -C $dev M=...).
            mkdir -p $dev
            cp -a . $dev/
            find $dev -name '*.o' -delete
            find $dev -name '*.a' -delete
            find $dev -name '*.ko' -delete
            rm -f $dev/vmlinux $dev/vmlinux.o $dev/vmlinux.unstripped $dev/.tmp_vmlinux*

            runHook postInstall
          '';
        };

      mkBinder =
        cfg: kernel:
        cfg.stdenv.mkDerivation {
          pname = "binder-linux";
          version = cfg.version;
          src = binder-src;

          nativeBuildInputs = cfg.nativeBuildInputs;
          buildInputs = cfg.hostLibs;

          buildPhase = ''
            runHook preBuild
            make -C ${kernel.dev} M=$PWD/binder modules
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm444 binder/binder_linux.ko \
              $out/lib/modules/${cfg.release}/extra/binder_linux.ko

            # Make $out a self-contained modules tree, so it can be loaded
            # with `modprobe -d $out binder_linux` (no /lib/modules involved).
            ${pkgs.kmod}/bin/depmod -b $out ${cfg.release}

            runHook postInstall
          '';
        };

      packagesFor =
        cfg:
        let
          kernel = mkKernel cfg;
        in
        {
          "kernel-${cfg.version}" = kernel;
          "binder-${cfg.version}" = mkBinder cfg kernel;
        };

      allPackages = lib.foldl' (acc: cfg: acc // packagesFor cfg) { } (lib.attrValues kernels);
    in
    {
      nixosModules = {
        default = import ./module.nix self;
        wsl-binder = self.nixosModules.default;
      };

      packages.${system} = allPackages // {
        default = allPackages."binder-${defaultVersion}";
      };

      devShells.${system}.default =
        (pkgs.mkShell.override { stdenv = kernels.${defaultVersion}.stdenv; }) {
          packages = kernels.${defaultVersion}.nativeBuildInputs ++ kernels.${defaultVersion}.hostLibs;
          shellHook = ''
            echo "kernel build env: $(gcc --version | head -1)"
          '';
        };
    };
}
