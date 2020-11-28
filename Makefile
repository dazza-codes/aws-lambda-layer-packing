# https://www.gnu.org/software/make/manual/html_node/Makefile-Conventions.html
SHELL = /bin/bash

# Tips for writing shell scripts within makefiles:
# - Escape the script's use of $ by replacing with $$
# - Convert the script to work as a single line by inserting ; between commands
# - If you want to write the script on multiple lines, escape end-of-line with \
# - Optionally start with set -e to match make's provision to abort on sub-command failure
# - This is totally optional, but you could bracket the script with () or {} to
#   emphasize the cohesiveness of a multiple line sequence -- note that this is
#   not a typical makefile command sequence

# https://www.gnu.org/software/make/manual/html_node/One-Shell.html
# If .ONESHELL is provided, then only the first line of the recipe
# will be checked for the special prefix characters (‘@’, ‘-’, and ‘+’).
.ONESHELL:
.SUFFIXES:

PYTHON_VER=$(shell python --version | grep -o -E '[0-9]+[.][0-9]+')
PY_VER=$(shell echo "py$(PYTHON_VER)" | sed -e 's/\.//g')

BASE_IMAGE=$(PY_VER)-lambda-builds
TEST_IMAGE=$(PY_VER)-lambda-tests

LIB_NAME=$(shell poetry version | awk '{ printf "%s",$$1 }')
LIB_VERSION=$(shell poetry version -s)

LIB_PREFIX=$(PY_VER)-$(LIB_NAME)-$(LIB_VERSION)
LIB_PACKAGE=$(LIB_PREFIX).zip
LIB_TMPDIR=/tmp/$(LIB_NAME)
LIB_TSTDIR=/tmp/test/$(LIB_NAME)

USER_ID=$(shell id --user)
GROUP_ID=$(shell id --group)

LAMBDA_ACCOUNT ?= $(AWS_ACCOUNT)
LAMBDA_REGION ?= $(AWS_DEFAULT_REGION)

# AWS account and region should be set as env-var for some rules
ifndef AWS_ACCOUNT
AWS_ACCOUNT_ERROR = $(error AWS_ACCOUNT env-var must be defined)
endif

# AWS account and region should be set as env-var for some rules
ifndef AWS_DEFAULT_REGION
AWS_REGION_ERROR = $(error AWS_DEFAULT_REGION env-var must be defined)
endif

# S3_BUCKET should be set as an env-var for some rules
ifndef S3_BUCKET
S3_BUCKET_ERROR = $(error S3_BUCKET env-var must be defined)
endif

S3_PREFIX ?= lambda-layers/$(LIB_NAME)
S3_ROOT=s3://$(S3_BUCKET)/$(S3_PREFIX)


.PHONY: aws-check aws-settings

aws-check: ; $(S3_BUCKET_ERROR) $(AWS_ACCOUNT_ERROR) $(AWS_REGION_ERROR)
	@test -n "$(S3_BUCKET)" && test -n "$(AWS_DEFAULT_REGION)" && test -n "$(AWS_ACCOUNT)"

aws-settings:
	@echo
	echo -e "\t s3-bucket:\t $(S3_BUCKET)"
	echo -e "\t s3-layer-path:\t $(S3_ROOT)"
	echo -e "\t aws-region:\t $(LAMBDA_REGION)"
	echo -e "\t aws-account:\t $(LAMBDA_ACCOUNT)"
	echo
	echo "Listing S3_ROOT=$(S3_ROOT):"
	aws s3 ls $(S3_ROOT)


.PHONY: clean check init

clean:
	@rm -rf build dist .eggs *.egg-info
	rm -rf .benchmarks .coverage* coverage.xml htmlcov report.xml .tox
	find . -type d -name '.mypy_cache' -exec rm -rf {} +
	find . -type d -name '__pycache__' -exec rm -rf {} +
	find . -type d -name '*pytest_cache*' -exec rm -rf {} +
	find . -type f -name "*.py[co]" -exec rm -rf {} +

check:
	@# allow this to fail
	@poetry run python -m pip check || true
	@poetry check || true

init: poetry
	@source "$(HOME)/.poetry/env"
	poetry run pip install --upgrade pip
	poetry run python -m pip install -r requirements.dev
	poetry run pre-commit install
	poetry install -v --no-interaction --extras all


.PHONY: docker-boto-libs
.PHONY: docker-base-build docker-base-shell
.PHONY: docker-test-build docker-test-shell docker-test-run

docker-boto-libs: layer-tstdir
	cp lambda_versions.py $(LIB_TSTDIR)/
	docker run --rm \
		-v $(LIB_TSTDIR)/:/var/task:ro,delegated \
		lambci/lambda:python$(PYTHON_VER) \
		lambda_versions.lambda_handler

#docker run --rm \
#  -v <code_dir>:/var/task:ro,delegated \
#  [-v <layer_dir>:/opt:ro,delegated] \
#  lambci/lambda:<runtime> \
#  [<handler>] [<event>]


