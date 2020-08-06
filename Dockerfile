# syntax=docker/dockerfile:1.0.2-experimental
# the above line is necessary, not a comment, do not delete!
# you must have a local environment variable of DOCKER_BUILDKIT=1 for this to work!

# For more information about this base image, see
# https://hub.docker.com/r/lambci/lambda
FROM lambci/lambda:build-python3.6
LABEL maintainer=@dazza-codes

ENV PYTHONDONTWRITEBYTECODE=true

RUN --mount=type=ssh \
    mkdir -p ~/.ssh && \
    ssh-keyscan -H github.com >> ~/.ssh/known_hosts && \
    ssh-keyscan -H gitlab.com >> ~/.ssh/known_hosts

RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python \
    && poetry --version

RUN curl -o jq-linux64 -sSL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 \
    && mv jq-linux64 /usr/local/bin/jq \
    && chmod a+x /usr/local/bin/jq \
    && jq --version

# The layer_builds.sh should be the CMD, but it's not explicit (yet)
COPY layer_builds.sh layer_create_zip.sh layer_size.sh ./

#
# The following can be ignored, it's here for reference only.
#

#COPY requirements.txt /tmp/requirements.txt
#RUN --mount=type=ssh \
#    source ./layer_create_zip.sh \
#    create_layer_zip

#chown -R 0:0 /var/useDownloadCache
#python3.6 -m pip install \
#    -t /var/task/ \
#    -r /var/task/requirements.txt \
#    --cache-dir /var/useDownloadCache
#
#chown -R 1000:1000 /var/task
#chown -R 1000:1000 /var/useDownloadCache
#find /var/task -type f -name *.so -exec strip {} ;

#docker run --rm \
#    -v $HOME/.cache/serverless-python-requirements/4f5880eb75f127d1b9e30128e546299ea6c3b76764d31a5b50522cc54e5e4eaf_slspyc\:/var/task\:z \
#    -v $HOME/.ssh/id_rsa\:/root/.ssh/id_rsa\:z \
#    -v $HOME/.ssh/known_hosts\:/root/.ssh/known_hosts\:z \
#    -v /run/user/1000/keyring/ssh\:/tmp/ssh_sock\:z \
#    -e SSH_AUTH_SOCK\=/tmp/ssh_sock \
#    -v $HOME/.cache/serverless-python-requirements/downloadCacheslspyc\:/var/useDownloadCache\:z \
#    lambci/lambda\:build-python3.6 \
#    /bin/sh -c 'chown -R 0\\:0 /var/useDownloadCache && python3.6 -m pip install -t /var/task/ -r /var/task/requirements.txt --cache-dir /var/useDownloadCache && chown -R 1000\\:1000 /var/task && chown -R 1000\\:1000 /var/useDownloadCache && find /var/task -name \\*.so -exec strip \\{\\} \\;'
