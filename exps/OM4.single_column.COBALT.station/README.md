# OM4.single_column.COBALT.station

A relocatable single-column MOM6-SIS2-COBALT case: **year-long runs at any
open-ocean location**, given only an `ocean_hgrid.nc`.

This is the sibling of `exps/OM4.single_column.COBALT`, which is left untouched
as the short CI regression test. Use whichever fits:

| | `OM4.single_column.COBALT` | `OM4.single_column.COBALT.station` (here) |
|---|---|---|
| Purpose | regression test | science runs |
| Location | BATS only | any station |
| Max length | ~3.6 days (forcing runs out) | full year 2004 |
| Fe / N deposition | off (near-zero constants) | **on** (global climatology) |
| Reference answers | `ref/ocean.stats` | none — not a regression test |

## Running

```bash
export PATH="$HOME/work/FRE-NCtools/build/bin:$PATH"   # FRE-NCtools
./setup_station.sh BATS 31.6667 -64.1667               # build + link the grid
ln -sfn input.nml_1yr input.nml                        # or input.nml_2day
mpirun -np 1 ../../builds/build/<machine>-<platform>/ocean_ice/repro/MOM6SIS2
```

`setup_station.sh <name> <lat> <lon> [bottom_depth_m]` builds a 0.4-degree,
4x4-cell box centred on the station (same geometry as the CI case) and links
the grid into `INPUT/`. Grids are kept per-station under `INPUT/grids/<name>/`,
so switching stations is just another call to the script. Default bottom depth
is 4000 m; pass a fourth argument for something else.

Verified stations: BATS (31.6667, -64.1667) and HOT (22.75, -158.0, 4800 m).
Both give 0.000000% tiling error and run clean with no truncations.

## Prerequisite: an upstream bug in the `atmos_null` submodule

This case (and the regression case, and any other MOM6-SIS2 configuration)
will abort on the **first coupled timestep** if the model was built with
Fortran bounds checking enabled:

```
Fortran runtime error: Index '2' of dimension 3 of array 'atm%tr_bot'
outside of expected range (1:1)
```

`src/atmos_null/atmos_model.F90` calls `register_tracers(MODEL_LAND, ...)` and
then uses that count to allocate the **atmosphere's** `tr_bot`,
`Surf_Diff%dflux_tr` and `delta_tr`. The field table declares one land tracer
(`sphum`) but four atmospheric ones (`sphum`, `liq_wat`, `ice_wat`,
`cld_amt`), so the coupler — which loops over the atmospheric count in
`atm_land_ice_flux_exchange.F90`, pairing it with
`get_tracer_names(MODEL_ATMOS, ...)` — indexes past the end of a
one-element array. The fix is to register `MODEL_ATMOS` instead (and to import
`MODEL_ATMOS` rather than `MODEL_LAND` at the top of the file).

**Why this is not already fixed:** `builds/docker/linux-gnu.mk` has
`-fbounds-check` commented out of `FFLAGS_DEBUG`, and CI runs the `debug`
build, so CI never trips it. The out-of-bounds access still happens there —
silently. `builds/macOS/osx-gnu.mk`, by contrast, ships
`FFLAGS_REPRO = -O1 -fbounds-check`, so anyone following the macOS build
instructions hits it immediately.

Two things to know: `src/atmos_null` is a **submodule**, so `git submodule
update` will silently revert a local fix — re-apply it after any submodule
sync. And the fix belongs upstream at
https://github.com/NOAA-GFDL/atmos_null, not in this repository; it is
deliberately not part of this experiment's commit.

## Why this case can relocate and the regression case cannot

Two independent things had to change.

**1. Physical T/S.** The regression case sets
`INIT_LAYERS_FROM_Z_FILE = False` and reads `MOM_IC.nc`, which is *index*-matched
to the BATS grid — it is read without interpolation, so it only works on a grid
of exactly those dimensions at exactly that location. Here it is `True`, so MOM6
interpolates global WOA13 monthly climatology onto whatever grid is present.
The filenames were already correct in `MOM_input`; they were simply inert.

**2. BGC tracers.** Less obvious. The regression `field_table` has ~79
`*_src_file` entries pointing at `bgc_woa_esper_ics_..._BATS.nc`, but they are
**never used**: `enforce_src_info = f` sets `requires_src_info = .false.` for
every tracer, and that flag is the branch condition in
`MOM_generic_tracer.F90` (`initialize_MOM_generic_tracer`) that decides whether
a tracer initialises from its source file. With it false every tracer falls
through to `GENERIC_TRACER_IC_FILE` — i.e. `MOM_IC.nc` again.

Here `enforce_src_info = t`, which routes tracers through
`MOM_initialize_tracer_from_Z`. That interpolates each tracer's global Z-space
source onto the model grid, and `GENERIC_TRACER_IC_FILE` is not set at all.

## Initial conditions

56 tracers come from global sources:

