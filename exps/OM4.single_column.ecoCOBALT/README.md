# OM4.single_column.ecoCOBALT

Single-column eco-COBALT — the GZ-COBALT (gelatinous zooplankton) and COBALT-DVM
(diel vertical migration) merge — at the same physics as
[`../OM4.single_column.COBALT.station`](../OM4.single_column.COBALT.station).

Only the biogeochemistry differs. `MOM_input`, `MOM_layout`, `MOM_saltrestore`,
`SIS_input`, `SIS_layout`, `SIS_override`, `data_table` and `run_multiyear.sh`
are **symlinks** to the station case, so the two cannot silently drift apart.
What is real here: `MOM_override`, `field_table`, `COBALT_input`,
`COBALT_override`, the `input.nml_*` and `diag_table_ecoCOB*` variants,
`setup_station.sh`, `regression.sh` and `BGC_SOURCE`.

## Setup

This assumes `../OM4.single_column.COBALT.station` is already built and
running. Everything that case needed -- MOM6-SIS2 built, FRE-NCtools on
`PATH`, and `exps/datasets/station_1d/` populated -- is reused here unchanged;
nothing new needs to be downloaded. Three things ARE new for this experiment,
and the steps below cover each: a different executable, this experiment's own
copy of the grid, and its own `field_table` / `COBALT_override`.

### 1. Build the eco-COBALT executable (one-time)

```bash
cd CEFI-regional-MOM6           # repo root
./builds/build_bgc_variant.sh ecocobalt
```

eco-COBALT is a different `src/ocean_BGC` branch
(`jessluo/feature/gz-cobalt-merge`), so it needs its own executable -- the
station case's `MOM6SIS2` will not work here; see "The executable" below for
why. This script checks that branch out into `src/ocean_BGC`, builds
`MOM6SIS2` from it, and archives the result as `builds/exec/MOM6SIS2.ecocobalt`
with a `.provenance` file recording exactly which `ocean_BGC` commit it came
from.

The first build (or the first after `rm -rf builds/build`) takes as long as
building the station case from scratch -- a few minutes. Rebuilding later,
e.g. after the branch gets new commits, is usually well under a minute, since
only the changed BGC source files recompile.

Confirm it worked:
```bash
ls -la builds/exec/MOM6SIS2.ecocobalt
cat builds/exec/MOM6SIS2.ecocobalt.provenance
```

`git status` in the repo root will now show ` M src/ocean_BGC` -- expected,
see "The executable" below. It does not affect the station case, which never
touches that submodule at run time.

### 2. Build a grid for this experiment (one-time per station)

```bash
cd exps/OM4.single_column.ecoCOBALT
./setup_station.sh BATS 31.6667 -64.1667
```

Build it again here even if you already have a BATS grid for the station
case: `setup_station.sh` in this directory is a *copy* of the station case's,
not a symlink, so it manages its own `INPUT/grids/` independently -- the two
experiments' grid inventories never silently share (or drift from) each
other. Usage is otherwise identical to the station case:

```bash
./setup_station.sh              # list grids already built here
./setup_station.sh HOT          # activate one already built, by name
```

Building a new station needs FRE-NCtools on `PATH` (see the station README's
"Installing FRE-NCtools"); re-activating one already built here does not.

### 3. Regression test

```bash
./regression.sh
```

This runs a 48-hour case and a 24-hour-plus-24-hour-restart case, then checks
two things: the restart files are bitwise identical between them, and
`ocean.stats` from the 48-hour run matches `ref/ocean.stats`. A clean run
prints

```
Check 1: restart reproducibility (48hr vs 24hr+24hr)
  identical  MOM.res.nc
  identical  ice_cobalt.res.nc
  identical  ice_model.res.nc
  identical  ocean_cobalt_airsea_flux.res.nc

Check 2: ocean.stats vs ref/ocean.stats (rel tol 1.0e-9)
  OK: largest difference 0.000e+00

REGRESSION TEST PASSED
```

