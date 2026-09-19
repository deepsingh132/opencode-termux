# opencode-termux

Run **[OpenCode](https://github.com/anomalyco/opencode)** — the terminal AI coding
assistant — **natively on Termux (Android)**.

No proot. No Ubuntu container. No glibc. Just one Android program that runs directly in
Termux, installs like a normal package, and starts with the `opencode` command.

Built for **arm64 Android phones on Android 9 (API 28) or newer**.

---

## Quick start

Open Termux and paste this:

```bash
pkg install -y curl
curl -fsSL https://raw.githubusercontent.com/deepsingh132/opencode-termux/native-android/scripts/termux-upgrade.sh -o termux-upgrade.sh
bash termux-upgrade.sh
```

That one script does **everything**: installs any missing tools, downloads the latest
OpenCode, builds it for your phone, installs it, and prints the version when it is done.

Then run:

```bash
opencode            # open the interactive app (TUI)
opencode run "hi"   # ask a single question
```

### In a hurry? Skip the build

```bash
bash termux-upgrade.sh --release
```

This installs the newest ready-made package from
[Releases](https://github.com/deepsingh132/opencode-termux/releases) — no compiling, much
faster.

> **Before you start**
>
> - Install Termux from [F-Droid](https://f-droid.org/packages/com.termux/) or
>   [GitHub](https://github.com/termux/termux-app/releases). The Play Store version is
>   outdated and will not work.
> - Building needs about **2 GB of free space** and an internet connection.

---

## Updating

Run the same script again — it always picks up the latest version:

```bash
bash termux-upgrade.sh              # rebuild the latest
bash termux-upgrade.sh --release    # install the latest prebuilt package
```

Install a specific version:

```bash
bash termux-upgrade.sh 1.18.31
```

## All options

| Command | What it does |
| --- | --- |
| `bash termux-upgrade.sh` | Build and install the latest version |
| `bash termux-upgrade.sh <version>` | Build and install a specific version |
| `bash termux-upgrade.sh --release` | Don't build; install the latest prebuilt `.deb` |
| `bash termux-upgrade.sh --no-install` | Build the package but don't install it |
| `bash termux-upgrade.sh --force` | Rebuild even if the version is already installed |
| `bash termux-upgrade.sh --pacman` | Also create a pacman package |
| `bash termux-upgrade.sh --no-pull` | Don't update the repo before building |
| `bash termux-upgrade.sh --help` | Show help |

The script can be run from anywhere. If it is not inside a copy of this project, it
clones the project to `~/opencode-termux` first. Once cloned, you can also run
`~/opencode-termux/scripts/termux-upgrade.sh` directly.

### Manual install

Download `opencode_<version>_aarch64.deb` from
[Releases](https://github.com/deepsingh132/opencode-termux/releases) and install it:

```bash
dpkg -i opencode_<version>_aarch64.deb
```

### Uninstall

```bash
dpkg -r opencode
```

---

## What is this, in plain words?

OpenCode is an AI assistant that lives in your terminal. Its normal Linux builds depend
on a system library called `glibc`, which **Android does not have** (Android uses a
different library called `bionic`). Because of that, the normal Linux download crashes in
Termux.

This project adapts OpenCode to run **natively**:

1. Start from the **official Android build of Bun** (the JavaScript engine OpenCode uses),
   published by the Bun project.
2. Take OpenCode's actual program code and graft ("transplant") it into that Android Bun.
3. Swap in an Android-compatible renderer so the full-screen text UI works.
4. Package the result as one file you install with `dpkg`.

The result behaves like a normal Termux program: `opencode` just works — no `proot`, no
extra Linux distribution, no compatibility layer at runtime.

### What works

- ✅ The full interactive terminal UI (TUI)
- ✅ `opencode run "..."`, `opencode serve`, providers, models, and plugins
- ✅ No glibc, no proot, no Ubuntu container
- ✅ Easy updates straight from this repository's releases

### Requirements

| Requirement | Why |
| --- | --- |
| 64-bit (arm64 / aarch64) device | Packages are built for `aarch64` |
| Android 9 (API 28) or newer | The native binary needs a recent Android `bionic` |
| Termux from F-Droid or GitHub | The Play Store version is outdated |
| ~2 GB free space while building | Downloads and temporary build files |

---

## Troubleshooting

| Problem | What to do |
| --- | --- |
| `opencode: command not found` right after install | Reopen Termux, or run `hash -r` |
| The script says a package is missing | Just run it again; it installs dependencies automatically |
| `--release` says the release was not found | That version isn't published yet — run without `--release` to build it locally |
| An old version still starts | Check for duplicates with `dpkg -l \| grep opencode` and remove extras |
| Build fails with no space | Free up storage and re-run; the build needs ~2 GB free |
| A brand-new OpenCode version isn't showing up | Releases are built automatically (daily). To get it immediately, run `bash termux-upgrade.sh` |
| TUI looks broken or will not start | Make sure you are on Android 9+ with F-Droid/GitHub Termux |

---

## For developers

Everything below is about *how* the build works. If you only want to use OpenCode, you
can stop reading here.

### How the native build works

```
 official Android Bun (ELF)        OpenCode program code (module graph)
              \___________________________/
                            |
        tools/transplant/transplant.py  (graft)
                            |
        "revive" surgery (fix the embedded size field)
                            |
        swap in an Android build of libopentui.so (TUI renderer)
                            |
        seccomp hardening shim (aarch64)
                            |
        single runnable opencode ELF (~180 MB) -> .deb
```

Key pieces:

- **`tools/prebuilt/libopentui-bionic.so`** — the Android build of the TUI renderer.
- **`tools/prebuilt/libopencode-crhandler.so`** — a small aarch64 seccomp shim.
- **`tools/transplant/`** — the graft/revive pipeline (`transplant.py`, `swap_tui.py`,
  `revive_patch.py`).

### Manual build

```bash
make transplant VER=1.18.31   # -> artifacts/transplant/1.18.31/opencode-native-tui
make deb-native VER=1.18.31   # -> packing/dpkg-native/opencode_1.18.31_aarch64.deb
make pacman-native VER=1.18.31
```

The everyday entry point is still just:

```bash
./scripts/termux-upgrade.sh
```

### GitHub Actions

`.github/workflows/build-native-self.yml` runs on a free `ubuntu-latest` runner (no
self-hosted machine needed):

1. Resolves the latest (or requested) OpenCode version.
2. Skips if that version is already released.
3. Downloads the official Android Bun and the OpenCode package.
4. Runs the transplant pipeline, swaps the TUI library, and applies seccomp hardening.
5. Builds the `.deb` and publishes a release tagged `native-<version>`.

It runs on a daily schedule and can also be started manually:

```bash
gh workflow run build-native-self.yml --repo deepsingh132/opencode-termux \
  --ref native-android --field version=1.18.31
```

Shell unit tests live in `tests/unit/` and run via `.github/workflows/tests.yml`
(`./tests/run.sh`).

> **Note:** CI runs on x86 and can only *produce* the aarch64 package; it cannot run it.
> Final runtime checks happen on a real device — `make transplant` performs an on-device
> TUI probe (`tui_probe: pass`).

### Repository layout

```
scripts/
  termux-upgrade.sh          one-command build + install (the user script)
  package/                   .deb / pacman builders
tools/
  transplant/                graft + revive + TUI swap pipeline
  prebuilt/                  version-independent aarch64 binaries (TUI lib, shim)
  watcher/                   native file-watcher daemon + plugin shim
.github/workflows/
  build-native-self.yml      automated native build + release
  tests.yml                  shell unit tests
Makefile                     make transplant / deb-native / pacman-native
```

Full technical notes: [`docs/transplant.md`](docs/transplant.md),
[`docs/comparison-runtime-lines.md`](docs/comparison-runtime-lines.md).

---

## Credits

- **[OpenCode](https://github.com/anomalyco/opencode)** — the app itself.
- **[Bun](https://github.com/oven-sh/bun)** — its official Android build is the base.
- **[Hope2333/opencode-termux](https://github.com/Hope2333/opencode-termux)** — the
  original transplant/revive pipeline this project builds on.
- **[OpenTUI](https://github.com/anomalyco/opentui)** — the TUI renderer.

## License

MIT — see [LICENSE](LICENSE).