| Source | Tracers |
|---|---|
| `woa13_all_{n,o,p,i}_annual_01.nc` | no3, o2, po4, sio4 |
| `GLODAPv2.2016b.oi-filled.*.nc` | alk, dic |
| `GLODAPv1.abiotic.filled.*.nc` | abiotic carbon |
| `cobaltv3_tracer_source.nc` | the remaining ~50 |

`cobaltv3_tracer_source.nc` (global, 360x180, 35 z-levels) replaced the
2023-era `init_ocean_cobalt.res.nc` entirely. Its shared fields are bitwise
identical to that file and it loses nothing, so it is a strict superset --
worth checking again if either file is ever regenerated.

### Two things about this IC file you should know

**The medium-phytoplankton fields are seeds, not climatology.** In the
delivered file `nmd` is a bitwise copy of `nsm`, `femd` of `fesm`, and `simd`
of `silg`. That gets the group off zero -- which is essential, because zero
biomass is an absorbing state for a phytoplankton group and it could never
grow -- but the medium group redistributes over the first weeks rather than
starting at its true biomass.

**The phosphorus fields were derived here, not delivered.** As shipped,
`psm`, `pmd`, `plg` and `pdi` were bitwise copies of their *nitrogen*
counterparts, i.e. P:N = 1.0 against a Redfield expectation of 0.0625 -- a 16x
phosphorus overestimate in every phytoplankton group. They were recomputed
in place as N/16 and the file's `long_name`/`comment` attributes updated to
record this; the untouched original is `cobaltv3_tracer_source.nc.orig`.
Because they are a uniform 1/16 of N, they carry **no spatial P:N structure**.
If you need P:N variability it has to come from a properly generated source.

24 tracers still **cold-start** (`_requires_src_info = f`,
`_requires_restart = f`): the `*_btf` bottom fluxes and the acclimation /
memory variables (`irr_aclm*`, `pcmlim_aclm_*`, `mu_mem_*`, `irr_mem`). These
are empty in `cobaltv3_tracer_source.nc` too, and zero is legitimate for them
-- bottom fluxes accumulate from zero and the memory variables relax to
ambient within days.

Verification after a 2-day run at BATS: `nmd` mean 4.57e-08 vs `nsm` 4.01e-08.
They start bitwise identical, so a 14% divergence in two days confirms the
medium group is a live prognostic variable. `pmd`/`nmd` drifts from the
imposed 0.0625 to 0.0513 over the same period, confirming the phosphorus
evolves under its own dynamics.

Sanity check at BATS: WOA-interpolated initial state reproduces `MOM_IC.nc`'s
mean T (6.2462 C), mean S (35.2427) and total mass (6.97073E+15) to printed
precision.

## Forcing and deposition

JRA55-do, full year 2004: 2930 3-hourly records, global 640x320, `gregorian`.
The regression case's files are the first 31 records of these same files.

Atmospheric deposition of Fe, lithogenic dust and N is **enabled** from global
12-month climatologies. Note these are **pre-industrial** (`*_PI.nc`,
`depflux_total.mean.1860.nc`). Upstream CEFI has moved to ESM4 1993-2014
present-day climatologies (see `exps/NWA12.COBALT/data_table`), which also
carry wet Fe and dust deposition that these files lack. Swap if you need
present-day forcing. Atmospheric CO2 is a constant 360 ppm in `data_table`.

## Input files -- how to get them

Everything under `INPUT/` is a symlink into `exps/datasets/station_1d/`, which
is **not** tracked in this repository. A fresh clone therefore has broken
symlinks until that directory is populated.

These files are not part of the 1D CI dataset
(`1d_ci_datasets.tar.gz`), and they are not part of the CEFI dataset
distribution either. **Contact Jessica Luo (@jessluo) for access.**

What is needed in `exps/datasets/station_1d/`:

| Files | Purpose | Size |
|---|---|---|
| 9 x JRA55-do `*.padded.nc` | full-year 2004 forcing, 2930 3-hourly records | ~12 GB |
| `woa13_decav_{ptemp,s}_monthly_fulldepth_01.nc` | global T/S climatology | |
| `woa13_all_{n,o,p,i}_annual_01.nc` | no3, o2, po4, sio4 | |
| `GLODAPv2.2016b.oi-filled.*.nc`, `GLODAPv1.abiotic.filled.*.nc` | alk, dic, abiotic carbon | |
| `cobaltv3_tracer_source.nc` | the remaining COBALT tracers | 744 MB |
| `Soluble_Fe_Flux_PI.nc`, `Mineral_Fe_Flux_PI.nc`, `depflux_total.mean.1860.nc` | Fe / dust / N deposition | |
| `seawifs-clim-*.nc` | chlorophyll climatology | |

On the machine this case was developed on, `exps/datasets/station_1d/` is a
directory of symlinks into a separate checkout
(`model_checkouts/MOM6_OBGC_examples`) rather than copies, so nothing is
duplicated; `cobaltv3_tracer_source.nc` is the one real file there. If that
checkout moves, relinking that single directory is enough -- nothing in this
experiment needs to change.
