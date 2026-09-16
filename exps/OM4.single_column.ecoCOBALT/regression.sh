#!/usr/bin/env bash
#
# Regression test for single-column eco-COBALT.
#
#   ./regression.sh              run both checks
#   ./regression.sh --update-ref run the 48-hour case and overwrite ref/ocean.stats
#
# Two independent checks, mirroring ../OM4.single_column.BLING/regression.sh:
#
#   1. Restart reproducibility. One 48-hour run must give bitwise-identical
#      restart files to a 24-hour run continued for another 24 hours. This is
#      machine independent and catches state that eco-COBALT fails to
#      checkpoint -- in particular the 17 tracers carrying requires_restart = f.
#
#   2. Reference answer. ocean.stats from the 48-hour run must match
#      ref/ocean.stats to within REL_TOL.
#
# NOTE: ref/ocean.stats here is NOT comparable to the standard COBALT station
# case. The merge changes the shared vertical sinking solver in
# generic_tracer_utils.F90 for every sinking tracer, so eco-COBALT is not
# expected to reproduce COBALT bitwise. Generate this reference fresh.
#
# Override MACHINE / PLATFORM / BUILD_TYPE for another system, EXE to point at a
# different executable, REL_TOL to loosen check 2.
#
set -u

EXPDIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$EXPDIR/../.." && pwd)"

MACHINE="${MACHINE:-mac-m1}"
PLATFORM="${PLATFORM:-osx-gnu}"
BUILD_TYPE="${BUILD_TYPE:-repro}"
REL_TOL="${REL_TOL:-1.0e-9}"
EXE="${EXE:-$ROOT/builds/exec/MOM6SIS2.ecocobalt}"

RESTART_FILES=(MOM.res.nc ice_cobalt.res.nc ice_model.res.nc ocean_cobalt_airsea_flux.res.nc)

cd "$EXPDIR" || exit 1
[ -x "$EXE" ] || {
    echo "No executable at $EXE"
    echo "Build it with: $ROOT/builds/build_bgc_variant.sh ecocobalt"
    exit 1
}

# Pre-flight: the executable must have been built from the ocean_BGC source this
# experiment's field_table and COBALT_override were written against. Running the
# eco field_table against a standard-COBALT binary is the easiest mistake to make
# and produces silently wrong results rather than an error.
PROV="${EXE}.provenance"
if [ -f BGC_SOURCE ] && [ -f "$PROV" ]; then
    want=$(awk -F'= *' '/^commit/{print $2}' BGC_SOURCE | tr -d ' ')
    have=$(awk '/^ocean_BGC/{print $3}' "$PROV")
    if [ -n "$want" ] && [ -n "$have" ] && [ "$want" != "$have" ]; then
        echo "BGC source mismatch:"
        echo "  BGC_SOURCE wants : $want"
        echo "  $(basename "$EXE") was built from : $have"
        echo "Rebuild with: $ROOT/builds/build_bgc_variant.sh ecocobalt"
        echo "(or set EXE=... if you know the difference is intentional)"
        exit 1
    fi
fi
echo "Executable: $EXE"
[ -f "$PROV" ] && grep '^ocean_BGC' "$PROV"

# shellcheck source=/dev/null
[ -f "$ROOT/builds/$MACHINE/$PLATFORM.env" ] && source "$ROOT/builds/$MACHINE/$PLATFORM.env"

# run <tag> <input.nml variant> <diag_table variant>
run() {
    local tag="$1"
    echo "  running $tag ..."
    rm -rf RESTART; mkdir -p RESTART logs
    ln -fs "$2" input.nml
    ln -fs "$3" diag_table
    if ! mpirun -np 1 "$EXE" > "logs/$tag.out" 2> "logs/$tag.err"; then
        echo "  $tag FAILED -- see logs/$tag.out and logs/$tag.err"
        tail -20 "logs/$tag.err"
        return 1
    fi
    rm -rf "RESTART_$tag"
    mv RESTART "RESTART_$tag"
    mv ocean.stats "RESTART_$tag/" 2>/dev/null
    return 0
}

echo "== 48-hour run =="
rm -f INPUT/*.res.nc INPUT/coupler.res
run 48hr input.nml_48hr diag_table_ecoCOB_min || exit 1

if [ "${1:-}" = "--update-ref" ]; then
    mkdir -p ref
    cp RESTART_48hr/ocean.stats ref/ocean.stats
    echo "Updated ref/ocean.stats from the 48-hour run."
    exit 0
fi

echo "== 24-hour run =="
rm -f INPUT/*.res.nc INPUT/coupler.res
run 24hr input.nml_24hr diag_table_ecoCOB_min || exit 1

echo "== 24-hour restart run =="
rm -f INPUT/*.res.nc INPUT/coupler.res
cp RESTART_24hr/*.res.nc RESTART_24hr/coupler.res INPUT/
run 24hr_rst input.nml_24hr_rst diag_table_ecoCOB_min || exit 1

status=0

echo
echo "Check 1: restart reproducibility (48hr vs 24hr+24hr)"
for f in "${RESTART_FILES[@]}"; do
    if [ ! -f "RESTART_48hr/$f" ] || [ ! -f "RESTART_24hr_rst/$f" ]; then
        echo "  MISSING  $f"; status=1; continue
    fi
    if diff -q <(ncdump "RESTART_48hr/$f") <(ncdump "RESTART_24hr_rst/$f") > /dev/null; then
        echo "  identical  $f"
    else
        echo "  DIFFERS    $f"; status=1
    fi
done

echo
echo "Check 2: ocean.stats vs ref/ocean.stats (rel tol $REL_TOL)"
if [ -f ref/ocean.stats ]; then
    python3 compare_ocean_stats.py ref/ocean.stats RESTART_48hr/ocean.stats "$REL_TOL" || status=1
else
    echo "  no ref/ocean.stats -- create one with ./regression.sh --update-ref"
    status=1
fi

echo
if [ $status -eq 0 ]; then
    echo "REGRESSION TEST PASSED"
else
    echo "REGRESSION TEST FAILED"
fi
exit $status
