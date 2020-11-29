#!/bin/bash

# When modifying any package cleanup or optimizations, use `make layer-test` to
# check that the package changes do not cause failures in the project test suite.

# strip can break some packages, see https://github.com/pypa/manylinux/issues/119
# it's useful for layers that are BIG, but skip it for smaller layers.

SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(readlink -f "$SCRIPT_PATH")

crash () {
  err=${1:-"Unknown error"}
  echo "$err"
  exit 1
}

# Pin the AWS SDK lambda packages to the provided versions, so
# they can be removed from lambda layers.  The strategy is to
# add the SDK libs as explicit requirements to every layer build
# and then remove them from the build.  The `create_layer_zip`
# function will call `clean_aws_packages` to remove the AWS SDK
# libs listed below.
#
# fix boto3 and botocore to the current lambda layer versions
# https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html
#
# This could also help to detect when a project dependency requires a version of these
# AWS SDK libs that is different from the lambda versions.  To get this list:
# `ls -1d /var/runtime/*.dist-info` in the lambci container.  These are
# essentially the `boto3` library and the dependency tree it requires.

## Note that getting these dynamically as follows could result in versions
## that are not documented or in the lambda container, if any pip installations
## have run to override those versions; so manual updates below are required.
#BOTO3_VERSION=$(python -c 'import boto3; print(boto3.__version__)')
#BOTOCORE_VERSION=$(python -c 'import botocore; print(botocore.__version__)')

pin_lambda_sdk () {
  requirements_file=$1
  # remove and replace all the AWS SDK libs
  sed -i '/^boto3/d' "${requirements_file}"
  sed -i '/^botocore/d' "${requirements_file}"
  sed -i '/^docutils/d' "${requirements_file}"
  sed -i '/^jmespath/d' "${requirements_file}"
  sed -i '/^python_dateutil/d' "${requirements_file}"
  sed -i '/^s3transfer/d' "${requirements_file}"
  sed -i '/^six/d' "${requirements_file}"
  sed -i '/^urllib3/d' "${requirements_file}"

  cat >> "${requirements_file}" <<REQUIREMENTS
boto3~=1.15.16
botocore~=1.18.16
REQUIREMENTS
}


clean_python_metadata () {
  site=$1
  echo "Cleaning python package metadata from $site ..."
  find "$site" -type d -name '*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name '*.egg-info' -exec rm -rf {} +
}

clean_python_packages () {
  site=$1
  echo "Optimizing python package installations in $site ..."
  find "$site" -type d -name '__pycache__' -exec rm -rf {} +
  find "$site" -type f -name '*.py[co]' -exec rm -f {} +
  # remove all the test or tests modules but not the packages
  find "$site" -type d -name 'test' | while read -r d; do
    find "$d" -type f -not -name '__init__.py' -exec rm {} \;
  done
  find "$site" -type d -name 'tests' | while read -r d; do
    find "$d" -type f -not -name '__init__.py' -exec rm {} \;
  done
#  # numpy does not lazy-load numpy.testing
#  for d in $(find "$site" -type d -name 'testing'); do
#    find "$d" -type f -not -name '__init__.py' -exec rm {} \;
#  done
}

strip_binary_libs() {
  site=$1
  echo "Optimizing binary libraries *.so.* in $site ..."
  find "$site" -type f \( -iname '*.so.*' \
    ! -iname 'libgfortran-*' \
    ! -iname 'libnetcdf-*' \
    ! -iname 'libgdal*' \
    ! -iname 'libhdf5*' \
    ! -iname 'libproj*' \) \
    -exec strip {} \;
}

strip_cpython_libs() {
  site=$1
  echo "Optimizing cpython compiled libraries in $site ..."
  find "$site" -type f \( -iname '*.cpython*.so' ! -iname '*netCDF4*' \) -exec strip {} \;
}

clean_numpy () {
  site=$1
  if [ -d "${site}/numpy" ]; then
    # This could break tests using https://numpy.org/doc/stable/reference/routines.testing.html
    # watch https://github.com/numpy/numpy/issues/17620
    echo "Cleaning numpy in $site ..."
    find "${site}/numpy/doc" -type f -not -name '__init__.py' -exec rm {} \;

    # rasterstats uses numpy.distutils at runtime
    #find "${site}/numpy/distutils" -type f -not -name '__init__.py' -exec rm {} \;

    # numpy does not lazy-load numpy.testing
    #find "${site}/numpy/testing" -type f -not -name '__init__.py' -exec rm {} \;

    # strip_binary_libs will take care of stripping numpy and other binary libs
    #find "${site}/numpy" -type f \( -iname '*.so.*' ! -iname '*libgfortran*' \) -exec strip {} \;
  fi
}

