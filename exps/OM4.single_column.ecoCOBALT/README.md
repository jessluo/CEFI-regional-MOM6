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

To give a group a zero initial condition instead -- which switches it off for
good, since zero is absorbing -- see "Switching groups off" below. That is a
`field_table` edit, not an IC-file edit.

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
documents those defaults in its header comment. See "Switching groups off"
below if you want a different set of groups migrating.

## Switching groups off

There are three ways to take a group out of the run, and they mean different
things. Pick the one that matches the question you are asking.

### Stop a group migrating

Two parameters in `COBALT_override`, and **both are required**:

```
does_dvm_lgt = False
swim_max_lgt = 0.0
```

`does_dvm_<group> = False` on its own is not enough. It does remove the group's
gut and metabolite pools and route egestion straight from ingestion, but the
group is still assigned a swimming speed, and `nvmmdz`, `nvmlgz` and `nlgt` are
registered `move_vertical = .true.` -- so that speed still moves the biomass
tracer. The group carries on migrating, just without transporting its gut
contents, which is almost never what was intended. `generic_COBALT` enforces the
pairing with a `FATAL`, so a half-configured run stops at initialisation instead
of producing quietly wrong answers.

Migration can only be enabled for `vmmdz`, `vmlgz` and `lgt` -- the three groups
that own gut and metabolite tracers -- and a second `FATAL` rejects `does_dvm`
anywhere else. Switching it *off* is supported for all seven.

The group is otherwise untouched: still present, still grazing, still grazed.
A group switched off this way becomes structurally identical to its
non-migrating counterpart, differing only in its own parameter values. Static
`lgt`, for instance, routes ingested material exactly as `smt` does, with no
gut-clearance delay -- but it keeps `frac_fast_det_lgt = 0.75` and
`agg_lgt = 8.2e+04`, so salp falls and fast-sinking egestion carry on.

### Remove a group entirely (zero initial condition)

Zero is an absorbing state for every grazer -- ingestion, growth and every loss
term scale with biomass -- so a group started at zero stays at exactly zero for
the whole run. This is the clean way to ask "what does this configuration look
like without salps at all".

In `field_table`, delete that group's six `<name>_src_*` / `<name>_valid_min`
lines and add **both** of these:

```
nsmt_requires_restart = f
nsmt_requires_src_info = f
```

Both flags are needed. `initialize_MOM_generic_tracer` skips initialisation only
when `.not. requires_restart`; a prognostic tracer with no `src_file` that still
requires a restart falls through to the global generic-tracer IC file and aborts
with `check Generic Tracer IC filename`. Dropping the restart requirement is
safe precisely because the value is always 0.0, so there is nothing to carry
across a restart.

Two things to know. The tracers still exist: registered, advected, diffused and
written to restarts every step, just permanently zero, so there is no cost
saving. And zeroing an initial condition removes that nitrogen from the column,
so total inventory no longer matches a run that seeds the group. If you need
matched inventories, fold the removed nitrogen into `nmdz`/`nlgz` in the IC
file, the same bookkeeping choice described under "Initial conditions".

### Starve a group (`imax = 0`)

```
imax_smt = 0.0
imax_lgt = 0.0
```

`imax` multiplies the ingestion matrix, so zero removes all feeding while
leaving the group present, edible and decaying. Unlike a zero initial condition
this conserves nitrogen -- the biomass drains into detritus and other grazers
rather than vanishing at `t = 0`. The group never reaches zero either, because
basal respiration scales as `f_n^2 / (refuge_conc + f_n)` and so falls away
faster than the biomass does.

## Relationship to its parent models

eco-COBALT is the merge of two parent configurations -- COBALTv3-DVM
(`dev/eco-cobalt`, which adds diel vertical migration) and standard COBALTv3
(`dev/cefi`). Switching the added groups off brings it close to each parent but
not bitwise onto either, and it is worth knowing why before you interpret a
difference as a bug.

Neither parent shares this case's `ref/ocean.stats`; it is generated fresh here
and is not comparable to the station case's.

### Reducing to COBALTv3-DVM

Zero the two tunicate groups and what remains is parameter-for-parameter
identical to `dev/eco-cobalt`, apart from an equivalent rewrite of the egestion
fractions (see below). The runs still diverge -- 7-day run at BATS, column
means, eco-COBALT relative to `dev/eco-cobalt`:

| `nvmmdz` | `nmdz` | `no3` |
|---|---|---|
| -8.9% | -5.5% | agrees to 5 significant figures |

The divergence is already 1.3% on day 1, so it is not a food-web effect of
removing the tunicates. It comes from active-feeding respiration:
`dev/eco-cobalt` registers `phi_aresp_*` (0.3 for every group) but never uses
it, while eco-COBALT adds it to `jmetabo_n` for the migrating groups. eco's
migrators therefore respire more and lose biomass faster.

To reproduce: build the DVM-only executable with
`builds/build_bgc_variant.sh devecocobalt`, and run it against a copy of this
experiment whose `field_table` has the nine tracers that branch does not define
removed -- `nsmt`, `nlgt`, `nlgt_gut`, `nlgt_met`, `plgt_gut`, `silgt_gut`,
`felgt_gut`, `fedet_fast`, `fedet_fast_btf`. Give the copy its own `INPUT/`:
two cases sharing one directory will overwrite each other's restart pickups and
silently start from different dates.

