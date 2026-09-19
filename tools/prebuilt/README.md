# Prebuilt aarch64 artifacts (self-serve CI)

Both files are opencode-version-independent and let the GitHub-hosted workflow
(`.github/workflows/build-native-self.yml`) produce full-TUI, seccomp-hardened
Termux packages without any cross-compilation toolchain in CI.

## `libopentui-bionic.so`

Android/Bionic build of OpenTUI's renderer that
`tools/transplant/transplant.py all` equal-length-swaps into the transplanted
ELF (`swap_tui.py`; reads it from
`artifacts/transplant/opentui-bionic/libopentui.so`).

Carved from a working Hope2333 native release binary
(`opencode 1.18.30` for Termux, single ELF `usr/bin/opencode`) and validated
with `swap_tui.has_ffi_guard` (`clamp=6 csel_vs=12`):

- ELF 64-bit LSB shared object, ARM aarch64, for Android 24, NDK r29
- `NEEDED libm.so, libc.so, libdl.so`, `SONAME libopentui.so`
- sha256: `bfc631c84748c63cdd27a8d86c3b3c53d3f6970f1fd376cdb2bb1b7a710e1811`
- size: 5878192 bytes

## `libopencode-crhandler.so`

Seccomp hardening shim (`tools/shim/sigsys_handler.c` compiled for
aarch64-linux-android by Termux clang), applied by
`tools/transplant/crhandler_patch.py` which rewrites the product's dynamic
section so this shim is the first `DT_NEEDED` entry and adds
`DT_RUNPATH $ORIGIN/../lib/opencode` (no env vars, no LD_PRELOAD).

Building it in CI would need the Android NDK; instead it is built once
on-device (`make seccomp-harden`) and committed here.

- ELF 64-bit LSB shared object, ARM aarch64, for Android 24, NDK r29
- `NEEDED libdl.so, libc.so`
- sha256: `ebf59e44e737f2ed4624d6625ca207cd1090facf24a2c9717c6eab0a643a2fc6`
- size: 8104 bytes

## Maintenance

This file is opencode-version-independent in practice across 1.18.x
(same OpenTUI ABI), but the swap is equal-length: `swap_tui.py` refuses an
incoming lib larger than the target version's embedded slot. If a future
opencode version fails the swap (`tui:absent` in `report.json`), rebuild with
`tools/transplant/build-libopentui.sh` (Termux, zig + NDK recipe) and replace
this file, keeping the guard check green.

`libopencode-crhandler.so` only needs rebuilding if `tools/shim/sigsys_handler.c`
changes; run `make seccomp-harden VER=<ver>` on Termux and copy the result here.