clean_pandas () {
  site=$1
  if [ -d "${site}/pandas" ]; then
    echo "Cleaning pandas in $site ..."
    # the 'clean_python_packages' function already deletes the tests files
    #find "${site}/pandas/tests" -type f -not -name '__init__.py' -exec rm {} \;
  fi
}

clean_pydantic () {
  site=$1
  # removing cpython compiled libs can reduce pydantic down < 1Mb
  # without impairing the functionality (there is a small performance hit)
  if [ -d "${site}/pydantic" ]; then
    echo "Cleaning pydantic in $site ..."
    find "${site}/pydantic" -type f -name '*.cpython*.so*' -exec rm {} \;
  fi
}

clean_fastparquet () {
  site=$1
  if [ -d "${site}/fastparquet" ]; then
    echo "Cleaning fastparquet in $site ..."
    rm -rf "${site}/fastparquet/test"
    find "${site}/llvmlite/binding" -type f -name 'libllvmlite.so' -exec strip {} \;
  fi
}

hack_shared_libs () {
  site=$1

  export GDAL_DATA="${site}/share/gdal_data"
  export PROJ_DATA="${site}/share/proj_data"
  mkdir -p "${GDAL_DATA}"
  mkdir -p "${PROJ_DATA}"

  export SHARED_LIBS="${site}/share/libs"
  mkdir -p "${SHARED_LIBS}"

  find "${site}" -type d -name 'gdal_data' | while read -r data_path; do
    if [ "$data_path" != "$GDAL_DATA" ]; then
      rsync -auq "$data_path"/ "$GDAL_DATA"/
      rm -rf "$data_path"
      ln -s "$GDAL_DATA" "$data_path"
    fi
  done

  find "${site}" -type d -name 'proj_data' | while read -r data_path; do
    if [ "$data_path" != "$PROJ_DATA" ]; then
      rsync -auq "$data_path"/ "$PROJ_DATA"/
      rm -rf "$data_path"
      ln -s "$PROJ_DATA" "$data_path"
    fi
  done

  # TODO: consider using an AWS Lambda LD_LIBRARY_PATH vs. a custom python path, e.g.
  # LD_LIBRARY_PATH=/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/task:/var/task/lib:/opt/lib

  # Updating the LD_LIBRARY_PATH can fix symbol resolution
  export LD_LIBRARY_PATH="$SHARED_LIBS:$LD_LIBRARY_PATH"

  move_to_shared_libs () {
    lib_path=$1
    if [ -d "$lib_path" ]; then
      rsync -auq "$lib_path"/ "$SHARED_LIBS"/
      rm -rf "$lib_path"
      ln -s "$SHARED_LIBS" "$lib_path"
    fi
  }

  move_to_shared_libs "$site"/rasterio.libs
  move_to_shared_libs "$site"/Fiona.libs
  move_to_shared_libs "$site"/numpy.libs
  move_to_shared_libs "$site"/pyproj/.libs
  move_to_shared_libs "$site"/shapely/.libs

  # TODO: remove this hack on shapely/geos.py
  # due to https://github.com/Toblerity/Shapely/issues/1013
  # try a hack to patch shapely/geos.py
  patch "$site"/shapely/geos.py "$SCRIPT_PATH"/patches/shapely/geos.patch

# # To check for missing symbols, use:
# find "$SHARED_LIBS"/ -name "*.so*" | while read lib_name; do
#   ldd -r "$lib_name" 2>&1
# done

}


# The lambda runtime should provide the following packages,
# so it should be possible to remove them all from layers.

clean_aws_packages () {
  site=$1
  echo "Cleaning AWS SDK packages from $site ..."
  find "$site" -type d -name 'boto3' -exec rm -rf {} +
  find "$site" -type d -name 'boto3-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'botocore' -exec rm -rf {} +
  find "$site" -type d -name 'botocore-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'dateutil' -exec rm -rf {} +
  find "$site" -type d -name 'python_dateutil-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'docutils' -exec rm -rf {} +
  find "$site" -type d -name 'docutils-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'jmespath' -exec rm -rf {} +
  find "$site" -type d -name 'jmespath-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 's3transfer' -exec rm -rf {} +
  find "$site" -type d -name 's3transfer-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'six' -exec rm -rf {} +
  find "$site" -type d -name 'six-*.dist-info' -exec rm -rf {} +
  find "$site" -type d -name 'urllib3' -exec rm -rf {} +
  find "$site" -type d -name 'urllib3-*.dist-info' -exec rm -rf {} +
}

