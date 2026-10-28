# Changes from upstream LISF

Source: https://github.com/NASA-LIS/LISF, branch `support/lisf-public-7.8`, commit `f2b68e623ae98e41207cf12489ecf9240fae348b` (2026-10-15). That is the branch the public testcase walkthrough (`docs/public_testcase_walkthrough`) says to use; the `v7.8.0-public` release tag does not compile with GNU Fortran (`ldt/WSF_OPL/TOOLSUBS_WSF.F90`, `IOR` of mixed integer kinds), which the support branch fixes.

This copy starts from that commit's file tree with no earlier history. No LISF source file is changed apart from one added section in `README.adoc`: the Fortran, C, configure and compile scripts, configs, docs, LICENSE.txt and the third-party license folders are as upstream has them. Everything below is an addition for building without the project's prebuilt library image.

## Left out

- `.github/workflows/` (`build-appimage.yaml`, `build-release-docs.yaml`, `build-web-docs.yaml`): upstream's GitHub Actions for the release AppImage and the documentation site. They build and publish upstream's own releases and pages and are not needed to build or run LISF. `.github/scripts/appimage/` (including `compile_lisf` and `lisf.env`, which the notes below refer to) is kept.

## Why

The documented builds take their libraries from a prebuilt image: the release AppImage workflow (upstream `.github/workflows/build-appimage.yaml`) starts from a `lisf_libraries` tarball image, and `.github/scripts/appimage/lisf.env` points every library variable into it. Without that image there was no list of what to install, and `./configure` asks about fifteen to twenty questions on the terminal, which a scripted or container build cannot answer. These additions give a build from public conda-forge packages, with the answers written down.

## 2026-10-28: `environment.yml`

The conda-forge packages this build was checked with, pinned: gfortran, gcc and gxx 12.4.0 (the installation guide lists GNU 11.2 or 12.1), MPICH 4.3.2, the MPICH builds of ESMF 8.9.1, HDF5 1.14.6, netCDF-C 4.10.0 and netCDF-Fortran 4.6.2, ecCodes 2.47.0, OpenJPEG 2.5.4, libjpeg-turbo and zlib. Also:

