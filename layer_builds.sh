#!/bin/bash

SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(readlink -f "$SCRIPT_PATH")

# shellcheck disable=SC1090
source "$SCRIPT_PATH/layer_create_zip.sh"

py_version=$(python --version | grep -o -E '[0-9]+[.][0-9]+')
py_ver=$(echo "py${py_version}" | sed -e 's/\.//g')

# The Makefile provides values for these environment variables:
test -n "${LIB_NAME}" || crash "LIB_NAME env-var must be defined"
test -n "${LIB_VERSION}" || crash "LIB_VERSION env-var must be defined"
test -n "${LIB_PACKAGE}" || crash "LIB_PACKAGE env-var must be defined"

LAYER_PREFIX="${py_ver}-${LIB_NAME}-${LIB_VERSION}"

ZIP_PATH=${ZIP_PATH:-'/tmp'}
ZIP_PATH=$(readlink -f "$ZIP_PATH")
ZIP_TMP="${ZIP_PATH}/${py_ver}_lambda_layer.zip"

REQUIREMENTS_FILE="${ZIP_PATH}/requirements.txt"
test -f "$REQUIREMENTS_FILE" || crash "ERROR: there is no $REQUIREMENTS_FILE"

move_zip () {
  zip_lib=$1
  mv "${ZIP_TMP}" "${zip_lib}" || crash "Failed to create ${zip_lib}"
  echo "Created ${zip_lib}"
  echo
  echo
}

#
# Package Default Dependencies
#

cp -p "${ZIP_PATH}/requirements.txt" /tmp/requirements.txt
create_layer_zip
move_zip "${ZIP_PATH}/${LIB_PACKAGE}"

#
# Package Optional Extras
#

for f in "${ZIP_PATH}"/requirements_*.txt; do
  if [ -f "${f}" ]; then
    # shellcheck disable=SC2001
    extra=$(echo "${f}" | sed 's/.*requirements_\(.*\)\.txt/\1/')
    cp -p "${f}" /tmp/requirements.txt
    create_layer_zip
    move_zip "${ZIP_PATH}/${LAYER_PREFIX}-${extra}.zip"
  fi
done


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

cp -rf "${ZIP_PATH}"/project-no-deps/* "$package_dst/"

echo "Zipping packages for lambda layer..."
layer_zip="${ZIP_PATH}/${LAYER_PREFIX}-nodeps.zip"
rm -f "${layer_zip}"
pushd "${package_dir}" >/dev/null || crash "Failed to pushd ${package_dir}"

zip -qr9 --compression-method deflate --symlinks "${layer_zip}" python
zip -qr9 --compression-method deflate --symlinks "${ZIP_PATH}/${LIB_PACKAGE}" python
for f in "${ZIP_PATH}"/requirements_*.txt; do
  if [ -f "${f}" ]; then
    # shellcheck disable=SC2001
    extra=$(echo "${f}" | sed 's/.*requirements_\(.*\)\.txt/\1/')
    extra_zip="${ZIP_PATH}/${LAYER_PREFIX}-${extra}.zip"
    zip -qr9 --compression-method deflate --symlinks "${extra_zip}" python
  fi
done

ls "${layer_zip}" >/dev/null || crash "Failed to find ${layer_zip}"
unzip -q -t "${layer_zip}" || crash "Failed to test ${layer_zip}"
echo "created ${layer_zip}"
popd >/dev/null || crash "Failed to popd from ${package_dir}"
rm -rf "$package_dir"
echo
echo

# When this runs in a docker container with the root user, try
# to set permissions and ownership on the .zip artifacts
USER_ID=${USER_ID:-$(id --user)}
GROUP_ID=${GROUP_ID:-$(id --group)}
chmod a+rw "${ZIP_PATH}"/*.zip || true
chown "${USER_ID}":"${GROUP_ID}" "${ZIP_PATH}"/*.zip || true