#clean_aws_packages () {
#  # TODO: this doesn't work because pip has no -t (target) or --path
#  #       arguments to uninstall packages (only to install them)
#  site=$1
#  python -m pip uninstall -t "$site" -y boto3
#  python -m pip uninstall -t "$site" -y botocore
#  python -m pip uninstall -t "$site" -y dateutil
#  python -m pip uninstall -t "$site" -y docutils
#  python -m pip uninstall -t "$site" -y jmespath
#  python -m pip uninstall -t "$site" -y s3transfer
#  python -m pip uninstall -t "$site" -y six
#  python -m pip uninstall -t "$site" -y urllib3
#}

## TODO: find a way to archive a package file set
#package_archive () {
#  package=$1
#  python -m pip show --files "${package}" > /tmp/package_files.txt
#  location=$(awk '/Location/ { print $2 }' /tmp/package_files.txt)
#  files=$(grep -E "^\s+" /tmp/package_files.txt | sed "s#${package}#${location}/${package}#g")
#}

create_layer_zip () {

  # These pip options do not work:
  # python -m pip install --platform 'linux' --implementation 'py'

  # The destination path should be where AWS lambda unpacks a layer .zip file
  # /opt/python/lib/python3.6/site-packages/

  py_version=$(python --version | grep -o -E '[0-9]+[.][0-9]+')
  py_ver=$(echo "py${py_version}" | sed -e 's/\.//g')

  package_dir=$(mktemp -d -t tmp_python_XXXXXX)
  package_dst=${package_dir}/python/lib/python${py_version}/site-packages
  mkdir -p "$package_dst"
  echo "$package_dst"

  venv_dir=$(mktemp -d -t tmp_venv_XXXXXX)
  python -m pip install virtualenv
  python -m virtualenv --clear "$venv_dir"
  # shellcheck disable=SC1090
  source "$venv_dir/bin/activate"
  echo "$venv_dir"

  pin_lambda_sdk /tmp/requirements.txt

  python -m pip install --no-compile -t "$package_dst" -r /tmp/requirements.txt
  #python -m pip list --path "$package_dst"

  clean_aws_packages "$package_dst"
  clean_python_packages "$package_dst"
  strip_binary_libs "$package_dst"
  strip_cpython_libs "$package_dst"

  clean_numpy "$package_dst"
  clean_pandas "$package_dst"
  clean_pydantic "$package_dst"
  clean_fastparquet "$package_dst"

#  #
#  # experimental
#  #
#  hack_shared_libs "$package_dst"
#  # these env-vars are required for hacked_shared_libs
#  export GDAL_DATA="${package_dst}/share/gdal_data"
#  export PROJ_DATA="${package_dst}/share/proj_data"
#  # TODO: consider using an AWS Lambda LD_LIBRARY_PATH vs. a custom python path, e.g.
#  # LD_LIBRARY_PATH=/var/lang/lib:/lib64:/usr/lib64:/var/runtime:/var/runtime/lib:/var/task:/var/task/lib:/opt/lib
#  export LD_LIBRARY_PATH="${package_dst}/share/libs:$LD_LIBRARY_PATH"

  python -m pip list --path "$package_dst"
  clean_python_metadata "$package_dst"
  # a pip check is useless because it doesn't support a target path argument
  #python -m pip check -t "$package_dst"
  echo
  echo
  deactivate

  echo "Zipping packages for lambda layer..."
  zip_tmp=${ZIP_TMP:-/tmp/${py_ver}_lambda_layer.zip}
  rm -f "${zip_tmp}"
  pushd "${package_dir}" > /dev/null || crash "Failed to pushd ${package_dir}"

  zip -qr9 --compression-method deflate --symlinks "${zip_tmp}" python

  ls "${zip_tmp}" > /dev/null || crash "Failed to find ${zip_tmp}"
  unzip -q -t "${zip_tmp}" || crash "Failed to test ${zip_tmp}"

  echo "created ${zip_tmp}"
  popd > /dev/null || crash "Failed to popd from ${package_dir}"

  rm -rf "$package_dir"
  rm -rf "$venv_dir"
}
