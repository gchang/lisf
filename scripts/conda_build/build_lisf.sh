#!/bin/bash
# Configure and compile LDT, LIS and LVT against the conda-forge libraries of environment.yml,
# without the prebuilt library image and without typing the configure answers.
#
# Usage (inside the activated environment, after build_hdf4.sh):
#   HDF4_PREFIX=<build_hdf4.sh prefix> scripts/conda_build/build_lisf.sh [ldt] [lis] [lvt]
# With no arguments all three are built. JOBS sets the make jobs (default 4). Each component's
# configure and compile output goes to <component>/conda_build_configure.log and
# <component>/conda_build_compile.log; when a step fails, its first error lines and the end of its
# log are also printed, so the cause shows in a build that keeps no files. The executables are
# ldt/LDT, lis/LIS and lvt/LVT.
#
# The answers follow the project's own .github/scripts/appimage/compile_lisf (the default
# settings, which the public testcase walkthrough asks for because its target outputs were made
# with them), with these differences:
#   - HDF-EOS2, GeoTIFF and LIBGEOTIFF are off: conda-forge has no FortranGIS or HDF-EOS2, and
#     the public testcase does not use them.
#   - HDF4 is on for LDT only (the testcase's maximum snow albedo map is an HDF4 file) and off
#     for LIS and LVT.
#   - PIO is on. It only adds -lpioc to the link line, which conda-forge's libesmf.so needs
#     because it is built against an external ParallelIO; without it every link fails with
#     undefined references to PIOc_* routines.
set -euo pipefail