### Reducing to standard COBALTv3

Zero the tunicates *and* the migrating crustaceans, repoint `nmdz`/`nlgz` at
`cobaltv3_tracer_source.nc` so they carry the full standard inventory rather
than their halved values, drop `use_Press_et_al_tridiag_solver` (it does not
exist in the standard build), and set `hp_phi_vis = 0.0`. The two then agree
to roundoff -- maximum relative difference over a 7-day run at BATS:

| `temp` | `no3` | `nlgz` | `nmdz` | `nsmz` | `nsm` | `nlg` | `chl` | `ndet` |
|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 0 | 2.5e-08 | 0 | 0 | 0 |

`hp_phi_vis` is the one parameter that must be changed. eco-COBALT scales
higher-predator ingestion by a light limitation (Poupon et al. 2025),

```
hp_vis_lim = (1 - hp_phi_vis) + hp_phi_vis * irr / (irr + kirr_hp*ki_hp/(ki_hp + tot_prey_hp))
```

which has no COBALTv3 counterpart and reduces to 1 only when
`hp_phi_vis = 0`. At the default 0.90 it cuts predation on `nmdz` and `nlgz`
by ~90% at night. Leaving it on gives residuals of order 1e-02 in `nmdz`,
`nlgz` and `ndet`, which were once put down to N-P colimitation (see below).

Of the 346 parameters the two models share, only the egestion fractions differ,
and that is an equivalent rewrite rather than a retuning: standard COBALT folds
the unassimilated fraction into the `phi_*` values, which sum to 0.30, and
applies them to ingestion; eco-COBALT factors it out as
`egest = (1 - AE) * ingestion` and renormalises `phi_*` to sum to 1.0. With
`AE = 0.7` the two give the same flux, which is why every `phi_*` differs by
exactly 10/3. `gge_max` is 0.4 in both.

Non-migrating zooplankton impose nitrogen-phosphorus colimitation exactly as
standard COBALT does, capping production after respiration
([`a147296`](https://github.com/jessluo/cefi_ocean_BGC/commit/a14729643739a2c21bb1b433cec41223166ed550)):

```
jprod_n = (AE - phi_aresp)*jingest_n - basal_respiration
jprod_n = min(jprod_n, AE*jingest_p/q_p_2_n)
```

Earlier eco-COBALT code applied the colimitation to ingestion, before
respiration. That was a real difference, but it partly offset the missing
higher-predator losses, so fixing it on its own made `nmdz` and `nlgz` agree
*less* well. Only with `hp_phi_vis = 0` as well does the reduction come out
exact.

Iron scavenging is also the COBALTv3 form: the rate scales with
`ndet + ndet_fast` and all adsorbed iron goes to slow `fedet`. GZ-COBALT had
split it, sending the fast share to `fedet_fast` (`jfe_ads_fast`); that has been
reverted, so fast-sinking iron detritus now comes only from egestion.

The 2.5e-08 in `nsm` is a single cell (day 7, level 13) differing by one
float32 unit in the last place, i.e. double-precision roundoff surfacing in the
32-bit output. It is not a structural difference.

To find where the two first diverge, run both for 1 hour with
`dt_cpld = dt_atmos = 900` (one coupling step per biogeochemical step) and
write every generic_cobalt 3-D diagnostic that both models share every 15
minutes. The first record is then the first biogeochemical step from identical
state, so any field that differs there beyond roundoff is a structural
difference. FMS allows at most 300 fields per file, so the diagnostics must be
split across two files. Leave out `det_jzloss_n` and `det_jhploss_n`:
requesting either aborts both executables, because each is registered twice in
`cobalt_reg_diag.F90`.

To reproduce, both sides need the same column and the same starting point:
run standard COBALT on this case's BATS grid (its own `field_table` against
`MOM6SIS2.cobalt`), and reduce this case as described above. Both must
cold-start -- delete `INPUT/*.res.nc` and `INPUT/coupler.res` first -- because
restart pickups override the `field_table` initial conditions, and this case's
restarts carry the halved `nmdz`/`nlgz` rather than the standard values.

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

Verified on mac-m1 / osx-gnu / repro at BATS against
`builds/exec/MOM6SIS2.ecocobalt`, built from
[`803144d`](https://github.com/jessluo/cefi_ocean_BGC/commit/803144d7e6243157fb0f3718cbac14ed7df1fc12)
on `feature/gz-cobalt-merge`:

- builds clean, no new warnings
- all four biomass tracers initialise via `MOM_initialize_tracer_from_Z`
- 2-day and 1-year runs complete; all five element budgets close at
  `imbalance_tolerance = 1.0e-9` for the full year
- 1-year run: zero truncations, no NaN, column-mean temperature drift
  +0.089 K/yr, salinity flat
- `./regression.sh` passes: restart files bitwise identical across
  48hr vs 24hr+24hr, `ocean.stats` matches `ref/` to `0.000e+00`
- migration can be switched off per group without changing the answer when it
  is left on; a group switched off is bit-identical to its non-migrating
  counterpart (`nvmmdz` vs `nmdz`, `nvmlgz` vs `nlgz`, `0.000e+00` over 7 days)