docker-base-build:
	git rev-parse HEAD > version
	DOCKER_BUILDKIT=1 && export DOCKER_BUILDKIT
	docker build -f ./dockerfiles/base.Dockerfile \
 		-t $(BASE_IMAGE) \
 		--build-arg python_ver=$(PYTHON_VER) \
 		--ssh=default .
	rm version

docker-base-shell: docker-base-build
	docker run -it --rm $(BASE_IMAGE) /bin/bash

docker-test-build: docker-base-build clean
	DOCKER_BUILDKIT=1 && export DOCKER_BUILDKIT
	docker build -f ./dockerfiles/test.Dockerfile \
 		-t $(TEST_IMAGE) \
 		--build-arg py_ver=$(PY_VER) \
 		--ssh=default .

docker-test-run: docker-test-build
	docker run --rm $(TEST_IMAGE)

docker-test-shell: docker-test-build
	docker run -it --rm $(TEST_IMAGE) /bin/bash


.PHONY: layer-package layer-size layer-publish layer-tmpdir layer-tstdir

layer-package: docker-base-build poetry-export
	rm -rf $(LIB_TMPDIR)/*.zip
	docker run -it --rm \
		-e LIB_NAME\=$(LIB_NAME) \
		-e LIB_VERSION\=$(LIB_VERSION) \
		-e LIB_PACKAGE\=$(LIB_PACKAGE) \
		-e ZIP_PATH\=$(LIB_TMPDIR) \
		-e USER_ID\=$(USER_ID) \
		-e GROUP_ID\=$(GROUP_ID) \
		-v $(HOME)/.ssh/id_rsa\:/root/.ssh/id_rsa\:z \
		-v $(HOME)/.ssh/known_hosts\:/root/.ssh/known_hosts\:z \
		-v /run/user/$(USER_ID)/keyring/ssh\:/tmp/ssh_sock\:z \
		-e SSH_AUTH_SOCK\=/tmp/ssh_sock \
		-v /tmp:/tmp \
		$(BASE_IMAGE) ./layer_builds.sh
	ls -al $(LIB_TMPDIR)/*.zip
	echo
	ZIP_PATH=$(LIB_TMPDIR) ./layer_size.sh
	echo

layer-size: layer-tmpdir
	ls -al $(LIB_TMPDIR)/*.zip
	echo
	ZIP_PATH=$(LIB_TMPDIR) ./layer_size.sh
	echo

layer-tmpdir:
	mkdir -p $(LIB_TMPDIR)

layer-tstdir:
	mkdir -p $(LIB_TSTDIR)

layer-publish: layer-tmpdir aws-check aws-settings
	@LIB_PREFIX=$(LIB_PREFIX) \
	ZIP_PATH=$(LIB_TMPDIR) \
	S3_BUCKET=$(S3_BUCKET) \
	S3_PREFIX=$(S3_PREFIX) \
	./layer_publish.sh


.PHONY: function-publish

FUNC_NAME=$(LIB_NAME)-layer-test
FUNC_ARN=arn:aws:lambda:$(AWS_DEFAULT_REGION):$(AWS_ACCOUNT):function:$(FUNC_NAME)
ZIP_FILE=$(FUNC_NAME).zip

function-publish: layer-tmpdir aws-check aws-settings
	rm -f $(LIB_TMPDIR)/$(ZIP_FILE)
	zip $(LIB_TMPDIR)/$(ZIP_FILE) lambda_function.py
	aws lambda update-function-code \
		--function-name $(FUNC_ARN) \
		--zip-file fileb://$(LIB_TMPDIR)/$(ZIP_FILE)


.PHONY: poetry poetry-export

poetry:
	@if ! which poetry > /dev/null; then \
		curl -sSL https://raw.githubusercontent.com/sdispater/poetry/master/get-poetry.py -o /tmp/get-poetry.py; \
		python /tmp/get-poetry.py; \
	fi

# Export the project dependencies as a requirements.txt file, without
# any editable dependencies, and export the project library with no-deps
poetry-export: layer-tmpdir
	EXPORT_ARGS='--without-hashes --format requirements.txt --output requirements.txt'

	rm -f requirements.txt
	poetry export $${EXPORT_ARGS}
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements.txt

	rm -f requirements.txt
	poetry export $${EXPORT_ARGS} --extras pyarrow
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_pyarrow.txt

	rm -f requirements.txt
	poetry export $${EXPORT_ARGS} --extras netcdf4 --extras zarr --extras xarray
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_xarray.txt

	rm -f requirements.txt
	poetry export $${EXPORT_ARGS} --extras sql
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_sql.txt

	## # Too big for lambda - layer-publish will crash
	## rm -f requirements.txt
	## poetry export $${EXPORT_ARGS} --extras all
	## sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_all.txt

	rm -f requirements.txt
	rm -rf dist/*
	poetry build
	wheel=$$(ls -1t dist/*.whl | head -n1)
	rm -rf $(LIB_TMPDIR)/project-no-deps
	python -m pip install --no-compile --no-deps -t $(LIB_TMPDIR)/project-no-deps "$${wheel}"

	rm -f requirements.txt