: "${CONDA_PREFIX:?activate the lisf conda environment first}"
: "${HDF4_PREFIX:?set HDF4_PREFIX to the install prefix given to build_hdf4.sh}"
E=$CONDA_PREFIX
repo=$(cd "$(dirname "$0")/../.." && pwd)
jobs=${JOBS:-4}
components=("$@")
(( ${#components[@]} )) || components=(ldt lis lvt)

# Library locations, as .github/scripts/appimage/lisf.env sets them for the library image
for app in LDT LIS LVT; do
  export ${app}_ARCH=linux_gfortran ${app}_FC=mpif90 ${app}_CC=mpicc
  export ${app}_JPEG=$E ${app}_OPENJPEG=$E ${app}_ECCODES=$E ${app}_NETCDF=$E ${app}_HDF5=$E
  export ${app}_MODESMF=$E/mod ${app}_LIBESMF=$E/lib ${app}_PIO=$E
done
export LIS_SPMD=parallel LIS_CPPC=mpicxx
export LDT_HDF4=$HDF4_PREFIX LDT_RPC="-L$HDF4_PREFIX/lib -lxdr"
export LANG=C
export PATH=$E/bin:$PATH
export LD_LIBRARY_PATH=$E/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

# One answer per configure prompt, in the order configure asks them.
ldt_answers=(
  0  # Parallelism (0-serial, 1-dmpar): serial
  2  # Optimization level: 2 (default)
  2  # Assume little/big_endian data format (1-little, 2-big): big (default)
  2  # Use GRIBAPI/ECCODES? (0-neither, 1-gribapi, 2-eccodes): ecCodes
  4  # NETCDF version (3 or 4): 4
  1  # NETCDF use shuffle filter?: yes
  1  # NETCDF use deflate filter?: yes
  1  # NETCDF use deflate level? (1 to 9, 0-no): 1
  1  # Use HDF4?: yes (Fortran HDF4 from build_hdf4.sh)
  1  # Use HDF5?: yes
  0  # Use HDFEOS?: no (not on conda-forge)
  0  # Enable GeoTIFF support?: no (needs FortranGIS, not on conda-forge)
  0  # Enable LIBGEOTIFF support?: no
  1  # Include date/time stamp history?: yes (default)
  1  # Use PIO?: yes (adds -lpioc, needed by conda-forge's libesmf.so)
)
lis_answers=(
  1  # Parallelism (0-serial, 1-dmpar): dmpar (default)
  2  # Optimization level: 2 (default)
  2  # Assume little/big_endian data format (1-little, 2-big): big (default)
  2  # Use GRIBAPI/ECCODES? (0-neither, 1-gribapi, 2-eccodes): ecCodes
  0  # Enable AFWA-specific grib configuration settings?: no (default)
  1  # Use NETCDF?: yes
  4  # NETCDF version (3 or 4): 4
  1  # NETCDF use shuffle filter?: yes
  1  # NETCDF use deflate filter?: yes
  1  # NETCDF use deflate level? (1 to 9, 0-no): 1
  0  # Use HDF4?: no
  1  # Use HDF5?: yes
  0  # Use HDFEOS?: no (not on conda-forge)
  0  # Use MINPACK?: no (default)
  0  # Use LIS-CRTM?: no (default)
  0  # Use LIS-CMEM?: no (default)
  0  # Use LIS-LAPACK?: no (default)
  0  # Use PETSc?: no (default)
  0  # Enable USAF LIS75 SM DA codes?: no (default)
  1  # Use PIO?: yes (adds -lpioc, needed by conda-forge's libesmf.so)
)
lvt_answers=(
  2  # Optimization level: 2 (default)
  2  # Assume little/big_endian data format (1-little, 2-big): big (default)
  2  # Use GRIBAPI/ECCODES? (1-gribapi, 2-eccodes): ecCodes
  1  # Use NETCDF?: yes
  4  # NETCDF version (3 or 4): 4
  1  # NETCDF use shuffle filter?: yes
  1  # NETCDF use deflate filter?: yes
  1  # NETCDF use deflate level? (1 to 9, 0-no): 1
  0  # Use HDF4?: no
  1  # Use HDF5?: yes
  0  # Use HDFEOS?: no (not on conda-forge)
  0  # Enable AFWA-specific grib configuration settings?: no (default)
  0  # Enable GeoTIFF support?: no (needs FortranGIS, not on conda-forge)
  0  # Use MATLAB support?: no (default)
  1  # Use PIO?: yes (adds -lpioc, needed by conda-forge's libesmf.so)
)

# Print the first error lines and the last 60 lines of a failed step's log to stderr.
show_log() {
  {
    echo "---- first error lines of $1 ----"
    grep -n -i -m 20 -E 'error|fatal|cannot|not found|killed' "$1" || echo "(none matched)"
    echo "---- last 60 lines of $1 ----"
    tail -n 60 "$1"
    echo "---- end of $1 ----"
  } >&2
}

for c in "${components[@]}"; do
  case $c in
    ldt) answers=("${ldt_answers[@]}");;
    lis) answers=("${lis_answers[@]}");;
    lvt) answers=("${lvt_answers[@]}");;
    *) echo "unknown component '$c' (use ldt, lis or lvt)" >&2; exit 2;;
  esac
  cd "$repo/$c"
  printf '%s\n' "${answers[@]}" | ./configure > conda_build_configure.log 2>&1 \
    || { echo "$c configure failed, see $c/conda_build_configure.log" >&2; show_log conda_build_configure.log; exit 1; }
  grep -q 'generated successfully' conda_build_configure.log \
    || { echo "$c configure did not finish, see $c/conda_build_configure.log" >&2; show_log conda_build_configure.log; exit 1; }
  if [[ $c == ldt ]]; then
    # Link the Fortran-enabled static HDF4 by full path, ahead of the Fortran-less
    # libmfhdf.so that the environment's netCDF brings in.
    sed -i 's|-L$(LIB_HDF4) -lmfhdf -ldf|$(LIB_HDF4)/libmfhdf.a $(LIB_HDF4)/libdf.a|' make/configure.ldt
  fi
  exe=${c^^}
  rm -f "$exe"
  ./compile -j "$jobs" > conda_build_compile.log 2>&1 || true
  [[ -x $exe ]] || { echo "$c compile failed, see $c/conda_build_compile.log" >&2; show_log conda_build_compile.log; exit 1; }
  echo "built $repo/$c/$exe"
done
