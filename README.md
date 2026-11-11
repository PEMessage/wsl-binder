# wsl-binder

Out-of-tree Android binder (`binder_linux.ko`) for WSL2, built with Nix
against the exact Microsoft WSL kernel.

## Packages

```sh
nix build '.#packages.x86_64-linux."binder-6.18.35.2"'
```

The flake exposes `kernel-<version>` and `binder-<version>` for every supported
WSL kernel; `nixosModules.default` provides `services.wsl-binder`. Attribute
names contain dots, so quote them in flake installables.

## Releases

Releases are created manually from **Actions → Release → Run workflow**. Each
run:

1. builds every `binder-*` package;
2. creates a `YYYY-MM-DD-<adjective>-<noun>` tag (mason-registry style);
3. signs the NAR with the repository cache key;
4. publishes the signed binary cache (`nix-cache-info`, `*.narinfo`,
   `*.nar.xz`) and a self-contained `lib/modules/<release>/` tarball for
   non-NixOS WSL distributions.

### One-time signing key

The workflow reads the private key from the repository secret
`NIX_CACHE_PRIVATE_KEY`:

```sh
nix key generate-secret --key-name wsl-binder-1 > cache-priv-key.pem
nix key convert-secret-to-public < cache-priv-key.pem
gh secret set NIX_CACHE_PRIVATE_KEY < cache-priv-key.pem
```

Keep the private key out of the repository. The public key is derived from it
and published as the `cache-public-key.pem` asset in every release.

### Using the binary cache

```nix
nix.settings = {
  extra-substituters = [
    "https://github.com/<owner>/<repo>/releases/latest/download"
  ];
  extra-trusted-public-keys = [
    "wsl-binder-1:..." # from the cache-public-key.pem release asset
  ];
};
```

The cache contains only the `binder-*` outputs, not the full kernel. Release
assets are fetched anonymously, so the repository must be public (or consumers
need their own authenticated fetcher).

### Non-NixOS WSL (Ubuntu, ...)

Pick the tarball whose kernel release matches `uname -r`. It contains the
complete modules tree (`lib/modules/<release>/...`), so it can be unpacked
anywhere and loaded without touching the system's `/lib/modules`:

```sh
sudo mkdir -p /opt/wsl-binder
sudo tar -C /opt/wsl-binder -xzf binder-<release>.tar.gz
# -C /dev/null ignores host modprobe.d, -d selects the unpacked tree
sudo modprobe -C /dev/null -d /opt/wsl-binder binder_linux
sudo mkdir -p /dev/binderfs
sudo mount -t binder binder /dev/binderfs
for d in binder hwbinder vndbinder; do
  sudo ln -sfn "/dev/binderfs/$d" "/dev/$d"
done
```

This is a one-shot load; wire the same `modprobe` command into systemd if the
module is needed at boot.
