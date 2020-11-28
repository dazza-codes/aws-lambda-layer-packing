#!/bin/bash

SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(readlink -f "$SCRIPT_PATH")

# shellcheck disable=SC1090
source "$SCRIPT_PATH/layer_create_zip.sh"

py_version=$(python --version | grep -o -E '[0-9]+[.][0-9]+')
py_ver=$(echo "py${py_version}" | sed -e 's/\.//g')

# environment variables should define the following:
#LIB_NAME
#LIB_VERSION
#LIB_PACKAGE
LAYER_PREFIX="${py_ver}-${LIB_NAME}-${LIB_VERSION}"

TMP_LAYER_ZIP="/tmp/${py_ver}_lambda_layer.zip"

# this assumes /tmp/requirements.txt exists
REQUIREMENTS_FILE=/tmp/requirements.txt

crash() {
  echo "OOPS - something went wrong!"
  exit 1
}

#
# Package Complete Dependencies
#

create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LIB_PACKAGE}" || crash
echo "Created /tmp/${LIB_PACKAGE}"
echo
echo

#
# Package - No Dependencies
#
# This section depends on the Makefile recipe for `poetry-export` to
# create /tmp/project installation using
# 	pip install --no-compile --no-deps -t /tmp/project-no-deps {wheel}

py_version=$(python --version | grep -o -E '[0-9]+[.][0-9]+')
py_ver=$(echo "py${py_version}" | sed -e 's/\.//g')
package_dir=$(mktemp -d -t tmp_python_XXXXXX)
package_dst=${package_dir}/python/lib/python${py_version}/site-packages
mkdir -p "$package_dst"
echo "$package_dst"

