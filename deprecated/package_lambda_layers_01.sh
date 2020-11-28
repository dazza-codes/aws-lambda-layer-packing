#!/bin/bash

prefix="${PREFIX:-/opt}"

py_version="${PY_VERSION:-3.6}"
py_ver="${PY_VER:-py36}"

layer_package="${py_ver}_layer"

export PYTHONDONTWRITEBYTECODE=true

clean_python_packages () {
  site=$1
  find "$site" -type d -name '__pycache__' -exec rm -rf {} +
  find "$site" -type d -name 'tests' -exec rm -rf {} +
  find "$site" -type d -name '*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name '*.py[co]' -exec rm -rf {} +
  #find "$site" -type d -name '*.egg-info' -exec rm -rf {} +
  #find "$site" -type d -name 'datasets' -exec rm -rf {} +
}

crash () {
  echo
  echo "OOPS - something went wrong!"
  echo
  exit 1
}


#
# The destination path should be where AWS lambda unpacks a layer .zip file
#
dst=${prefix}/python/lib/python${py_version}/site-packages
mkdir -p "${dst}"
pushd "${prefix}" || crash


## Use `poetry show -t --no-dev`, `pip freeze` or `pipdeptree` to check poetry installed
## versions and pin common deps to use the same, consistent versions in lambda layers.
#
# AWS lambda bundles the python SDK in lambda layers, but advise that bundling it into
# a layer is a best practice.
# https://aws.amazon.com/blogs/compute/upcoming-changes-to-the-python-sdk-in-aws-lambda/
#
# See also the current versions of botocore in lambda - listed at
# https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html
#
# Also consider what is supported by aiobotocore, see:
# https://github.com/aio-libs/aiobotocore/blob/master/setup.py


BOTO3='boto3==1.12.3'
BOTOCORE='botocore==1.15.3'
AIOBOTOCORE='aiobotocore==0.12.0'
REQUESTS="requests==2.23.0"  # not bundled with botocore any more
S3FS='s3fs==0.3.5'
FASTPARQUET='fastparquet==0.3.2'

DATACLASSES='dataclasses==0.7'

DASK='dask[delayed]==2.10.1'
DASK_ALL='dask[complete]==2.10.1'

GEOPANDAS='geopandas==0.5.1'
NUMPY='numpy==1.18.2'
PANDAS='pandas==1.0.2'
XARRAY='xarray==0.15.1'
ZARR='zarr==2.4.0'

PYPROJ='pyproj==2.4.2'  # for rasterio/CRS
RASTERIO='rasterio==1.1.2'
S2SPHERE='s2sphere==0.2.5'

PG8000='pg8000==1.15.2'
BS4='beautifulsoup4==4.9.0'
XMLTODICT='xmltodict==0.12.0'


rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${BS4}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_beautifulsoup4.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${PG8000}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_pg8000.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${XMLTODICT}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_xmltodict.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


rm -rf "${dst:?}"/*
python -m pip install -t "$dst" \
  "${AIOBOTOCORE}" "${BOTO3}" "${BOTOCORE}" "${DASK}" "${DATACLASSES}" "${REQUESTS}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_boto3.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


rm -rf "${dst:?}"/*
python -m pip install -t "$dst" \
  "${AIOBOTOCORE}" "${BOTO3}" "${BOTOCORE}" "${DASK}" "${DATACLASSES}" "${REQUESTS}" "${S3FS}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_s3fs.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


# fastparquet depends on pandas/numpy, numba, thrift
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" \
  "${DATACLASSES}" "${NUMPY}" "${PANDAS}" "${FASTPARQUET}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_fastparquet.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for pyarrow - it has been too big for an AWS lambda layer
## pyarrow depends on numpy
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" pyarrow
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_pyarrow.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for pandas
## - numpy (from pandas)
## - pytz (from pandas)
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PANDAS}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_pandas.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for geopandas, includes:
## - pandas (from geopandas)
## - pyproj (from geopandas)
## - shapely (from geopandas)
## - fiona (from geopandas)
## - numpy (from pandas -> geopandas)
## - pytz (from pandas -> geopandas)
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PANDAS}" "${PYPROJ}" "${GEOPANDAS}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_geopandas.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for xarray, includes:
## - pandas (from xarray)
## - numpy (from pandas -> geopandas)
## - pytz (from pandas -> geopandas)
## - plus zarr
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PANDAS}" "${XARRAY}" "${ZARR}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_xarray.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for dask[delayed]
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PANDAS}" "${DASK}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_dask_delayed.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for dask[complete]
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PANDAS}" "${DASK_ALL}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_dask.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for rasterio (depends on numpy etc); added pyproj too
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${NUMPY}" "${PYPROJ}" "${RASTERIO}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_rasterio.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"


## python layer for s2sphere; added pyproj too
rm -rf "${dst:?}"/*
python -m pip install -t "$dst" "${DATACLASSES}" "${PYPROJ}" "${S2SPHERE}"
clean_python_packages "$dst"
python -m pip list --path "$dst"
zip_file="/tmp/${layer_package}_s2sphere.zip"
rm -f "${zip_file}"
zip -q -r9 --symlinks "${zip_file}" python
unzip -q -t "${zip_file}" || crash
echo "created ${zip_file}"
