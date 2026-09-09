# OM4.single_column.BLING

A two-day single-column BLING case at BATS, used as a fast regression test for
the BLING biogeochemistry in `src/ocean_BGC`.

It is the BLING counterpart of `exps/OM4.single_column.COBALT.station` and
shares that case's physics, JRA forcing and grid — only the biogeochemistry
differs. One core, about a minute per run, so the whole test is a few minutes.

## Running

```bash
./regression.sh
```

Expected output:

```
Check 1: restart reproducibility (48hr vs 24hr+24hr)
  identical  MOM.res.nc
  identical  ice_bling.res.nc
  identical  ice_model.res.nc
  identical  ocean_bling_airsea_flux.res.nc

Check 2: ocean.stats vs ref/ocean.stats (rel tol 1.0e-9)
  OK: largest difference 0.000e+00

REGRESSION TEST PASSED
```

Set `MACHINE` / `PLATFORM` if you are not on `mac-m1` / `osx-gnu`, `BUILD_TYPE`
if you did not build `repro`, or `EXE` to point at an executable directly.
`REL_TOL` loosens check 2.

## What the two checks cover

**Check 1 — restart reproducibility.** A single 48-hour run must produce
bitwise-identical restart files to a 24-hour run continued for a further 24
hours. This is the same test `../OM4.single_column.COBALT/driver.sh` applies to
COBALT. It needs no stored reference answer and is machine independent, so it
holds on any platform and compiler. It catches prognostic state that BLING
computes but fails to checkpoint, which is the failure mode that silently
corrupts long segmented runs.

**Check 2 — reference answer.** `ocean.stats` from the 48-hour run is compared
field by field against `ref/ocean.stats`, and truncation counts must match
exactly. This is what catches an answer change. Unlike check 1 it is only
bitwise on the machine that produced the reference; elsewhere expect agreement
to roughly 1e-13 and loosen `REL_TOL` accordingly.

If you change BLING deliberately and the new answers are correct, refresh the
reference with

```bash
./regression.sh --update-ref
```

and commit `ref/ocean.stats` alongside the code change, so the diff records that
answers moved.

## Prerequisites

* A MOM6-SIS2 build. BLING is compiled into the same `MOM6SIS2` executable as
  COBALT — `input.nml` (`do_generic_BLING`) and `field_table` are what select
  it, so there is no separate build target.
* The shared input files in `exps/datasets/station_1d/`, symlinked from
  `INPUT/`.
* The BATS grid, which `INPUT/` symlinks out of
  `../OM4.single_column.COBALT.station/INPUT/grids/BATS/`. Build it once with
  `./setup_station.sh BATS` in that experiment; it needs FRE-NCtools on `PATH`.
  Those symlinks are deliberately not version controlled.

## Files

| | |
|---|---|
| `input.nml_48hr`, `input.nml_24hr`, `input.nml_24hr_rst` | the three run segments; `regression.sh` symlinks one to `input.nml` |
| `diag_table_full` | diagnostics for the 48-hour run; the 24-hour runs use a header-only table |
| `field_table` | BLING tracers and their initial-condition sources |
| `ref/ocean.stats` | reference answer for check 2 |
| `compare_ocean_stats.py` | field-by-field `ocean.stats` comparison with a relative tolerance |

## Configuration notes

* **Initialisation is relocatable.** T/S come from global WOA13 monthly
  climatology via `INIT_LAYERS_FROM_Z_FILE = True`; `po4`, `o2`, `dic`, `alk`
  and the preformed/saturation carbon tracers come from their `*_src_file`
  entries in `field_table` (WOA13 and GLODAPv2), which `enforce_src_info = t`
  makes active. Point the grid symlinks at another station and the case runs
  there unchanged — but regenerate `ref/ocean.stats` if you do.
* **`fed`, `dop`, `chl`, `biomass_p` and `irr_mem` cold-start at zero** — there
  is no global climatology for them, so they carry `_requires_src_info = f` and
  `_requires_restart = f`. Two days is far too short for them to spin up; they
  are not physically meaningful here, but they are still exercised by both
  checks and so are still under test.
* **The full carbon system is on** (`do_carbon`, `do_carbon_pre`,
  `do_po4_pre`), so the test covers the mocsy carbonate solver and the
  preformed and saturation tracers, not just the core nutrient code.
  `do_14c = .false.`, to avoid needing an atmospheric `c14o2_flux` field.
* **BLING has no nitrogen or lithogenic tracers**, so `data_table` drops the
  NO3/NH4/lith deposition entries the COBALT cases carry, and adds
  `co2_sat_flux_pcair_atm` for the `dic_sat` gas exchange.

### `bury_caco3` must stay `.true.`

`generic_BLING_update_from_coupler` reads `runoff_tracer_flux` for `dic` and
`alk` unconditionally:

```fortran
call g_tracer_get_values(tracer_list,'dic','runoff_tracer_flux',bling%runoff_flux_dic,isd,jsd)
call g_tracer_get_values(tracer_list,'alk','runoff_tracer_flux',bling%runoff_flux_alk,isd,jsd)
```

but those two tracers are only registered with `flux_runoff = .true.` inside the
`if (bury_caco3)` branch, so with `bury_caco3 = .false.` the array is never
allocated. A bounds-checked build dies on the first coupled step with

```
generic_tracer_utils.F90:2065
Fortran runtime error: Array bound mismatch for dimension 1 of array 'array' (10/1)
```

and an unchecked build reads unallocated memory silently. `input.nml` therefore
sets `bury_caco3 = .true.`, which is also why `cased` appears in `field_table`.
Once the two `g_tracer_get_values` calls are given the same `if (bury_caco3)`
guard as the registrations, `.false.` becomes testable too.
