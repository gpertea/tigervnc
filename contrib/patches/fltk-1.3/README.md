# FLTK 1.3 Windows clipboard listener patch

TigerVNC currently requires FLTK 1.3 (`CMakeLists.txt` rejects other minor
versions). On Windows, FLTK 1.3 monitors clipboard changes through the legacy
`SetClipboardViewer()` chain. A program that fails to forward
`WM_DRAWCLIPBOARD` can prevent every later viewer in that chain from seeing
clipboard updates.

`0001-win32-use-modern-clipboard-listener.patch` changes the FLTK Windows
backend to use `AddClipboardFormatListener()` and `WM_CLIPBOARDUPDATE` when
available. The functions are resolved dynamically, and the existing viewer
chain remains as a fallback for older Windows versions.

This is maintained here as a TigerVNC build dependency patch. It is separate
from TigerVNC's own clipboard deferral change, which handles a notification
that arrived while clipboard text was temporarily unavailable.

## Patch provenance

- Upstream: <https://github.com/fltk/fltk>
- FLTK tag: `release-1.3.11`
- FLTK commit: `702172a951a2bb4f25afe31008ef3fcbb5bfb92f`
- Patched file: `src/Fl_win32.cxx`

Keeping a unified diff rather than a copied source file makes the upstream
version and the local changes explicit.

## Apply and build

The following example assumes an MSYS2 UCRT64 shell and sibling FLTK and
TigerVNC source directories:

```sh
fltk_src=/c/src/fltk
fltk_build="$fltk_src/build-tigervnc"
tigervnc_src=/c/src/tigervnc

git -C "$fltk_src" checkout release-1.3.11
git -C "$fltk_src" apply \
  "$tigervnc_src/contrib/patches/fltk-1.3/0001-win32-use-modern-clipboard-listener.patch"

cmake -S "$fltk_src" -B "$fltk_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPTION_BUILD_SHARED_LIBS=OFF \
  -DFLTK_BUILD_TEST=OFF \
  -DFLTK_BUILD_EXAMPLES=OFF \
  -DOPTION_USE_SYSTEM_LIBJPEG=ON \
  -DOPTION_USE_SYSTEM_LIBPNG=ON \
  -DOPTION_USE_SYSTEM_ZLIB=ON
cmake --build "$fltk_build" --target fltk fltk_images

fltk_build_win=$(cygpath -m "$fltk_build")
cmake -S "$tigervnc_src" -B "$tigervnc_src/build-windows" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_STATIC=ON \
  -DBUILD_VIEWER=ON \
  -DFLTK_DIR="$fltk_build_win" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$fltk_build_win/lib"
cmake --build "$tigervnc_src/build-windows" --target vncviewer
```

The personal TigerVNC branch also includes the Brotli libraries required when
statically linking the current MSYS2 GnuTLS package.

## Regression helper

`contrib/tests/windows/clipboard-chain-blackhole.c` deliberately joins the
legacy clipboard-viewer chain and does not forward `WM_DRAWCLIPBOARD`. It
removes itself cleanly after 12 seconds.

Build it from MSYS2 UCRT64:

```sh
gcc -O2 -Wall -Wextra -mwindows \
  contrib/tests/windows/clipboard-chain-blackhole.c \
  -o clipboard-chain-blackhole.exe -luser32
```

Test procedure:

1. Start the VNC viewer.
2. Start `clipboard-chain-blackhole.exe` so it joins ahead of the viewer.
3. Copy a unique text marker in a local Windows application while the viewer
   is unfocused.
4. Focus the viewer and request or paste the remote clipboard before the
   helper's 12-second timer expires.

The legacy FLTK build misses the marker. The patched FLTK build receives the
independent `WM_CLIPBOARDUPDATE` notification and transfers it normally.

On 2026-08-06 this test produced `NO_MATCH` with the original FLTK listener
and `MATCH` with the patched listener. The same original viewer recovered once
the helper exited and repaired the legacy chain.
