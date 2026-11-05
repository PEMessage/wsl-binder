{
  description = "WSL2 kernel 6.18.35.2 and the out-of-tree binder module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    kernel-src = {
      url = "github:microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.18.35.2";
      flake = false;
    };
    binder-src = {
      url = "github:choff/anbox-modules";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, kernel-src, binder-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      # The vendor kernel is built with GCC 13.2; genksyms CRCs depend on
      # CONFIG_GCC_VERSION, so the compiler major is part of the module ABI.
      stdenv = pkgs.stdenvAdapters.overrideCC pkgs.stdenv pkgs.gcc13;

      nativeTools = with pkgs; [ bc bison flex perl pkg-config pahole kmod python3 ];
      hostLibs = with pkgs; [ elfutils zlib openssl ];

      kernel = stdenv.mkDerivation {
        pname = "wsl2-kernel";
        version = "6.18.35.2";
        src = kernel-src;

        outputs = [ "out" "dev" ];

        nativeBuildInputs = nativeTools;
        buildInputs = hostLibs;

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

      binder = stdenv.mkDerivation {
        pname = "binder-linux";
        version = "6.18.35.2";
        src = binder-src;

        nativeBuildInputs = nativeTools;
        buildInputs = hostLibs;

        buildPhase = ''
          runHook preBuild
          make -C ${kernel.dev} M=$PWD/binder modules
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm444 binder/binder_linux.ko \
            $out/lib/modules/6.18.35.2-microsoft-standard-WSL2/extra/binder_linux.ko
          runHook postInstall
        '';
      };
    in
    {
      packages.${system} = {
        inherit kernel binder;
        default = binder;
      };

      devShells.${system}.default = (pkgs.mkShell.override { inherit stdenv; }) {
        packages = nativeTools ++ hostLibs;
        shellHook = ''
          echo "kernel 6.18.35.2 build env: $(gcc --version | head -1)"
        '';
      };
    };
}
