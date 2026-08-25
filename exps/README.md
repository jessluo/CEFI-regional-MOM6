# exps 
This folder contains example configurations to run MOM6-SIS2-cobalt 

| directory    | Purpose |
| --------------    | ------- |
| ```OM4.single_column.COBALT/```     | 1D MOM6-cobalt exmaple - short CI regression test, BATS only |
| ```OM4.single_column.COBALT.station/``` | 1D MOM6-cobalt at any station, year-long run - use this for science runs |
| ```OM4p25.COBALT/```                | OM4 0.25deg MOM6-cobalt v3 exmaple |
| ```dumbbell/```                     | dumbbell exmaple |
| ```NWA12.COBALT/```                 | NWA12 MOM6-SIS2-cobalt example |
| ```NEP10.COBALT/```                 | NEP10 MOM6-SIS2-cobalt example |

If you do not have access to Gaea C6 and would like to run the NWA12.COBALT, NEP10.COBALT, or OM4p25.COBALT experiments, please contact us at oar.gfdl.cefi-support AT noaa DOT gov to get access to the needed datasets.

# OM4.single_column.COBALT
Users are advised to refer to the Dockerfile located at [ci/docker/Dockerfile.ci](../ci/docker/Dockerfile.ci). This Dockerfile includes the necessary steps to compile the code, download required input files, and execute the example 1D test case.

Users can also test the 1D case without using the container approach, please follow [this tutorial](https://cefi-regional-mom6.readthedocs.io/en/latest/BuildMOM6.html). The example dataset for the 1D case can be downloaded from `ftp://nomads.gfdl.noaa.gov/1/users/cefi/OM4.single_column.COBALT/data/1d_ci_datasets.tar.gz`.

Users can follow the instructions below to run 1D example on Gaea C5:

```console
git clone https://github.com/NOAA-GFDL/CEFI-regional-MOM6.git --recursive
cd CEFI-regional-MOM6/builds; ./linux-build.bash -m gaea -p ncrc5.intel23 -t debug -f mom6sis2
cd ../exps
ln -fs /gpfs/f5/cefi/world-shared/datasets ./
cd OM4.single_column.COBALT
sbatch run.sub
```
# OM4.single_column.COBALT.station
A relocatable version of the 1D case: it runs for a full year at any open-ocean
location, given only an `ocean_hgrid.nc`. Unlike `OM4.single_column.COBALT`,
which reads a `MOM_IC.nc` index-matched to the BATS grid, this configuration
interpolates global WOA13 / GLODAP / COBALT initial conditions onto whatever
grid is supplied, and enables atmospheric deposition of Fe, dust and N.

Build the grid for a station with `./setup_station.sh <name> <lat> <lon>
[bottom_depth_m]` (requires FRE-NCtools on PATH), then run as usual. See
[OM4.single_column.COBALT.station/README.md](OM4.single_column.COBALT.station/README.md)
for the initial-condition details and caveats.

Note this case needs the full-year JRA55-do forcing and the global initial
condition files. These are **not** part of the 1D CI dataset and are not
distributed with the CEFI datasets either -- contact Jessica Luo (@jessluo)
for access.

# OM4p25.COBALT
Users can follow the instructions below to run OM4 0.25 COBALTv3 example on Gaea C6.
```console
git clone https://github.com/NOAA-GFDL/CEFI-regional-MOM6.git --recursive
cd CEFI-regional-MOM6/builds; ./linux-build.bash -m gaea -p ncrc6.intel23 -t repro -f mom6sis2
cd ../exps
ln -fs /gpfs/f6/ira-cefi/world-shared/datasets ./
cd OM4p25.COBALT
sbatch driver.sh
```

# NWA12.COBALT
Users can follow the instructions below to run NWA12 example on Gaea C6.

```console
git clone https://github.com/NOAA-GFDL/CEFI-regional-MOM6.git --recursive
cd CEFI-regional-MOM6/builds; ./linux-build.bash -m gaea -p ncrc6.intel23 -t repro -f mom6sis2
cd ../exps
ln -fs /gpfs/f6/ira-cefi/world-shared/datasets ./
cd NWA12.COBALT
sbatch run.sub 
```

# NEP10.COBALT
Users can follow the instructions below to run NEP10 example on Gaea C6.

```console
git clone https://github.com/NOAA-GFDL/CEFI-regional-MOM6.git --recursive
cd CEFI-regional-MOM6/builds; ./linux-build.bash -m gaea -p ncrc6.intel23 -t repro -f mom6sis2
cd ../exps
ln -fs /gpfs/f6/ira-cefi/world-shared/datasets ./
cd NEP10.COBALT
sbatch run.sub
```
