# OM4.single_column.COBALT.station

A relocatable single-column MOM6-SIS2-COBALT configuration. It runs for a full
year at any open-ocean location, given only an `ocean_hgrid.nc`.

## Important: `ROTATION` must follow the station latitude

`MOM_override` in this experiment sets:

```
#override ROTATION = "2omegasinlat"
#override OMEGA = 7.2921E-05
```

**Do not carry over `ROTATION = "betaplane"` / `F_0 = 0` from
`OM4.single_column.COBALT`.** That setting gives zero Coriolis everywhere. It
is harmless over that case's 48-hour run, but in anything longer there is no
rotational limit on wind-driven mixed-layer deepening: the boundary layer
deepens without bound, holds SST artificially low, suppresses longwave and
latent heat loss, and the column takes up heat continuously.

A year-long run with `F_0 = 0` fails in a way that is easy to miss. It reports
**zero truncations and healthy CFL throughout, and exits 0** — but the
thermocline collapses (the upper 400 m goes isothermal, warming reaching
1000 m) and the column-mean temperature climbs by roughly 2.7 C, implying a
net surface heat flux near 1400 W/m2, which is physically impossible. Nothing
in the run log flags it; it has to be caught by inspecting the profiles.

`2omegasinlat` derives f from the grid latitude, so every station gets the
correct value with no further edits. This is required for any multi-month
integration, and for the configuration to be meaningful at more than one
latitude.

## Running

```bash
export PATH="$HOME/work/FRE-NCtools/build/bin:$PATH"   # FRE-NCtools
./setup_station.sh BATS 31.6667 -64.1667               # build + link the grid
ln -sfn input.nml_1yr input.nml                        # or input.nml_2day
mpirun -np 1 ../../builds/build/<machine>-<platform>/ocean_ice/repro/MOM6SIS2
```

`setup_station.sh <station_name> <latitude> <longitude> [bottom_depth_m]`
builds a 0.4-degree, 4x4-cell box centred on the station and links the grid
files into `INPUT/`. Grids are kept per station under `INPUT/grids/<name>/`, so
switching location is another call to the script. Default bottom depth is
4000 m.

```bash
./setup_station.sh HOT    22.75  -158.0   4800
./setup_station.sh EQPAC   0.0   -140.0   5000
```

Nothing else needs to change between stations: the initial conditions and
forcing are global and are interpolated onto whatever grid is present, and the
Coriolis parameter is derived from the grid latitude.

Namelists provided: `input.nml_1yr` (12 months) and `input.nml_2day` (a quick
configuration check). Both start 2004-01-01.

## Differences between this experiment and OM4.single_column.COBALT

`exps/OM4.single_column.COBALT` is a **continuous-integration regression
test**. It is not a science configuration, and two of the differences below
are the reason why.

| | `OM4.single_column.COBALT` | this experiment |
|---|---|---|
| Purpose | CI regression test | science runs |
| Location | BATS only | any station |
| Run length | ~3.6 days (forcing ends) | full year 2004 |
| Physical IC | `MOM_IC.nc`, index-matched to grid | global WOA13, interpolated |
| BGC IC | `MOM_IC.nc` via `GENERIC_TRACER_IC_FILE` | per-tracer global sources |
| Coriolis | `F_0 = 0` (no rotation) | `2omegasinlat` (from latitude) |
| Fe / N deposition | off | on |

**Physical initial conditions.** The regression case overrides
`INIT_LAYERS_FROM_Z_FILE` to `False` and reads `MOM_IC.nc`, which is
*index*-matched to the BATS grid: it is read without interpolation and is only
valid on a grid of exactly those dimensions at exactly that location. Here it
is `True`, so MOM6 interpolates global WOA13 monthly climatology onto whatever
grid is supplied.

**BGC initial conditions.** The regression `field_table` contains ~79
`*_src_file` entries, but they have no effect. `enforce_src_info = f` sets
`requires_src_info = .false.` for every tracer, and that flag is the branch
condition in `initialize_MOM_generic_tracer`
(`src/ocean_BGC/generic_tracers/MOM_generic_tracer.F90`) that decides whether a
tracer initialises from its own source file. With it false, every tracer falls
through to `GENERIC_TRACER_IC_FILE` — `MOM_IC.nc` again. This experiment sets
`enforce_src_info = t`, which routes tracers through
`MOM_initialize_tracer_from_Z`, interpolating each global source onto the model
grid, and leaves `GENERIC_TRACER_IC_FILE` unset.

