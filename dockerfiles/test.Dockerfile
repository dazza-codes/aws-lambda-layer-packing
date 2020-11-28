# syntax=docker/dockerfile:1.0.2-experimental
# the above line is necessary, not a comment, do not delete!
# you must have a local environment variable of DOCKER_BUILDKIT=1 for this to work!

ARG py_ver=py36

# For more information about this base image, see *_base.Dockerfile
FROM ${py_ver}-lambda-builds

RUN pip install --upgrade pip

COPY requirements.dev ./
RUN python -m pip install --no-compile -r requirements.dev

COPY pyproject.toml poetry.lock ./
RUN poetry export --extras pyarrow --without-hashes --format requirements.txt --output requirements.txt && \
	sed -i -e 's/^-e //g' requirements.txt && \
    python -m pip install --no-compile -r requirements.txt

# The layer_builds.sh should be the CMD, but it's not explicit (yet)
COPY layer_*.sh ./

# Apply optimized cleanup, but do not clean the AWS packages in this test venv because it
# is isolated from a lambci system python installation that contains the AWS packages
RUN package_dst=$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])') && \
    source ./layer_create_zip.sh && \
    clean_python_packages "$package_dst" && \
    strip_binary_libs "$package_dst" && \
    strip_cpython_libs "$package_dst" && \
    clean_numpy "$package_dst" && \
    clean_pandas "$package_dst" && \
    clean_pydantic "$package_dst" && \
    clean_fastparquet "$package_dst"

COPY README.md ./
ADD lambda_project ./lambda_project
ADD tests ./tests
RUN poetry build && \
    python -m pip install --no-compile --no-deps ./dist/*.whl

CMD ["pytest", "-v"]
