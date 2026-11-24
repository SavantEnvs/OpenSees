#!/usr/bin/env bash
# mayhem/build.sh — build OpenSees (sanitized) and the Tcl-driven fuzz harnesses.
#
# 1) Configure + build upstream's CMake `OpenSees` target in build-mayhem/ (gitignored by upstream's
#    `build*` rule) with $SANITIZER_FLAGS $DEBUG_FLAGS, so every OpenSees library is instrumented.
# 2) Re-use CMake's own link line for the OpenSees executable (build-mayhem/CMakeFiles/OpenSees.dir/
#    link.txt), swapping tclAppInit.cpp's main() for each harness object, to link every fuzzer and its
#    -standalone reproducer against exactly the libraries upstream links.
# Upstream's Clang branch prefers static archives (CMAKE_FIND_LIBRARY_SUFFIXES ".a"), which drags in
# static libcurl/libcrypto via HDF5; the cache presets above point those at the shared system libs.
# FindTCL insists on Tk although OpenSees never uses it: TK_* point at Tcl to satisfy the check.
# 3) The functional oracle (mayhem/test.sh) runs the sanitized `OpenSees` interpreter itself on
#    known-answer scripts; a second, unsanitized build of ~6000 TUs would double an already long build.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export CC CXX

cd "$SRC"
B="$SRC/build-mayhem"
LIBDIR=/usr/lib/x86_64-linux-gnu


# UBSan's vptr check (C++ only) makes every polymorphic cast reference the class's typeinfo; many
# OpenSees interface classes (SocketAddress, DesignVariable, ...) never define a key function, so
# their typeinfo is never emitted and the link fails. Only `vptr` is relaxed; the rest of UBSan and
# ASan stay on and halting.
SAN_CXX="$SANITIZER_FLAGS"
[ -z "$SANITIZER_FLAGS" ] || SAN_CXX="$SANITIZER_FLAGS -fno-sanitize=vptr"

# SanCov on the whole project (not only the harness), so the fuzzer sees OpenSees' edges.
COV_FLAGS="-fsanitize=fuzzer-no-link"

cmake -S "$SRC" -B "$B" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-O1 $SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_CXX_FLAGS="-O1 $SAN_CXX $COV_FLAGS $DEBUG_FLAGS" \
  -DCMAKE_C_FLAGS_RELEASE="" -DCMAKE_CXX_FLAGS_RELEASE="" \
  -DCMAKE_Fortran_FLAGS="-O1" -DCMAKE_Fortran_FLAGS_RELEASE="" \
  -DTCL_LIBRARY="$LIBDIR/libtcl8.6.so" -DTCL_INCLUDE_PATH=/usr/include/tcl8.6 \
  -DTCL_TCLSH=/usr/bin/tclsh8.6 \
  -DTK_LIBRARY="$LIBDIR/libtcl8.6.so" -DTK_INCLUDE_PATH=/usr/include/tcl8.6 \
  -DHDF5_PREFER_PARALLEL=OFF \
  -DHDF5_C_LIBRARY_hdf5="$LIBDIR/hdf5/serial/libhdf5.so" \
  -DHDF5_C_LIBRARY_crypto="$LIBDIR/libcrypto.so" -DHDF5_C_LIBRARY_curl="$LIBDIR/libcurl.so" \
  -DHDF5_C_LIBRARY_sz="$LIBDIR/libsz.so" -DHDF5_C_LIBRARY_m="$LIBDIR/libm.so" \
  -DHDF5_C_LIBRARY_dl="$LIBDIR/libdl.so.2" -DHDF5_C_LIBRARY_pthread="$LIBDIR/libpthread.so.0"
cmake --build "$B" --target OpenSees -j"$MAYHEM_JOBS"

# Link line of upstream's interpreter: "<cxx> <flags> <objects> -o OpenSees <libs>"
LINK="$(cat "$B/CMakeFiles/OpenSees.dir/link.txt")"
OBJS="$(printf '%s\n' $LINK | grep '\.o$' | grep -v 'tclAppInit\.cpp\.o$' | sed "s|^|$B/|" | tr '\n' ' ')"
LIBS="$(printf '%s\n' $LINK | sed -n '/^OpenSees$/,$p' | tail -n +2 | tr '\n' ' ')"
mkdir -p "$B/bin"; cd "$B"   # link.txt paths are relative to the build dir

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/standalone_main.o"
$CXX $SAN_CXX $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"

for h in fuzz_tcl_script fuzz_uniaxial_material fuzz_path_timeseries; do
  $CXX -O1 $SAN_CXX $DEBUG_FLAGS -std=c++17 -I/usr/include/tcl8.6 -I"$SRC/SRC/tcl" \
    -c "$SRC/mayhem/harnesses/$h.cc" -o "$B/$h.o"
  $CXX $SAN_CXX $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$B/$h.o" "$B/lsan_off.o" $OBJS $LIBS \
    -o "$B/bin/$h"
  $CXX $SAN_CXX $DEBUG_FLAGS "$B/standalone_main.o" "$B/$h.o" "$B/lsan_off.o" $OBJS $LIBS \
    -o "$B/bin/$h-standalone"
done
cp "$B/OpenSees" "$B/bin/OpenSees"
echo "build.sh: done"
