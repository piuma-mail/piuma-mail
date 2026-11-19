# fxtranslate 0.5.0, Piuma Mail's copy

Taken from crates.io (fxtranslate 0.5.0, MPL-2.0, see LICENSE; the changed files stay under MPL-2.0) and patched in
a few places. Each change is marked "Piuma Mail:" in the source.

- `build.rs`, `src/gemmology_shim.cpp`: arm64 uses the plain NEON kernel
  instead of i8mm. NEON is on every arm64 CPU, so phones without i8mm don't
  crash, and translation is much faster than the scalar kernel. x86_64 keeps the
  scalar kernel, since the AVX2 one has no runtime check and doesn't build with
  MSVC.
- `src/gemmology_shim.cpp`: `posix_memalign` instead of `aligned_alloc`,
  which Android only has from API 28.
- `build.rs`: on Android the C++ runtime is linked statically (`c++_static`
  and `c++abi`), since the app ships no `libc++_shared.so`.
- `src/spm.rs`: byte-fallback pieces (`<0x7C>`) decode to their byte, so "|"
  and other rare characters come out as themselves.
- `Cargo.toml`, `src/cache.rs`: ruzstd 0.9.1 instead of 0.7, which fixes a
  decompression bomb (RUSTSEC-2026-0344); its decoder is now in `decoding`.

Drop this copy when upstream has the same fixes.

## Upstream version

Based on **fxtranslate 0.5.0** from crates.io (the `version` in this folder's `Cargo.toml`, which
stays the upstream one). Being a path dependency, this copy is invisible to RustSec and Dependabot:
the "Upstream versions" workflow (`.github/workflows/upstream-watch.yml`) compares it with the latest
crates.io release every Monday and opens an issue when they differ. Moving to a new upstream version:
replace the files, re-apply every "Piuma Mail:" change above, update this section and
`THIRD_PARTY.md`, and run `python3 tools/gen_rust_licenses.py`.