and takes a couple of minutes. If it fails, the two most likely causes are
covered below: a `BGC_SOURCE` / executable mismatch ("The executable"), or a
missing `use_Press_et_al_tridiag_solver` setting ("Namelist requirements").

### 4. Longer runs

```bash
ln -sfn input.nml_1yr input.nml
ln -sfn diag_table_ecoCOB diag_table
EXE=../../builds/exec/MOM6SIS2.ecocobalt ./run_multiyear.sh 1
```

**Before running longer than the regression test**, skim "Initial conditions"
below: the four new biomass tracers' initial condition comes from a split of
existing zooplankton fields, not from any independent observation or spin-up,
so treat the ecosystem trajectory as illustrative rather than validated.

Don't run a longer case in this directory at the same time as another one --
`run_multiyear.sh`, `regression.sh` and a bare `mpirun` invocation all reuse
the same `INPUT/`, `RESTART/`, `input.nml` and `diag_table` in this directory,
so two runs launched here at once will corrupt each other's output. If you
want to compare two configurations side by side, run one to completion before
starting the next, or check out a second copy of this directory.

## The executable

eco-COBALT is a different `src/ocean_BGC` branch, so it is a **different
executable** from standard COBALT. `../../builds/build_bgc_variant.sh` checks
out the right branch, rebuilds, and archives the binary as
`../../builds/exec/MOM6SIS2.<variant>` with a `.provenance` file recording the
ocean_BGC SHA. `regression.sh` cross-checks that SHA against `BGC_SOURCE` and
refuses to run on a mismatch — running this experiment's `field_table` against a
standard-COBALT binary is the easiest mistake to make here and fails silently
rather than loudly.

Two consequences to expect, both normal:

- `git status` in the superproject permanently shows ` M src/ocean_BGC`.
- `git submodule update` silently reverts `src/ocean_BGC` and invalidates the
  build. Re-run `build_bgc_variant.sh` after one.

## Initial conditions

The merge registers 21 tracers that standard COBALT does not. All are registered
unconditionally with no `init_value`, so without intervention they all start
at exactly 0.0.