cp -rf /tmp/project-no-deps/* "$package_dst/"

echo "Zipping packages for lambda layer..."
layer_zip="/tmp/${LAYER_PREFIX}-nodeps.zip"
rm -f "${layer_zip}"
pushd "${package_dir}" >/dev/null || crash
zip -rq -D -X -9 -A --compression-method deflate --symlinks "${layer_zip}" python
# also add the project package to the LIB-PACKAGE (which only contains dependencies)
zip -rq -D -X -9 -A --compression-method deflate --symlinks "/tmp/${LIB_PACKAGE}" python
ls "${layer_zip}" >/dev/null || crash
unzip -q -t "${layer_zip}" || crash
echo "created ${layer_zip}"
popd >/dev/null || exit 1
rm -rf "$package_dir"
echo
echo


#
# Isolate Package Dependencies
#
# The total layer size for all requirements can be too large for lambda; so
# collect only the main dependencies from the requirements file and
# group them into layers for packages that belong together.  These
# could be modified to be optional extras in the pyproject.toml but
# this optimization for lambda could break easy use of the package
# for common purposes.
#
# There is some potential duplicate data from rasterio and fiona in
# python/lib/python3.6/site-packages/rasterio/gdal_data
# python/lib/python3.6/site-packages/rasterio/proj_data
# python/lib/python3.6/site-packages/fiona/proj_data
# python/lib/python3.6/site-packages/fiona/gdal_data

# If the packages are installed already, `pip show` can be used
# to get package version data, e.g.
#python -m pip show boto3 | awk '/^Version:/ { print $2 }'

get_package_spec() {
  package=$1
  grep -o -E "${package}"'[=><]+[0-9.]*' "${REQUIREMENTS_FILE}"
}

get_package_version() {
  package=$1
  grep -o -E "${package}"'[=><]+[0-9.]*[;]?' "${REQUIREMENTS_FILE}" | grep -o -E '[=><]+[0-9.]*' | grep -o -E '[^=><][0-9.]*'
}

#AIOBOTOCORE=$(grep 'aiobotocore==' "${REQUIREMENTS_FILE}")

S3FS=$(grep 's3fs==' "${REQUIREMENTS_FILE}")
FASTPARQUET=$(grep 'fastparquet==' "${REQUIREMENTS_FILE}")

DASK_DELAYED='dask[delayed]>=2.22'
DASK_ALL='dask>=2.22'
NUMPY=$(grep 'numpy==' "${REQUIREMENTS_FILE}")
PANDAS=$(grep 'pandas==' "${REQUIREMENTS_FILE}")
PYTZ=$(grep 'pytz==' "${REQUIREMENTS_FILE}")

GEOPANDAS=$(grep 'geopandas==' "${REQUIREMENTS_FILE}")
FIONA=$(grep 'fiona==' "${REQUIREMENTS_FILE}")
SHAPELY=$(grep 'shapely==' "${REQUIREMENTS_FILE}")
PYPROJ=$(grep 'pyproj==' "${REQUIREMENTS_FILE}") # for rasterio/CRS

PYCRS=$(grep 'pycrs==' "${REQUIREMENTS_FILE}") # for rasterio/CRS
RASTERIO=$(grep 'rasterio==' "${REQUIREMENTS_FILE}")
RASTERSTATS=$(grep 'rasterstats==' "${REQUIREMENTS_FILE}")
S2SPHERE=$(grep 's2sphere==' "${REQUIREMENTS_FILE}")

# generic utilities for python 3.6
DATACLASSES='dataclasses==0.7'
REQUESTS=$(grep 'requests==' "${REQUIREMENTS_FILE}") # not bundled with botocore any more

#
# lib collections, based on `poetry show -t {lib}`
#
# - add dataclasses to everything, it is too small to be it's own layer
# - add requests as needed, it's only 100's of KB
# - add s2sphere as needed, it's only 100's of KB
#

# shellcheck disable=SC2034
GEOPANDAS_LIBS=" $GEOPANDAS $FIONA $NUMPY $PANDAS $PYPROJ $SHAPELY $S2SPHERE "

# shellcheck disable=SC2034
RASTER_LIBS=" $RASTERIO $RASTERSTATS $PYPROJ $PYCRS $S2SPHERE "

# shellcheck disable=SC2034
PARQUET_LIBS=" $FASTPARQUET $S3FS "

# shellcheck disable=SC2034
SCI_LIBS=" $DASK $NUMPY $PANDAS "

cat >/tmp/requirements.txt <<REQUIREMENTS
${DATACLASSES}
${REQUESTS}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-utils.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-utils.zip"
echo
echo

cat >/tmp/requirements.txt <<REQUIREMENTS
${S3FS}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-s3fs.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-s3fs.zip"
echo
echo

# fastparquet depends on pandas/numpy, numba, thrift
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-numpy.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-numpy.zip"
echo
echo

## python layer for pytz
cat >/tmp/requirements.txt <<REQUIREMENTS
${PYTZ}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-pytz.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-pytz.zip"
echo
echo

## python layer for pandas
## - numpy (from pandas)
## - pytz (from pandas)
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
${PANDAS}
${PYTZ}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-pandas.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-pandas.zip"
echo
echo

## python layer for geopandas, includes:
## - pandas (from geopandas)
## - pyproj (from geopandas)
## - shapely (from geopandas)
## - fiona (from geopandas)
## - numpy (from pandas -> geopandas)
## - pytz (from pandas -> geopandas)
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
${PANDAS}
${PYPROJ}
${PYTZ}
${GEOPANDAS}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-geopandas.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-geopandas.zip"
echo
echo

# fastparquet depends on pandas/numpy, numba, thrift
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
${PANDAS}
${PYTZ}
${FASTPARQUET}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-fastparquet.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-fastparquet.zip"
echo
echo

## python layer for pyarrow - it has been too big for an AWS lambda layer
## pyarrow depends on numpy
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
pyarrow
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-pyarrow.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-pyarrow.zip"
echo
echo

## python layer for dask[delayed]
cat >/tmp/requirements.txt <<REQUIREMENTS
${DASK_DELAYED}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-dask_delayed.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-dask_delayed.zip"
echo
echo

## python layer for dask[complete]
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
${PANDAS}
${DASK_ALL}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-dask.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-dask.zip"
echo
echo

## python layer for pyproj
cat >/tmp/requirements.txt <<REQUIREMENTS
${PYPROJ}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-pyproj.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-pyproj.zip"
echo
echo

## python layer for rasterio (depends on numpy etc)
#rasterio_ver=${RASTERIO/*==}
cat >/tmp/requirements.txt <<REQUIREMENTS
${NUMPY}
${RASTERIO}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-rasterio.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-rasterio.zip"
echo
echo

## python layer for s2sphere
cat >/tmp/requirements.txt <<REQUIREMENTS
${S2SPHERE}
REQUIREMENTS
create_layer_zip
mv "${TMP_LAYER_ZIP}" "/tmp/${LAYER_PREFIX}-s2sphere.zip" || crash
echo "Created /tmp/${LAYER_PREFIX}-s2sphere.zip"
echo
echo

# When this runs in a docker container with the root user, try
# to set permissions and ownership on the .zip artifacts
USER_ID=${USER_ID:-$(id --user)}
GROUP_ID=${GROUP_ID:-$(id --group)}
chmod a+rw /tmp/*.zip || true
chown "${USER_ID}":"${GROUP_ID}" /tmp/*.zip || true
