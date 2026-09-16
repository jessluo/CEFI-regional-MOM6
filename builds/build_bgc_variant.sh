#!/usr/bin/env bash
#
# Build one BGC variant of MOM6SIS2 and archive it under builds/exec/.
#
#   ./build_bgc_variant.sh cobalt        standard COBALT   (ocean_BGC dev/cefi)
#   ./build_bgc_variant.sh ecocobalt     eco-COBALT        (jessluo feature/gz-cobalt-merge)
#   ./build_bgc_variant.sh <v> --full    force the full linux-build.bash driver
#
# Why this exists
# ---------------
# There is no compile-time switch for the biogeochemistry: the whole of
# src/ocean_BGC/generic_tracers is compiled unconditionally, and
# linux-build.bash hardcodes srcdir=$abs_rootdir/../src. So each BGC variant is
# a different src/ocean_BGC branch and therefore a different executable.
#
# Rather than keeping three full build trees (which would also rebuild the
# BGC-independent FMS library three times), this builds in place and archives
# the executable. A variant that ADDS source files needs a full rebuild so
# mkmf regenerates path_names -- that requirement is now baked in per variant
# below (NEEDS_FULL), not left to the caller to remember. Both ecocobalt and
# devecocobalt add generic_bottom_layer_diags.F90 (merged in from upstream
# ocean_BGC dev/cefi on 2026-09-15); cobalt predates that file.
#
# Environment overrides: MACHINE, PLATFORM, BUILD_TYPE.
#
set -euo pipefail

VARIANT="${1:-}"
FULL="${2:-}"
[ -n "$VARIANT" ] || { sed -n '3,8p' "$0" | sed 's/^# \?//'; exit 1; }

MACHINE="${MACHINE:-mac-m1}"
PLATFORM="${PLATFORM:-osx-gnu}"
BUILD_TYPE="${BUILD_TYPE:-repro}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BGC="$ROOT/src/ocean_BGC"
BUILDDIR="$ROOT/builds/build/${MACHINE}-${PLATFORM}/ocean_ice/${BUILD_TYPE}"
EXECDIR="$ROOT/builds/exec"

FORK_URL="https://github.com/jessluo/cefi_ocean_BGC.git"

# 'cobalt' is dev/cefi PLUS the BLING FMS_co2calc zt fix (198aad7), which is what
# the station and BLING cases were actually validated against. Bare dev/cefi
# (5760648) would silently drop that fix.
case "$VARIANT" in
    cobalt)       REMOTE=jessluo REF=bugfix/BLING_FMSco2calc_call NEEDS_FULL=no  ;;
    ecocobalt)    REMOTE=jessluo REF=feature/gz-cobalt-merge      NEEDS_FULL=yes ;;
    # dev/eco-cobalt is the DVM work WITHOUT the GZ-COBALT tunicates: 12 new
    # tracers instead of 21, NUM_ZOO = 5, no named group constants, no does_dvm.
    # Kept as its own variant so the branch can be validated before the gz merge.
    devecocobalt) REMOTE=jessluo REF=dev/eco-cobalt              NEEDS_FULL=yes ;;
    *) echo "unknown variant '$VARIANT' (expected: cobalt, ecocobalt, devecocobalt)" >&2; exit 1 ;;
esac

# The fork is a local-only remote on purpose. .gitmodules must keep pointing at
# the upstream NOAA-CEFI URL, which is what everyone else clones.
if ! git -C "$BGC" remote get-url jessluo >/dev/null 2>&1; then
    echo "adding 'jessluo' remote to src/ocean_BGC"
    git -C "$BGC" remote add jessluo "$FORK_URL"
fi

echo "== fetching $REMOTE/$REF =="
if ! git -C "$BGC" fetch "$REMOTE" "$REF"; then
    # Offline fallback: the merge branch also lives in a sibling clone.
    FALLBACK="$ROOT/../cbed/cefi_ocean_BGC"
    if [ -d "$FALLBACK/.git" ]; then
        echo "network fetch failed; trying local clone $FALLBACK"
        git -C "$BGC" fetch "$FALLBACK" "$REF"
    else
        echo "could not fetch $REMOTE/$REF" >&2; exit 1
    fi
fi
git -C "$BGC" checkout --detach --quiet FETCH_HEAD
SHA=$(git -C "$BGC" rev-parse HEAD)
echo "src/ocean_BGC now at $SHA"

echo "== building =="
if [ "$FULL" = "--full" ] || [ "$NEEDS_FULL" = yes ] || [ ! -f "$BUILDDIR/Makefile" ]; then
    "$ROOT/builds/linux-build.bash" -m "$MACHINE" -p "$PLATFORM" -t "$BUILD_TYPE" -f mom6sis2
else
    [ -f "$ROOT/builds/$MACHINE/$PLATFORM.env" ] && . "$ROOT/builds/$MACHINE/$PLATFORM.env"
    make -C "$BUILDDIR" -j NETCDF=4 $( [ "$BUILD_TYPE" = repro ] && echo REPRO=1 ) \
         $( [ "$BUILD_TYPE" = debug ] && echo DEBUG=1 ) MOM6SIS2
fi

echo "== archiving =="
mkdir -p "$EXECDIR"
cp -pf "$BUILDDIR/MOM6SIS2" "$EXECDIR/MOM6SIS2.$VARIANT"
{
    echo "variant      : $VARIANT"
    echo "built        : $(date -u +%FT%TZ)"
    echo "machine      : ${MACHINE}-${PLATFORM} ${BUILD_TYPE}"
    echo "superproject : $(git -C "$ROOT" rev-parse HEAD) ($(git -C "$ROOT" rev-parse --abbrev-ref HEAD))"
    echo "ocean_BGC    : $SHA  <- $REMOTE/$REF"
    echo "MOM6         : $(git -C "$ROOT/src/MOM6" rev-parse HEAD)"
    echo "SIS2         : $(git -C "$ROOT/src/SIS2" rev-parse HEAD)"
    echo "FMS          : $(git -C "$ROOT/src/FMS" rev-parse HEAD)"
    echo "cppdefs      : $(tr '\n' ' ' < "$BUILDDIR/.MOM6SIS2.cppdefs" 2>/dev/null)"
} > "$EXECDIR/MOM6SIS2.$VARIANT.provenance"

echo
echo "wrote builds/exec/MOM6SIS2.$VARIANT"
echo "NOTE: src/ocean_BGC is left detached at $SHA ($VARIANT)."
echo "      'git status' in the superproject will show ' M src/ocean_BGC'. That is expected."
echo "      'git submodule update' would silently revert it and invalidate this build."
