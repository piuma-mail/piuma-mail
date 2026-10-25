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

Drop this copy when upstream has the same fixes.
