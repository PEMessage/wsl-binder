# AGENTS.md

Out-of-tree Android binder for WSL2, built against the exact Microsoft WSL
kernel that is running. WSL owns the kernel; this repo only produces a
`binder_linux.ko` matching its ABI.

## Layout

```
flake.nix      kernel + binder build, sources pinned by flake.lock
flake.lock
module.nix     NixOS module: services.wsl-binder
patches/       binder fixes applied on top of binder-src (binderfs only)
```

- The flake targets one kernel version; `kernel-src` must match `uname -r`.
- Sources are flake inputs (`kernel-src`, `binder-src`), not submodules: a git
  flake does not export submodule contents, and path-input workarounds copy the
  whole kernel tree into the store.
- `nixpkgs-build` pins the toolchain that produces the artifacts; `nixpkgs` is
  the runtime side, safe for consumers to follow without rebuilding anything.
- `nixpkgs` is pinned to the revision used by the main NixOS flake.

## Adding a kernel version

Add the input (name = version, URL = vendor tag) and a matching entry in the
`kernels` table inside `outputs`; copy the existing entry and adjust
`version`, `kernel-src` and `release`:

```nix
# inputs
"kernel-6.18.4x.y" = {
  url = "github:microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.18.4x.y";
  flake = false;
};

# kernels
"6.18.4x.y" = {
  version = "6.18.4x.y";
  kernel-src = inputs."kernel-6.18.4x.y";
  release = "6.18.4x.y-microsoft-standard-WSL2";
  # ... stdenv, nativeBuildInputs, hostLibs
};
```

Then `nix flake lock`. Every entry yields `kernel-<ver>` and `binder-<ver>`;
`default` follows `defaultVersion`.

## Build

The flake pins the toolchain and builds the kernel and module:

```sh
nix develop                       # gcc 13, pahole, elfutils/zlib/openssl headers
nix build '.#packages.x86_64-linux."kernel-6.18.35.2"'  # bzImage + Module.symvers, plus .dev
nix build '.#packages.x86_64-linux."binder-6.18.35.2"'  # binder_linux.ko built against kernel.dev
```

Attribute names contain dots, so they must be quoted in installables.

The kernel build stops at `bzImage` plus `modules_prepare`; no in-tree modules
are compiled. An out-of-tree module links only against vmlinux exports, and the
`CONFIG_MODVERSIONS` CRCs it needs are emitted by the kernel compile itself
(`vmlinux.symvers`, copied to `Module.symvers`). `modules_prepare` alone is not
enough: it writes no `Module.symvers`. On 16 cores this is a 953 s clean build
instead of 2450 s. `.dev` keeps `vmlinux`, because
`CONFIG_DEBUG_INFO_BTF_MODULES` needs it as pahole's `--btf_base`; without it
module BTF generation is silently skipped.

## NixOS module

`nixosModules.default` provides `services.wsl-binder.enable`. It writes the
`modules-load.d` entry (plus a `modprobe.d` install rule) that NixOS-WSL's
disabled `boot.kernel.enable` would otherwise have written, so
`modprobe binder_linux` loads the store `.ko` without touching
`/lib/modules`. It then mounts binderfs at `/dev/binderfs` and links
`/dev/binder` there, because the packaged module has no static misc devices.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/), enforced by
`.githooks/commit-msg` (enable once per clone with
`git config core.hooksPath .githooks`):

```
<type>(<scope>): <subject>
```

- types: `feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- scope optional, e.g. `binder`, `kernel`, `docs`
- imperative subject, no trailing period, header <= 72 chars
- breaking change: `!` after type/scope and/or a `BREAKING CHANGE:` footer

## Scope

Kernel and module build only; NixOS integration is not here yet.
