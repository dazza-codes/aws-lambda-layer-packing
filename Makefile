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


# For packaging lambda .zip archives, see also
# - https://github.com/aws-samples/aws-lambda-layer-awscli/blob/master/Makefile
#
# From https://github.com/UnitedIncome/serverless-python-requirements/tree/master/lib
#
# docker run --rm \
#    -v $HOME/.cache/serverless-python-requirements/4f5880eb75f127d1b9e30128e546299ea6c3b76764d31a5b50522cc54e5e4eaf_slspyc\:/var/task\:z \
#    -v $HOME/.cache/serverless-python-requirements/downloadCacheslspyc\:/var/useDownloadCache\:z \
#    lambci/lambda\:build-python3.6 \
#    /bin/sh -c 'chown -R 0\\:0 /var/useDownloadCache && python3.6 -m pip install -t /var/task/ -r /var/task/requirements.txt --cache-dir /var/useDownloadCache && chown -R 1000\\:1000 /var/task && chown -R 1000\\:1000 /var/useDownloadCache && find /var/task -name \\*.so -exec strip \\{\\} \\;'

# TODO: try to use an aws-sam package, but it's probably lacking optimizations
#sam-layer-package:
#	@docker run -i $(EXTRA_DOCKER_ARGS) \
#	-v $(PWD):/home/samcli/workdir \
#	-v $(HOME)/.aws:/home/samcli/.aws \
#	-w /home/samcli/workdir \
#	-e AWS_DEFAULT_REGION=$(LAMBDA_REGION) \
#	pahud/aws-sam-cli:latest sam package --template-file sam-layer.yaml --s3-bucket $(S3BUCKET) --output-template-file sam-layer-packaged.yaml
#	@echo "[OK] Now type 'make sam-layer-deploy' to deploy your Lambda layer with SAM"


PY_VERSION=$(shell python --version | grep -o -E '[0-9]+[.][0-9]+')
PY_VER=$(shell echo "py$(PY_VERSION)" | sed -e 's/\.//g')

LIB_NAME=lambda-project
LIB_VERSION=$(shell python -c 'import lambda_project; print(lambda_project.VERSION)')

LIB_PREFIX=$(PY_VER)-$(LIB_NAME)-$(LIB_VERSION)
LIB_PACKAGE=$(LIB_PREFIX).zip
LIB_TMPDIR=/tmp/$(LIB_NAME)
LIB_REPO=ssh://git@github.com/dazza-codes/aws-lambda-layer-packing.git@$(LIB_VERSION)

APP_IMAGE=$(LIB_NAME)-lambda-builds

USER_ID=$(shell id --user)
GROUP_ID=$(shell id --group)

clean:
	@rm -rf build dist .eggs *.egg-info
	@rm -rf .benchmarks .coverage* coverage.xml htmlcov report.xml .tox
	@find . -type d -name '.mypy_cache' -exec rm -rf {} +
	@find . -type d -name '__pycache__' -exec rm -rf {} +
	@find . -type d -name '*pytest_cache*' -exec rm -rf {} +
	@find . -type f -name "*.py[co]" -exec rm -rf {} +

docker-build:
	git rev-parse HEAD > version
	DOCKER_BUILDKIT=1 && export DOCKER_BUILDKIT
	docker build -t $(APP_IMAGE) --ssh=default  .
	rm version

docker-shell: docker-build poetry-export
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
		$(APP_IMAGE) /bin/bash

layer-package: docker-build poetry-export
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
		$(APP_IMAGE) ./layer_builds.sh
	ls -al $(LIB_TMPDIR)/*.zip
	echo
	ZIP_PATH=$(LIB_TMPDIR) ./layer_size.sh
	echo

layer-size: layer-tmpdir
	ls -al $(LIB_TMPDIR)/*.zip
	echo
	ZIP_PATH=$(LIB_TMPDIR) ./layer_size.sh
	echo

layer-publish: layer-tmpdir
	AWS_DEFAULT_REGION=$(AWS_DEFAULT_REGION) \
	AWS_ACCOUNT=$(AWS_ACCOUNT) \
	LIB_PREFIX=$(LIB_PREFIX) \
	ZIP_PATH=$(LIB_TMPDIR) \
	./layer_publish.sh

layer-tmpdir:
	mkdir -p $(LIB_TMPDIR)

# Export the project dependencies as a requirements.txt file, without
# any editable dependencies, and export the project library with no-deps
poetry-export: layer-tmpdir
	EXPORT_ARGS='--without-hashes --format requirements.txt --output requirements.txt'

	poetry export $${EXPORT_ARGS}
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements.txt

	#
	# manually add optional extras from the pyproject.toml
	#
	poetry export $${EXPORT_ARGS} --extras gis
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_gis.txt

	poetry export $${EXPORT_ARGS} --extras fastparquet
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_fastparquet.txt

	poetry export $${EXPORT_ARGS} --extras pyarrow
	sed -e 's/^-e //g' requirements.txt > $(LIB_TMPDIR)/requirements_pyarrow.txt

	rm -f requirements.txt
	rm -rf dist/*
	poetry build
	wheel=$$(ls -1t dist/*.whl | head -n1)
	rm -rf $(LIB_TMPDIR)/project-no-deps
	python -m pip install --no-compile --no-deps -t $(LIB_TMPDIR)/project-no-deps "$${wheel}"

init: poetry
	@source "$(HOME)/.poetry/env"
	@poetry run pip install --upgrade pip
	@poetry run python -m pip install -r requirements.dev
	@poetry run pre-commit install
	@poetry install -v --no-interaction \
		--extras gis \
		--extras pyarrow \
		--extras fastparquet \
		--extras s3fs
	@poetry run python -m pip check

poetry:
	@if ! which poetry > /dev/null; then \
		curl -sSL https://raw.githubusercontent.com/sdispater/poetry/master/get-poetry.py -o /tmp/get-poetry.py; \
		python /tmp/get-poetry.py; \
	fi


.PHONY: docker-build docker-shell layer-package layer-size layer-publish layer-tmpdir
.PHONY: init poetry poetry-export
