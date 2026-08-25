#!/bin/bash
#
# Build the grid/mosaic set for a single-column station and link it into INPUT/.
#
#   usage: ./setup_station.sh <station_name> <latitude> <longitude> [bottom_depth_m]
#   e.g.   ./setup_station.sh BATS   31.6667 -64.1667
#          ./setup_station.sh HOT    22.75  -158.0
#          ./setup_station.sh EQPAC   0.0   -140.0     5000
#
# Requires FRE-NCtools on PATH, e.g.
#   export PATH="$HOME/work/FRE-NCtools/build/bin:$PATH"
#
# Everything else in this experiment is global, so once the grid exists the
# case runs at that location with no further changes.

set -e

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "usage: $0 <station_name> <latitude> <longitude> [bottom_depth_m]" >&2
    exit 1
fi

station="$1"
lat="$2"
lon="$3"
depth="${4:-4000}"

for tool in make_hgrid make_solo_mosaic make_topog make_coupler_mosaic; do
    command -v $tool >/dev/null 2>&1 || {
        echo "ERROR: $tool not found on PATH." >&2
        echo "       export PATH=\"\$HOME/work/FRE-NCtools/build/bin:\$PATH\"" >&2
        exit 1
    }
done

expdir="$(cd "$(dirname "$0")" && pwd)"
griddir="$expdir/INPUT/grids/$station"

# 0.4 deg box centred on the station, 4x4 ocean cells (8x8 supergrid),
# matching the geometry of the CI single-column case.
xmin=$(awk -v v="$lon" 'BEGIN{printf "%.4f", v-0.2}')
xmax=$(awk -v v="$lon" 'BEGIN{printf "%.4f", v+0.2}')
ymin=$(awk -v v="$lat" 'BEGIN{printf "%.4f", v-0.2}')
ymax=$(awk -v v="$lat" 'BEGIN{printf "%.4f", v+0.2}')

echo "Building grid for $station at (${lat}, ${lon}), bottom depth ${depth} m"
rm -rf "$griddir"
mkdir -p "$griddir"
cd "$griddir"

make_hgrid --grid_type regular_lonlat_grid \
           --nxbnd 2 --nybnd 2 \
           --xbnd "$xmin,$xmax" --ybnd "$ymin,$ymax" \
           --nlon 8 --nlat 8 \
           --grid_name ocean_hgrid > make_hgrid.log 2>&1

for m in ocean atmos land; do
    make_solo_mosaic --num_tiles 1 --dir ./ \
                     --mosaic_name ${m}_mosaic --tile_file ocean_hgrid.nc \
                     > make_solo_mosaic_${m}.log 2>&1
done

make_topog --mosaic ocean_mosaic.nc --topog_type rectangular_basin \
           --bottom_depth "$depth" --output ocean_topog.nc \
           > make_topog.log 2>&1

make_coupler_mosaic --atmos_mosaic atmos_mosaic.nc \
                    --land_mosaic land_mosaic.nc \
                    --ocean_mosaic ocean_mosaic.nc \
                    --ocean_topog ocean_topog.nc \
                    --mosaic_name grid_spec --check --verbose \
                    > make_coupler_mosaic.log 2>&1

# Link the freshly built grid into INPUT/, replacing any previous station.
cd "$expdir/INPUT"
for f in ocean_hgrid.nc ocean_topog.nc ocean_mosaic.nc atmos_mosaic.nc \
         land_mosaic.nc land_mask.nc ocean_mask.nc grid_spec.nc \
         atmos_mosaic_tile1Xocean_mosaic_tile1.nc \
         land_mosaic_tile1Xocean_mosaic_tile1.nc ; do
    if [ -e "grids/$station/$f" ]; then
        ln -sfn "grids/$station/$f" "$f"
    else
        echo "WARNING: grids/$station/$f was not produced" >&2
    fi
done
ln -sfn ocean_topog.nc topog.nc

echo "Station '$station' is now active in INPUT/."
echo "Tiling check from make_coupler_mosaic:"
grep -E "tiling error|ocean fraction|land  fraction" "$griddir/make_coupler_mosaic.log" || true
