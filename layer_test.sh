#!/bin/bash

SCRIPT_PATH=$(dirname "$0")
SCRIPT_PATH=$(readlink -f "$SCRIPT_PATH")

# shellcheck disable=SC1090
source "$SCRIPT_PATH/layer_create_zip.sh"

if [ -z "$LIB_TSTDIR" ]; then
  echo "ERROR: there is no $LIB_TSTDIR defined"
  exit 1
fi
if [ ! -d "$LIB_TSTDIR" ]; then
  echo "ERROR: the $LIB_TSTDIR is not a directory"
  exit 1
fi

REQUIREMENTS_FILE="${LIB_TSTDIR}/requirements.txt"
if [ ! -f "$REQUIREMENTS_FILE" ]; then
  echo "ERROR: there is no $REQUIREMENTS_FILE"
  exit 1
fi

REQUIREMENTS_DEV="${LIB_TSTDIR}/requirements.dev"
if [ ! -f "$REQUIREMENTS_DEV" ]; then
  echo "ERROR: there is no $REQUIREMENTS_DEV"
  exit 1
fi

TESTS_DIR="${LIB_TSTDIR}/tests"
if [ ! -d "$TESTS_DIR" ]; then
  echo "ERROR: there is no $TESTS_DIR"
  exit 1
fi

pin_lambda_sdk "${REQUIREMENTS_DEV}"
pin_lambda_sdk "${REQUIREMENTS_FILE}"

venv_dir=$(mktemp -d -t tmp_venv_XXXXXX)
python -m pip install virtualenv
python -m virtualenv --clear "$venv_dir"
# shellcheck disable=SC1090
source "$venv_dir/bin/activate"
echo "$venv_dir"

python -m pip install --no-compile -r "${REQUIREMENTS_DEV}"
python -m pip install --no-compile -r "${REQUIREMENTS_FILE}"
python -m pip install --no-compile --no-deps "${LIB_TSTDIR}"/dist/*.whl

python -m pip check

# Do not clean the AWS packages in this test venv because it
# is isolated from a lambci system python installation that
# contains the AWS packages
#[ "$LAMBDA_RUNTIME_DIR" != "" ] && clean_aws_packages "$package_dst"

package_dst=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')

clean_python_packages "$package_dst"
strip_binary_libs "$package_dst"
strip_cpython_libs "$package_dst"

clean_numpy "$package_dst"
clean_pandas "$package_dst"
clean_pydantic "$package_dst"
clean_fastparquet "$package_dst"

## experimental option:
#hack_shared_libs "$package_dst"
## these env-vars are required for hacked_shared_libs
#export GDAL_DATA="${package_dst}/share/gdal_data"
#export PROJ_DATA="${package_dst}/share/proj_data"
#export LD_LIBRARY_PATH="${package_dst}/share/libs:$LD_LIBRARY_PATH"

python -m pip list --path "$package_dst"

pushd "$TESTS_DIR" || exit 1
python -m pytest
popd || exit 1

echo
echo
deactivate

#rm -rf "$venv_dir"

# When this runs in a lambci container with the root user, try
# to reset permissions and ownership on the test directory
if [ "$LAMBDA_RUNTIME_DIR" != "" ]; then
  USER_ID=${USER_ID:-$(id --user)}
  GROUP_ID=${GROUP_ID:-$(id --group)}
  chmod -R a+rw "${LIB_TSTDIR}"/ || true
  chown -R "${USER_ID}":"${GROUP_ID}" "${LIB_TSTDIR}"/ || true
fi
