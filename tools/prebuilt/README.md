# Prebuilt bionic libopentui.so (self-serve CI)

`libopentui-bionic.so` is the Android/Bionic build of OpenTUI's renderer that
`tools/transplant/transplant.py all` equal-length-swaps into the transplanted
ELF (`swap_tui.py`; step 8 reads it from
`artifacts/transplant/opentui-bionic/libopentui.so`).

## Provenance

Carved from a working Hope2333 native release binary
(`opencode 1.18.30` for Termux, single ELF `usr/bin/opencode`) and validated
with `swap_tui.has_ffi_guard` (`clamp=6 csel_vs=12`):

- ELF 64-bit LSB shared object, ARM aarch64, for Android 24, NDK r29
- `NEEDED libm.so, libc.so, libdl.so`, `SONAME libopentui.so`
- sha256: `bfc631c84748c63cdd27a8d86c3b3c53d3f6970f1fd376cdb2bb1b7a710e1811`
- size: 5878192 bytes

## Maintenance

This file is opencode-version-independent in practice across 1.18.x
(same OpenTUI ABI), but the swap is equal-length: `swap_tui.py` refuses an
incoming lib larger than the target version's embedded slot. If a future
opencode version fails the swap (`tui:absent` in `report.json`), rebuild with
`tools/transplant/build-libopentui.sh` (Termux, zig + NDK recipe) and replace
this file, keeping the guard check green.
