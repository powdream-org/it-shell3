#!/usr/bin/env bash
# Run kcov coverage for all modules. Executed inside the zig-kcov Docker container.
# Expects: TEST_MODULES env var (space-separated module directory paths)
# Outputs: coverage/<module>/index.html per module, coverage/merged/index.html
set -e

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

COVERAGE_DIR=coverage
rm -rf $COVERAGE_DIR && mkdir -p $COVERAGE_DIR

for MODULE_DIR in $TEST_MODULES; do
  MODULE=$(basename $MODULE_DIR)
  echo "=== $MODULE: building tests ==="

  # All modules use ReleaseSafe for kcov — Debug binaries are too large
  # for kcov's DWARF parser. libitshell3 also needs -Dghostty-simd=false.
  BUILD_ARGS="-Doptimize=ReleaseSafe"
  if [ "$MODULE" = "libitshell3" ]; then
    BUILD_ARGS="$BUILD_ARGS -Dghostty-simd=false"
  fi

  # Clean zig cache to force fresh binary creation with known timestamps
  rm -rf $MODULE_DIR/.zig-cache

  # Build test binaries — fresh cache ensures all binaries are new
  (cd $MODULE_DIR && zig build test $BUILD_ARGS --summary none)

  # Find all test binaries produced by this build
  TEST_BINS=$(find $MODULE_DIR/.zig-cache/o -name test -type f -executable 2>/dev/null)

  if [ -z "$TEST_BINS" ]; then
    echo "ERROR: no test binary for $MODULE"
    continue
  fi

  BIN_IDX=0
  for TEST_BIN in $TEST_BINS; do
    echo "=== $MODULE: running kcov on binary $BIN_IDX ==="
    kcov --include-path=$WORKSPACE_DIR/$MODULE_DIR/src/ \
      --replace-src-path=$WORKSPACE_DIR/$MODULE_DIR/src:$MODULE_DIR/src \
      $COVERAGE_DIR/${MODULE}_part_${BIN_IDX} "$TEST_BIN" 2>/dev/null || true
    BIN_IDX=$((BIN_IDX + 1))
  done

  # Merge per-binary reports into one module report
  if [ "$BIN_IDX" -gt 1 ]; then
    PARTS=""
    for i in $(seq 0 $((BIN_IDX - 1))); do
      if [ -d "$COVERAGE_DIR/${MODULE}_part_${i}" ]; then
        PARTS="$PARTS $COVERAGE_DIR/${MODULE}_part_${i}"
      fi
    done
    if [ -n "$PARTS" ]; then
      kcov --merge $COVERAGE_DIR/$MODULE $PARTS 2>/dev/null || true
    fi
  elif [ -d "$COVERAGE_DIR/${MODULE}_part_0" ]; then
    mv $COVERAGE_DIR/${MODULE}_part_0 $COVERAGE_DIR/$MODULE
  fi

  # Clean up part directories
  rm -rf $COVERAGE_DIR/${MODULE}_part_*

  echo "=== $MODULE: done ==="
done

# Merge all module reports
MERGE_ARGS=""
for dir in $TEST_MODULES; do
  MODULE=$(basename $dir)
  if [ -d "$COVERAGE_DIR/$MODULE" ]; then
    MERGE_ARGS="$MERGE_ARGS $COVERAGE_DIR/$MODULE"
  fi
done
if [ -n "$MERGE_ARGS" ]; then
  kcov --merge $COVERAGE_DIR/merged $MERGE_ARGS 2>/dev/null || true
fi

echo
echo "=== Coverage Summary ==="
COVERAGE_NAMES=""
for dir in $TEST_MODULES; do
  COVERAGE_NAMES="$COVERAGE_NAMES $(basename $dir)"
done
COVERAGE_NAMES="$COVERAGE_NAMES merged"
export COVERAGE_NAMES
deno run --allow-read --allow-env $WORKSPACE_DIR/scripts/coverage-summary.ts

echo
echo "HTML report: coverage/merged/index.html"
