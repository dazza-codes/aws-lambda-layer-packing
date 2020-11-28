
# Docker Builds


### Options

These notes can be ignored, they are just here for reference.

```
chown -R 0:0 /var/useDownloadCache
python3.6 -m pip install \
    -t /var/task/ \
    -r /var/task/requirements.txt \
    --cache-dir /var/useDownloadCache

chown -R 1000:1000 /var/task
chown -R 1000:1000 /var/useDownloadCache
find /var/task -type f -name *.so -exec strip {} ;
```

```
docker run --rm \
    -v $HOME/.cache/serverless-python-requirements/4f5880eb75f127d1b9e30128e546299ea6c3b76764d31a5b50522cc54e5e4eaf_slspyc\:/var/task\:z \
    -v $HOME/.ssh/id_rsa\:/root/.ssh/id_rsa\:z \
    -v $HOME/.ssh/known_hosts\:/root/.ssh/known_hosts\:z \
    -v /run/user/1000/keyring/ssh\:/tmp/ssh_sock\:z \
    -e SSH_AUTH_SOCK\=/tmp/ssh_sock \
    -v $HOME/.cache/serverless-python-requirements/downloadCacheslspyc\:/var/useDownloadCache\:z \
    lambci/lambda\:build-python3.6 \
    /bin/sh -c 'chown -R 0\\:0 /var/useDownloadCache && python3.6 -m pip install -t /var/task/ -r /var/task/requirements.txt --cache-dir /var/useDownloadCache && chown -R 1000\\:1000 /var/task && chown -R 1000\\:1000 /var/useDownloadCache && find /var/task -name \\*.so -exec strip \\{\\} \\;'
```

For packaging lambda .zip archives, see also
- https://github.com/aws-samples/aws-lambda-layer-awscli/blob/master/Makefile

From https://github.com/UnitedIncome/serverless-python-requirements/tree/master/lib

```
docker run --rm \
   -v $HOME/.cache/serverless-python-requirements/4f5880eb75f127d1b9e30128e546299ea6c3b76764d31a5b50522cc54e5e4eaf_slspyc\:/var/task\:z \
   -v $HOME/.cache/serverless-python-requirements/downloadCacheslspyc\:/var/useDownloadCache\:z \
   lambci/lambda\:build-python3.6 \
   /bin/sh -c 'chown -R 0\\:0 /var/useDownloadCache && python3.6 -m pip install -t /var/task/ -r /var/task/requirements.txt --cache-dir /var/useDownloadCache && chown -R 1000\\:1000 /var/task && chown -R 1000\\:1000 /var/useDownloadCache && find /var/task -name \\*.so -exec strip \\{\\} \\;'
```

TODO: try to use an aws-sam package, but it's probably lacking optimizations

```
sam-layer-package:
    @docker run -i $(EXTRA_DOCKER_ARGS) \
    -v $(PWD):/home/samcli/workdir \
    -v $(HOME)/.aws:/home/samcli/.aws \
    -w /home/samcli/workdir \
    -e AWS_DEFAULT_REGION=$(LAMBDA_REGION) \
    pahud/aws-sam-cli:latest sam package --template-file sam-layer.yaml --s3-bucket $(S3BUCKET) --output-template-file sam-layer-packaged.yaml
    @echo "[OK] Now type 'make sam-layer-deploy' to deploy your Lambda layer with SAM"
```
