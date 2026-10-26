#!/usr/bin/env bash
#
# mayhem/build.sh — build the Savo fuzz harness (sanitized, instrumented) and the oracle (`./savo`).
# Runs inside the commit image as `mayhem` in /mayhem; the base image exports the build contract.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized + SanCov-instrumented library objects (everything except main.c), kept apart from the
#    oracle build's `build/` so the two never collide. *.o is gitignored upstream.
CORE="lexer parser global value symtab ast savo lineedit"
OBJDIR="$SRC/mayhem-build"
rm -rf "$OBJDIR"; mkdir -p "$OBJDIR"
OBJS=""
for m in $CORE; do
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1 -Isrc -c "src/$m.c" -o "$OBJDIR/$m.o"
  OBJS="$OBJS $OBJDIR/$m.o"
done

# 2) LeakSanitizer off, linked into every fuzz + standalone binary.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OBJDIR/lsan_off.o"

# 3) The harness: fuzzer binary + a run-once standalone reproducer.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -O1 -Isrc -c mayhem/fuzz_savo.c -o "$OBJDIR/fuzz_savo.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$OBJDIR/fuzz_savo.o" $OBJS "$OBJDIR/lsan_off.o" -lm -o /mayhem/fuzz_savo
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" \
    "$OBJDIR/fuzz_savo.o" $OBJS "$OBJDIR/lsan_off.o" -lm -o /mayhem/fuzz_savo-standalone

# 4) The oracle: upstream's normal `make` (project flags, no sanitizer, no -gdwarf-3) → ./savo,
#    which mayhem/test.sh drives through upstream's golden-file suite.
make clean >/dev/null
make -j"$MAYHEM_JOBS" CFLAGS="-Wall -Wextra -O2 -Isrc $COVERAGE_FLAGS" savo
[ -x "$SRC/savo" ]
