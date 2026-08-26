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
`OM4.single_column.COBALT`.** That gives zero Coriolis everywhere, which is
harmless over that case's 48-hour run but leaves the wind-driven mixed layer
with no rotational constraint in anything longer.

The resulting failure is quiet: a year-long run still exits 0 with zero
truncations, but the thermocline collapses and the column-mean temperature
drifts by degrees. It has to be caught by inspecting the profiles.

`2omegasinlat` derives f from the grid latitude, so every station gets the
correct value with no further edits. This is required for any multi-month
integration, and for the configuration to be meaningful at more than one
latitude.

## Running

### Before your first run

Four things need to be in place. They are one-time steps except the last,
which you repeat whenever you change station.

1. **Build MOM6-SIS2-COBALT** by following
   [`builds/README.md`](../../builds/README.md) — start at its *Quick Start
   Guide*, which covers the prerequisites per platform. In outline: create
   `builds/<machine>/` holding a `<platform>.env` and a `<platform>.mk` for
   your system (the `.env` can be empty if gfortran, MPI and netCDF are already
   installed), then from `builds/`:

   ```bash
   ./linux-build.bash -m <machine> -p <platform> -t repro -f mom6sis2
   ```

   That produces
   `builds/build/<machine>-<platform>/ocean_ice/repro/MOM6SIS2`, which is the
   path used in the run commands below — for example `mac-m1-osx-gnu` or
   `gaea-ncrc5.intel23`. Substitute your own throughout.

   Heed the conda warning at the top of that README and `conda deactivate`
   before building. A conda environment ahead of your system tools on PATH can
   supply a netCDF built for a different architecture than your compilers,
   which surfaces only at link time as a wall of undefined symbols.

   If your `.mk` enables Fortran bounds checking — as `builds/macOS/osx-gnu.mk`
   does — read [Known issue: `atm%tr_bot`](#known-issue-atmtr_bot-out-of-bounds-abort-at-the-first-timestep)
   before running, or the model aborts on the first timestep.

2. **Install FRE-NCtools** and put it on PATH — see
   [Installing FRE-NCtools](#installing-fre-nctools) below.

   ```bash
   export PATH="$HOME/work/FRE-NCtools/build/bin:$PATH"
   ```

3. **Get the input files** into `exps/datasets/station_1d/`. They are not in
   the repository and not in the 1D CI dataset — see
   [Input files](#input-files--how-to-get-them). Until this is done every
   symlink in `INPUT/` is broken. Check with:

   ```bash
   for f in INPUT/*.nc; do [ -e "$f" ] || echo "MISSING: $f"; done
   ```

   Any output means the corresponding file is not yet in
   `exps/datasets/station_1d/`.

4. **Build the grid for your station.**

   ```bash
   ./setup_station.sh BATS 31.6667 -64.1667
   ```

   `setup_station.sh <station_name> <latitude> <longitude> [bottom_depth_m]`
   builds a 0.4-degree, 4x4-cell box centred on the station and links the grid
   into `INPUT/`. Default bottom depth is 4000 m.

   ```bash
   ./setup_station.sh HOT    22.75  -158.0   4800
   ./setup_station.sh EQPAC   0.0   -140.0   5000
   ```

   Grids are kept per station under `INPUT/grids/<name>/` and are not deleted
   when you switch, so build a set once and move between them by name alone:

   ```bash
   ./setup_station.sh              # list the grids already built
   ./setup_station.sh HOT          # activate one, no coordinates needed
   ```

   The name-only form re-links an existing grid and does **not** need
   FRE-NCtools on PATH — only building a new grid does. Passing coordinates
   again rebuilds that station's grid from scratch.

   Nothing else changes between stations: the initial conditions and forcing
   are global and are interpolated onto whatever grid is present, and the
   Coriolis parameter is derived from the grid latitude.

### A single-year run

```bash
ln -sfn input.nml_1yr      input.nml       # 12 months from 2004-01-01
ln -sfn diag_table_no_daily diag_table     # monthly + annual output
mpirun -np 1 ../../builds/build/<machine>-<platform>/ocean_ice/repro/MOM6SIS2
```

Takes roughly 25 minutes on one core. Output lands in the experiment
directory: `2004*.nc` diagnostics, `ocean.stats`, and restarts in `RESTART/`.

To check the configuration before committing to a full year, swap in the
two-day namelist — it exercises every initialisation path in about 30 seconds:

```bash
ln -sfn input.nml_2day input.nml
```

`ocean.stats` is the first thing to look at. Truncations should be 0 and
`Mean Temp` should stay close to its starting value; see the note on drift
under [Multi-year runs](#multi-year-runs-repeat-year-forcing).

If the run dies immediately with

```
FATAL: time_interp_external 2: time ... is after range of list ...
```

there is a leftover `INPUT/coupler.res` from a previous multi-year run. The
coupler reads the start date from that file whenever it exists, whatever
`input_filename` says, so the run begins after the end of the forcing.
`run_multiyear.sh` clears these itself, but clear them by hand if needed:

```bash
rm -f INPUT/*.res.nc INPUT/coupler.res
```

### A multi-year run

```bash
./run_multiyear.sh 10
```

See [Multi-year runs](#multi-year-runs-repeat-year-forcing) below for what the
script does and how the output is organised. Do not start a multi-year run
with `diag_table_with_daily` selected unless you want tens of GB of output.

### Configuration: `input.nml` and `diag_table`

Both are symlinks to tracked variants, so switching is a `ln -sfn` rather than
an edit:

| symlink | variants |
|---|---|
| `input.nml` | `input.nml_1yr` (12 months), `input.nml_2day` (quick check), `input.nml_1yr_rst` (restart segment, used by `run_multiyear.sh`) |
| `diag_table` | `diag_table_no_daily` (monthly + annual), `diag_table_with_daily` (adds daily output) |

All namelists start 2004-01-01, the only year the forcing covers.
`diag_table_no_daily` is the default: the daily files dominate output volume,
taking one simulated year from roughly 17 MB to 70 MB.

Neither symlink is tracked in git, so a fresh clone has neither. Create them
before the first run — the commands above do this.

## Installing FRE-NCtools

`setup_station.sh` needs `make_hgrid`, `make_solo_mosaic`, `make_topog` and
`make_coupler_mosaic` from [FRE-NCtools](https://github.com/NOAA-GFDL/FRE-NCtools).
There is no packaged release; build it from source:

```bash
mkdir -p ~/work && cd ~/work
git clone https://github.com/NOAA-GFDL/FRE-NCtools.git
cd FRE-NCtools                      # <- easy to miss; the next two steps must run here
autoreconf -i
mkdir build && cd build
../configure --prefix=$HOME/work/FRE-NCtools/build CC=gcc-16 FC=gfortran-16
make -j8
make install
```

The tools land in `$HOME/work/FRE-NCtools/build/bin`. Put that on your PATH
before running `setup_station.sh`:

```bash
export PATH="$HOME/work/FRE-NCtools/build/bin:$PATH"
```

**That `export` only affects the shell you run it in.** A new terminal will
not have it, and `setup_station.sh` will fail with
`command not found: make_hgrid` even though the tools are installed. Either
re-run the export in each new shell, or add the line to your shell profile
(`~/.zshrc` for zsh, `~/.bash_profile` for bash) to make it permanent.

Three things that commonly go wrong:

**`autoreconf -i` fails with `possibly undefined macro: AC_PROG_LIBTOOL`.**
GNU libtool is missing. On macOS `/usr/bin/libtool` is Apple's unrelated tool,
so libtool can look installed when it is not — install the GNU one
(`brew install libtool`; `apt install libtool` on Debian/Ubuntu). Homebrew's
`autoreconf` already looks for the `g`-prefixed `glibtoolize`, so no further
setup is needed.

**`configure` reports `C compiler cannot create executables`.** The `CC` / `FC`
you passed do not exist. Substitute whatever your toolchain provides —
`ls $(brew --prefix)/bin/gcc-*` on macOS, or drop `CC`/`FC` entirely to use the
system defaults. Note that the version-suffixed names track whatever GCC
Homebrew currently installs, so the `gcc-16` above may need changing.

**netCDF is found but the link fails, or the wrong netCDF is used.**
`configure` locates netCDF through `nc-config` / `nf-config` on PATH. If you
have a conda environment ahead of your system tools in PATH, those helpers may
point at a netCDF built for a different architecture or compiler than the one
you are building with. Check with `which nf-config` and put the intended
toolchain first.

Once installed, verify the tools are on PATH:

```bash
command -v make_hgrid make_solo_mosaic make_topog make_coupler_mosaic
```

That should print four paths. If it prints nothing, the PATH export above has
not taken effect in this shell.

(`make_hgrid --help` prints its usage but exits with status 2, so do not read
a non-zero exit there as a failed install.)

## Multi-year runs (repeat-year forcing)

```bash
./run_multiyear.sh 10                     # ten segments
./run_multiyear.sh 2                      # short test
./run_multiyear.sh 10 /path/to/MOM6SIS2   # non-default build
```

The JRA55-do forcing covers calendar year 2004 only, so a multi-year
integration re-runs that year repeatedly. Each segment reads the ocean,
sea-ice and BGC state left by the previous one but resets the model clock to
2004-01-01 so the forcing lines up. This is standard **repeat-year forcing**:
the ocean spins up, the atmosphere is identical every year.

The clock reset uses `force_date_from_namelist = .true.` in
`input.nml_1yr_rst`, which overrides the date in `INPUT/coupler.res` while
still reading the restart fields. Segment 1 is a cold start.

Because every segment carries the same model dates, output would otherwise
overwrite between segments, so each is archived on completion:

```
history/yearNN/     diagnostics and ocean.stats for that segment
RESTART_yearNN/     restarts; the highest NN is the final state
```

To extend an existing run, rerun with a larger `<n_years>` — but note the
script restarts from segment 1, so to continue rather than redo, start from
the last `RESTART_yearNN` by hand.

**Repeat-year forcing has no interannual variability.** A multi-year run here
shows the ocean's adjustment and drift timescale under one fixed atmosphere,
not decadal variability.

**There is no temperature or salinity restoring**: `RESTORE_SALINITY` and
`RESTORE_TEMPERATURE` are both false. A single column has no lateral heat or
salt transport, so any net surface imbalance accumulates rather than being
exported. Over one year at BATS the upper ocean warms about 1.6 C at the
surface even with correct rotation; across ten segments that compounds.

Watch column-mean temperature in `history/yearNN/ocean.stats` from segment to
segment. If the drift is unacceptable for your application, the usual remedy
is surface restoring: set `RESTORE_SALINITY = True` (and optionally
`RESTORE_TEMPERATURE`) in `MOM_override` and supply the corresponding
`SALT_RESTORE_FILE` / `SST_RESTORE_FILE` on the model grid, holding the
monthly climatological surface values at the station. `FLUXCONST` sets the
restoring strength. Those files have to be generated per station, for instance
by sampling WOA at the station location onto the grid built by
`setup_station.sh`. Restoring suppresses drift but also damps the very surface
variability a single-column run is often set up to study, so it is a modelling
choice rather than a fix and is not enabled by default.

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
| `GLODAPv2.2016b.oi-filled.20180322.nc` | alk, dic | |
| `cobaltv3_tracer_source.nc` | COBALTv3 tracer ICs | 744 MB |
| `Soluble_Fe_Flux_PI.nc`, `Mineral_Fe_Flux_PI.nc`, `depflux_total.mean.1860.nc` | Fe / dust / N deposition | |
| `seawifs-clim-*.nc` | chlorophyll climatology | |

`geothermal_davies2013_v1.nc` and `diag_rho2.nc` are also needed. Every
`INPUT/` symlink resolves inside `exps/datasets/station_1d/`, so that one
directory is the only thing you need to populate — this experiment does not
depend on the 1D CI dataset.

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
