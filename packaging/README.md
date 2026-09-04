# Arch and AUR release

The package name is `oma-preview`; the executable and application name are Oma Preview.
`PKGBUILD` pins the published source release with a SHA-256 checksum.

Build with `makepkg -s` from this directory. Install the resulting archive with
`sudo pacman -U oma-preview-*.pkg.tar.zst`. The package includes the desktop entry,
icon, QML UI and MIT license. It does not change defaults or write home folders.

If you previously used `install.sh`, run the repository's `uninstall.sh` before
switching to the system package; otherwise `~/.local/bin/oma-preview` can shadow
`/usr/bin/oma-preview` and hide future package updates.

Optional PDF default: `xdg-mime default org.omarchy.oma-preview.desktop application/pdf`.
The agent skill is shipped in `/usr/share/oma-preview/skills/oma-preview`; copy that
directory into `~/.codex/skills/` to enable agent discovery in a new task.

## First AUR upload

1. Register at https://aur.archlinux.org/register and add your SSH public key.
2. Clone `ssh://aur@aur.archlinux.org/oma-preview.git` into a separate directory.
3. Copy `PKGBUILD` and `.SRCINFO` from here into that checkout.
4. Commit those two files and push. Do not upload application source or binaries.

After AUR publication, Omarchy users can run `omarchy pkg aur add oma-preview`.
Until then, use the GitHub release package. Official Omarchy repository inclusion
requires a separate maintainer-reviewed change to `omacom/omarchy-pkgs`.

For future versions: tag the tested source, update `pkgver`, download that tag's
archive, replace its checksum, and regenerate `.SRCINFO` with
`makepkg --printsrcinfo > .SRCINFO`. Build and test before uploading.
