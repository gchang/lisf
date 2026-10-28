#!/bin/bash
# Build HDF4 with its Fortran interface into a prefix, for LDT.
#
# LDT reads HDF4 parameter files (for example the Barlage maximum snow albedo in the public
# testcase) through the HDF4 Fortran interface. conda-forge's hdf4 package is built without
# Fortran, so this script builds HDF4 4.2.16-2 from the HDF Group's release tarball with the
# options the installation guide gives (--enable-fortran --disable-netcdf), static only, so
# that LDT links these libraries directly and not the Fortran-less ones in the environment.
#
# Usage (inside the activated environment from environment.yml):
#   scripts/conda_build/build_hdf4.sh <install prefix> [work dir]
# JOBS sets the number of make jobs (default 4). The work dir (default: a new temporary
# folder) holds the download and the source tree and can be deleted afterwards.
set -euo pipefail

prefix=${1:?usage: build_hdf4.sh <install prefix> [work dir]}
work=${2:-$(mktemp -d)}
: "${CONDA_PREFIX:?activate the lisf conda environment first}"
E=$CONDA_PREFIX
jobs=${JOBS:-4}

version=4.2.16-2
tarball=hdf-$version.tar.gz
sha256=a24b18312d421686031c2d66635f7d5abb2fe879f8a182b7e02797b0da8d1f6c
urls=(
  "https://support.hdfgroup.org/ftp/HDF/releases/HDF$version/src/$tarball"
  "https://support.hdfgroup.org/archive/support/ftp/HDF/releases/HDF$version/src/$tarball"
)

mkdir -p "$work" "$prefix"
prefix=$(cd "$prefix" && pwd)
cd "$work"
if ! echo "$sha256  $tarball" | sha256sum -c --status 2>/dev/null; then
  for u in "${urls[@]}"; do
    curl -fsSL --retry 3 -o "$tarball" "$u" && break
  done
fi
echo "$sha256  $tarball" | sha256sum -c
rm -rf "hdf-$version"
tar -xzf "$tarball"
cd "hdf-$version"

./configure --prefix="$prefix" \
  --enable-fortran --disable-netcdf --enable-hdf4-xdr \
  --disable-shared --enable-static --with-pic --disable-java \
  --with-jpeg="$E" --with-zlib="$E" --with-szlib=no \
  CC="$E/bin/gcc" F77="$E/bin/gfortran" FC="$E/bin/gfortran" \
  CFLAGS="-O2 -fPIC -I$E/include" \
  FFLAGS="-O2 -fPIC -fallow-argument-mismatch" \
  LDFLAGS="-L$E/lib -Wl,-rpath,$E/lib" > "$prefix/configure.log" 2>&1 \
  || { echo "HDF4 configure failed, see $prefix/configure.log" >&2; exit 1; }
make -j "$jobs" > "$prefix/make.log" 2>&1 \
  || { echo "HDF4 make failed, see $prefix/make.log" >&2; exit 1; }
make install >> "$prefix/make.log" 2>&1
for lib in libmfhdf.a libdf.a libxdr.a; do
  [[ -f $prefix/lib/$lib ]] || { echo "missing $prefix/lib/$lib" >&2; exit 1; }
done
echo "HDF4 $version with Fortran installed in $prefix"