**Four need a non-zero initial condition**: `nvmmdz`, `nvmlgz`, `nsmt`, `nlgt`.
These are live grazer biomass, and zero is an absorbing state -- ingestion,
growth and every loss term scale with biomass, so a group started at zero can
never recover. Same reasoning as
[the commit that stopped cold-starting the phytoplankton](https://github.com/jessluo/CEFI-regional-MOM6/commit/2820776bb1368dfd407daaf13c15561658d27e3f)
in the station case.

**The other 17** -- the 15 gut/metabolite pools plus `fedet_fast` and
`fedet_fast_btf` -- correctly cold-start at 0.0: they are flux-through
reservoirs refilled from ingestion within hours, so they self-heal regardless
of starting value.

### Setting the initial condition for the four biomass tracers

The exact value barely matters. A 1-year run at BATS was compared under two
choices -- the new tracers simply set equal to an existing zooplankton field,
versus the donor fields partitioned to conserve the standard-COBALT total --
and the two converged to within a small factor of each other by year end
despite a 2-3x difference in their starting values. So the simplest approach
is a reasonable default: just copy an existing field, as done here for a
fresh `ecocobalt_tracer_source.nc`:

```bash
cd ../datasets/station_1d
ncks -O -v nmdz,nlgz cobaltv3_tracer_source.nc ecocobalt_tracer_source.nc
ncap2 -O -s 'nvmmdz=nmdz; nvmlgz=nlgz; nlgt=nlgz; nsmt=nlgz;' \
      ecocobalt_tracer_source.nc ecocobalt_tracer_source.nc
for v in nvmmdz nvmlgz nsmt nlgt; do
  ncatted -O -a _FillValue,$v,o,f,1.0e20 -a missing_value,$v,o,f,1.0e20 \
             -a units,$v,o,c,"mol/kg" ecocobalt_tracer_source.nc
done
```

(the explicit `ncatted` matters: `ncap2` does not reliably carry `_FillValue`
through arithmetic, and a source variable without one is a hard FATAL at
model init.)

This experiment currently ships with a partitioned version instead, which
also conserves the standard-COBALT total for `nmdz`/`nlgz` rather than just
copying them:

```bash
ncap2 -O -s 'nvmmdz=0.5f*nmdz; nvmlgz=0.5f*nlgz; nsmt=nlgz/3.0f; nlgt=nlgz/3.0f;
             nmdz=0.5f*nmdz;   nlgz=0.5f*nlgz;' \
      ecocobalt_tracer_source.nc ecocobalt_tracer_source.nc
```

(derive the migrating/tunicate fields before overwriting `nmdz`/`nlgz` with
their halves; this version also needs `nmdz_src_file`/`nlgz_src_file` in
`field_table` repointed at `ecocobalt_tracer_source.nc`.) Use whichever is
convenient for your case -- neither is more "correct" for this purpose than
the other.

`cobaltv3_tracer_source.nc` is never modified by either version; both write to
a separate file, so the standard-COBALT station case is unaffected.

## Namelist requirements

Only one namelist setting needs to differ from the station case, in
`generic_tracer_nml`:

```
&generic_tracer_nml
       use_Press_et_al_tridiag_solver=.true.
```

This is required for diel vertical migration to conserve mass, and is already
set in all six `input.nml_*` files shipped here -- **do not remove it**, and
carry it over if you build a new `input.nml` for this experiment from scratch.
Everything else in `generic_tracer_nml` and `generic_COBALT_nml` is unchanged
from the station case.

`does_dvm` (which groups actually migrate) is **not** a namelist flag -- it is
a per-group `COBALT_input` / `COBALT_override` parameter (`does_dvm_vmmdz`,
`_vmlgz`, `_smz`, etc.), and the defaults already turn migration on for the
three groups that need it. `COBALT_override` here is intentionally empty and
documents those defaults in its header comment; leave it that way unless you
deliberately want different groups to migrate.

## Relationship to standard COBALT

eco-COBALT is **not** expected to reproduce
`../OM4.single_column.COBALT.station` bitwise, for two independent reasons:
`use_Press_et_al_tridiag_solver = .true.` changes the vertical solver for every
tracer, and the merge adds four grazers to the food web. `ref/ocean.stats` here
is generated fresh and is not comparable to the station case's.

## Files

| file | what |
|---|---|
| `BGC_SOURCE` | the ocean_BGC remote/branch/commit this experiment requires |
| `field_table` | station's, plus the 21 eco-COBALT tracer dispositions |
| `COBALT_override` | empty; documents the eco-COBALT parameter defaults |
| `diag_table_ecoCOB_min` | regression test: are the new tracers alive? |
| `diag_table_ecoCOB` | full table: station's `diag_table_no_daily` plus the eco-COBALT tracers and rate diagnostics |
| `regression.sh` | 48hr vs 24hr+24hr restart check + `ocean.stats` vs `ref/` |
| `setup_station.sh` | copy of the station case's; owns this experiment's grids |

## Status

Verified on mac-m1 / osx-gnu / repro at BATS, most recently 2026-09-16 against
`builds/exec/MOM6SIS2.ecocobalt` built from
[the current `feature/gz-cobalt-merge` tip](https://github.com/jessluo/cefi_ocean_BGC/commit/a5b7fb1edaa2bee11f4efc3a2f9ba5249dd2aaf4):

- builds clean, no new warnings
- all four biomass tracers initialise via `MOM_initialize_tracer_from_Z`
- 2-day and 1-year runs complete; all five element budgets close at
  `imbalance_tolerance = 1.0e-9` for the full year
- 1-year run: zero truncations, no NaN, column-mean temperature drift
  +0.089 K/yr, salinity flat
- `./regression.sh` passes: restart files bitwise identical across
  48hr vs 24hr+24hr, `ocean.stats` matches `ref/` to `0.000e+00`