- ParallelIO 2.6.9, because conda-forge's `libesmf.so` is linked against it (it would come in with ESMF anyway; it is listed so the reason is written down).
- make, Perl (configure), Python 3 (the `makedep.py` and `plugins.py` steps of compile) and binutils (`ar` for `lis/make`), so the build does not depend on what the base system has.
- wget (the testcase's NLDAS-2 download script) and curl (the HDF4 download; it also reaches `portal.nccs.nasa.gov` where an older system OpenSSL in FIPS mode fails the handshake).

## 2026-10-28: `scripts/conda_build/build_hdf4.sh`

LDT needs HDF4 with its Fortran interface: step 1 of the testcase reads the Barlage maximum snow albedo map (an HDF4 file) and stops with "HDF4 required to process Barlage max snow albedo!" otherwise, although the installation guide calls HDF4 optional. conda-forge's `hdf4` has no Fortran interface. The script downloads the HDF Group's HDF4 4.2.16-2 release tarball from `support.hdfgroup.org` (a second HDF Group address as fallback), checks its sha256 (`a24b18312d421686031c2d66635f7d5abb2fe879f8a182b7e02797b0da8d1f6c`), and builds it static with `--enable-fortran --disable-netcdf` (the guide's options) plus `--enable-hdf4-xdr`, into a prefix you choose.

## 2026-10-28: `scripts/conda_build/build_lisf.sh`

Sets the `LDT_*`, `LIS_*` and `LVT_*` library variables for the conda environment (the same variables `lisf.env` sets for the image), then runs `./configure` with the answers piped in, one per line with a comment for each, and `./compile -j` for LDT (serial), LIS (MPI) and LVT (serial). It stops with a message if configure does not finish or an executable is not made. The answers are those of `.github/scripts/appimage/compile_lisf`, which the walkthrough's targets were made with, except:

- HDF-EOS2, GeoTIFF and LIBGEOTIFF off: conda-forge has no HDF-EOS2 or FortranGIS, and the public testcase uses neither.
- HDF4 on for LDT only (above).
- PIO on: it only adds `-lpioc` to the link line, which conda-forge's ESMF needs; without it every link fails with undefined references to `PIOc_*`.

For LDT the script also edits the generated `make/configure.ldt` so that the static Fortran HDF4 libraries are linked by full path, ahead of the Fortran-less `libmfhdf.so` that conda-forge's netCDF brings into the environment.

## 2026-10-28: failed build steps print their log

`build_lisf.sh` sent configure and compile output only to `<component>/conda_build_configure.log` and `conda_build_compile.log`, so a container build, which keeps no files from a failed step, showed only "lis compile failed, see lis/conda_build_compile.log" and never the compiler's error. When a step fails, the script now also prints the log's first error lines (up to 20) and its last 60 lines. Nothing else changes: a successful build prints the same as before.

## 2026-10-28: vim in `environment.yml`

`lis/make/Makefile` (line 11) appends `../offline` to the generated file list with `vim -e`, so the LIS compile stops with "make: vim: No such file or directory" (error 127) on a system without vim, such as a plain container image; LDT and LVT do not use it. `environment.yml` now installs vim 9.2.1252 from conda-forge, and Perl moves from 5.44.0 to 5.32.1, the Perl that conda-forge's vim is built against (Perl only runs the configure scripts). No source file changes, and the executables are built the same way.

Check (2026-10-28, fresh clone, 4 cores): environment 44 s, HDF4 31 s, LDT 2 min 02 s, LIS 6 min 12 s, LVT 6 min 37 s, with make using the environment's vim; the public testcase step 2 short run (2017-01-01 to 2017-01-03, 1 process) completes in 9.6 s at 74 MB with all 9 output files.

## 2026-10-28: README section

"Building with conda-forge (no library image)" in `README.adoc`, with the four commands.

## Check

On 2026-10-28 (Linux x86_64, 4 cores, no access to the library image), from a fresh `git clone` of this repository:

| Step | Wall time | Peak memory |
|---|---|---|
| `conda env update -f environment.yml` into an empty environment (solve, 103 packages downloaded, install) | 50 s | 0.3 GB |
| `build_hdf4.sh` (download, configure, make, install) | 44 s | 0.07 GB |
| `build_lisf.sh ldt` | 3 min 09 s | 0.6 GB |
| `build_lisf.sh lis` | 4 min 55 s | 0.6 GB |
| `build_lisf.sh lvt` | 5 min 57 s | 0.5 GB |

The environment solves in seconds, so no lock file is included. The environment takes 1.6 GB and the source tree with objects about 0.5 GB.

Then the public testcase, inputs from `portal.nccs.nasa.gov/lisdata_pub/Tutorials/Web_Version/` (steps 1, 2, 6 and 7) and NLDAS-2 forcing from GES DISC for 2017-01-01 to 2017-02-01 (768 files, 1.3 GB, the testcase's own `INPUT/wget_gesdisc_nldas2.sh` with the end date moved), runs with no network:

- **LDT step 1** (`./LDT ldt.config.step1.noah36_params`, 21 s, 7.1 GiB peak): `lis_input.nldas.noah36.d01.nc` matches `target_step1`: 20 of 23 variables identical, SLOPE, ASPECT and TBOT differ only at float rounding (largest 9.2e-5 K in TBOT).
- **LIS step 2, January** (shipped config with the end date set to 2017-02-01): serial 2 min 20 s, 76 MB; `mpirun -np 4` with 2 x 2 processors 53 s, 84 MB per rank. All 126 output files of the 4-rank run have the same values as the serial run (only file timestamps differ). Against `target_step2` over the 124 six-hourly files: forcing identical; soil moisture (all layers) bias -5e-8 and RMSE 1e-4 m3/m3, r = 0.999999; Qle RMSE 0.11 W/m2; SWE RMSE 0.017 kg/m2. The walkthrough says outputs "may not be identical, but any differences reported should be small".
- **LVT step 7** (`lvt.config.step7.noah36_ol-da` pointed at `target_step2` and `target_step6`, 5 s): `LVT_MEAN_FINAL.201801010000.d01.nc` has every variable identical to `target_step7`, and 6 of the 7 text files are byte-identical; `MEAN_ASC_Fort_Cobb_RootMoist_v_RootMoist.dat` differs in the sixth significant digit on two lines (0.255861 against 0.255860).

An earlier build with the same libraries (2026-10-25) gave the same LDT differences and the same level of LIS agreement.

Tag: `lisf-public-7.8-f2b68e6.post1`.