**Coriolis.** The regression case sets `ROTATION = "betaplane"` with `F_0 = 0`
— no rotation anywhere. This experiment uses `ROTATION = "2omegasinlat"`. This
is the single most important setting to carry across if you adapt either case;
see [Important: `ROTATION` must follow the station
latitude](#important-rotation-must-follow-the-station-latitude) above for why.

**Deposition.** See below.

## Forcing and deposition

Atmospheric forcing is JRA55-do for the full year 2004: 2930 3-hourly records
on the global 640x320 grid, `gregorian` calendar. The regression case uses the
first 31 records of these same files, which is why it cannot run past ~3.6
days.

Atmospheric deposition of iron, lithogenic dust and nitrogen is **enabled**
here, from global 12-month climatologies:

| Field | File | Variable |
|---|---|---|
| dry Fe | `Soluble_Fe_Flux_PI.nc` | `FLUX` |
| dry lithogenic dust | `Mineral_Fe_Flux_PI.nc` | `FLUX_MINERAL` |
| dry PO4 (scaled from dust) | `Mineral_Fe_Flux_PI.nc` | `FLUX_MINERAL` |
| wet / dry NO3 | `depflux_total.mean.1860.nc` | `NO3_{WET,DRY}_DEP` |
| wet / dry NH4 | `depflux_total.mean.1860.nc` | `NH4_{WET,DRY}_DEP` |

**`OM4.single_column.COBALT` has no iron or nitrogen deposition at all** — its
`data_table` supplies near-zero constants (`-1.0e-13`, `-1.0e-12`) for wet and
dry NO3 and nothing whatsoever for Fe, lithogenic dust or NH4. Atmospheric
deposition is a first-order nutrient source in an open-ocean column, and iron
in particular controls diazotroph growth and the N:P balance. A single-column
COBALT run without it is not a scientifically valid model of the ecosystem,
which is a large part of why that case should be treated strictly as a
regression test.

Two things to note about the deposition fields used here. They are
**pre-industrial** (`*_PI.nc`, `mean.1860`); upstream CEFI has since moved to
ESM4 1993-2014 present-day climatologies (see `exps/NWA12.COBALT/data_table`),
which also carry wet Fe and dust deposition that these files lack. And
atmospheric CO2 is a constant 360 ppm in `data_table` — change all three
`co2_*` entries together if you need a different value.

## Initial conditions

| Source | Provides |
|---|---|
| `woa13_decav_{ptemp,s}_monthly_fulldepth_01.nc` | temperature, salinity |
| `woa13_all_{n,o,p,i}_annual_01.nc` | no3, o2, po4, sio4 |
| `GLODAPv2.2016b.oi-filled.20180322.nc` | alk, dic |
| `GLODAPv1.abiotic.filled.20180316.nc` | abiotic carbon |
| `cobaltv3_tracer_source.nc` | all remaining COBALT tracers |

`cobaltv3_tracer_source.nc` is the COBALTv3 initial-condition file: global,
360x180 x 35 depth levels, containing the 76 tracers COBALTv3 needs to run
anywhere:

```
cadet_arag  cadet_arag_btf  cadet_calc  cadet_calc_btf  cased      chl
co3_ion     fed             fedet       fedet_btf       fedi       fedi_btf
felg        felg_btf        femd        femd_btf        fesm       fesm_btf
htotal      irr_aclm        irr_aclm_sfc irr_aclm_z     irr_mem    ldon
ldop        lith            lithdet     lithdet_btf     mu_mem_ndi mu_mem_nlg
mu_mem_nmd  mu_mem_nsm      nbact       ndet            ndet_btf   ndet_fast
ndet_fast_btf ndi           ndi_btf     nh3             nh4        nlg
nlg_btf     nlgz            nmd         nmd_btf         nmdz       nsm
nsm_btf     nsmz            pcmlim_aclm_ndi pcmlim_aclm_nlg
pcmlim_aclm_nmd pcmlim_aclm_nsm         pdet            pdet_btf   pdet_fast
pdet_fast_btf pdi           pdi_btf     plg             plg_btf    pmd
pmd_btf     psm             psm_btf     sidet           sidet_btf  silg
silg_btf    simd            simd_btf    sldon           sldop      srdon
srdop
```

The `*_btf` bottom-flux tracers and the acclimation and memory variables
(`irr_aclm*`, `pcmlim_aclm_*`, `mu_mem_*`, `irr_mem`) start from zero rather
than from file — they are empty in the source file, and zero is the correct
start for them: bottom fluxes accumulate from zero and the memory variables
relax to ambient conditions within days. They carry
`_requires_src_info = f` and `_requires_restart = f` in `field_table`, which
routes them down `MOM_generic_tracer`'s "initialized by the tracer package"
path instead of demanding a `GENERIC_TRACER_IC_FILE`.

## Input files — how to get them

Everything under `INPUT/` is a symlink into `exps/datasets/station_1d/`, which
is **not** tracked in this repository, so a fresh clone has broken symlinks
until that directory is populated. These files are not part of the 1D CI
dataset (`1d_ci_datasets.tar.gz`) and are not part of the CEFI dataset
distribution. **Contact Jessica Luo for access.**

| Files | Purpose | Size |
|---|---|---|
| 9 x JRA55-do `*.padded.nc` | full-year 2004 forcing | ~12 GB |
| `woa13_decav_{ptemp,s}_monthly_fulldepth_01.nc` | global T/S climatology | |
| `woa13_all_{n,o,p,i}_annual_01.nc` | no3, o2, po4, sio4 | |
| `GLODAPv2.2016b.*.nc`, `GLODAPv1.abiotic.*.nc` | alk, dic, abiotic carbon | |
| `cobaltv3_tracer_source.nc` | COBALTv3 tracer ICs | 744 MB |
| `Soluble_Fe_Flux_PI.nc`, `Mineral_Fe_Flux_PI.nc`, `depflux_total.mean.1860.nc` | Fe / dust / N deposition | |
| `seawifs-clim-*.nc` | chlorophyll climatology | |

`geothermal_davies2013_v1.nc` and `diag_rho2.nc` come from the 1D CI dataset
(`exps/datasets/OM4_025.JRA.single_column/`).

## Known issue: `atm%tr_bot` out-of-bounds abort at the first timestep

If the model was built with Fortran bounds checking enabled — which the macOS
build turns on by default, since `builds/macOS/osx-gnu.mk` ships
`FFLAGS_REPRO = -O1 -fbounds-check` — the run aborts on the first coupled
timestep with:

```
Fortran runtime error: Index '2' of dimension 3 of array 'atm%tr_bot'
outside of expected range (1:1)
```

This is a bug in the `atmos_null` submodule, not in this experiment.
`atmos_model.F90` counts **land** tracers and uses that number to allocate the
**atmosphere's** arrays. The field table declares one land tracer (`sphum`) but
four atmospheric ones (`sphum`, `liq_wat`, `ice_wat`, `cld_amt`), so the
coupler — which loops over the atmospheric count — indexes past the end of a
one-element array. The same count also undersizes `Surf_Diff%dflux_tr` and
`Surf_Diff%delta_tr`.

Two lines in `src/atmos_null/atmos_model.F90` need to change:

```diff
@@ line 83 @@
-use field_manager_mod, only : MODEL_LAND
+use field_manager_mod, only : MODEL_ATMOS

@@ line 483 @@
-call register_tracers(MODEL_LAND, ntracers, ntprog, ndiag)
+call register_tracers(MODEL_ATMOS, ntracers, ntprog, ndiag)
```

Then rebuild.

Note that `src/atmos_null` is a **submodule**, so `git submodule update` will
silently revert the change — reapply it after any submodule sync. The fix
belongs upstream at https://github.com/NOAA-GFDL/atmos_null.

The out-of-bounds access happens on every platform; it is only *detected* where
bounds checking is on. CI does not catch it because
`builds/docker/linux-gnu.mk` has `-fbounds-check` commented out of
`FFLAGS_DEBUG` and CI runs the `debug` build.
