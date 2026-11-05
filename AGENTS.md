# AGENTS.md

Out-of-tree Android binder for WSL2, built against the exact Microsoft WSL
kernel that is running. WSL owns the kernel; this repo only produces a
`binder_linux.ko` matching its ABI.

## Layout

```
flake.nix      kernel + binder build, sources pinned by flake.lock
flake.lock
```

- The flake targets one kernel version; `kernel-src` must match `uname -r`.
- Sources are flake inputs (`kernel-src`, `binder-src`), not submodules: a git
  flake does not export submodule contents, and path-input workarounds copy the
  whole kernel tree into the store.
- `nixpkgs` is pinned to the revision used by the main NixOS flake.

## Changing the kernel version

Point `kernel-src` at `linux-msft-wsl-<ver>` (and update the version strings in
`flake.nix`), then:

```sh
nix flake lock
```

Keep the previous state on a branch if both versions are needed.

## Build

The flake pins the toolchain and builds the kernel and module:

```sh
nix develop                    # gcc 13, pahole, elfutils/zlib/openssl headers
nix build .#kernel             # bzImage + modules + Module.symvers, plus .dev
nix build .#binder             # binder_linux.ko built against kernel.dev
```

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
