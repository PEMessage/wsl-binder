{
  description = "WSL2 out-of-tree binder, one package set per kernel version";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    binder-src = {
      url = "github:choff/anbox-modules";
      flake = false;
    };

    # One entry per supported kernel version. The attribute name is the
    # version; the URL pins the vendor tree it must be built against.
    "kernel-6.18.35.2" = {
      url = "github:microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.18.35.2";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, binder-src, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;

      # Keep in sync with the `kernel-*` inputs above; newest first.
      versions = [ "6.18.35.2" ];

      # `uname -r` of a WSL2 kernel is its version plus the vendor localversion.
      release = version: "${version}-microsoft-standard-WSL2";

      # The vendor kernel is built with GCC 13.2; genksyms CRCs depend on
      # CONFIG_GCC_VERSION, so the compiler major is part of the module ABI.
      stdenv = pkgs.stdenvAdapters.overrideCC pkgs.stdenv pkgs.gcc13;

      nativeTools = with pkgs; [ bc bison flex perl pkg-config pahole kmod python3 ];
      hostLibs = with pkgs; [ elfutils zlib openssl ];

      kernelFor =
        version:
        stdenv.mkDerivation {
          pname = "wsl2-kernel";
          inherit version;
          src = inputs."kernel-${version}";

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

      binderFor =
        version: kernel:
        stdenv.mkDerivation {
          pname = "binder-linux";
          inherit version;
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
              $out/lib/modules/${release version}/extra/binder_linux.ko
            runHook postInstall
          '';
        };

      packagesFor =
        version:
        let
          kernel = kernelFor version;
        in
        {
          "kernel-${version}" = kernel;
          "binder-${version}" = binderFor version kernel;
        };

      latest = builtins.head versions;
    in
    {
      packages.${system} = builtins.foldl' (acc: version: acc // packagesFor version) { } versions // {
        default = binderFor latest (kernelFor latest);
      };

      devShells.${system}.default = (pkgs.mkShell.override { inherit stdenv; }) {
        packages = nativeTools ++ hostLibs;
        shellHook = ''
          echo "kernel build env: $(gcc --version | head -1)"
        '';
      };
    };
}
