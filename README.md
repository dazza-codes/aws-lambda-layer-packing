
# AWS Lambda Packaging

The following notes relate to packaging for AWS lambda.  The creation of a
lambda layer is not trivial, for several reasons:

- the library versions and APIs are complicated
- the size of the dependency libraries and restrictions on lambda package size
- the way lambda estimates the size of multiple layers by a simple
  summation of all layers regardless of any duplicate content

The builds follow the guidelines from the
[AWS knowledge center](https://aws.amazon.com/premiumsupport/knowledge-center/lambda-layer-simulated-docker/).
It recommends using the [lambci/lambda](https://hub.docker.com/r/lambci/lambda/) Docker images,
to simulate the live Lambda environment and create a layer that's compatible
with the runtimes that you specify. For more information, see
[lambci/lambda](https://hub.docker.com/r/lambci/lambda/) on the Docker website.
Note that lambci/lambda images are not an exact copy of the Lambda environment
and some files may be missing. The AWS Serverless Application Model (AWS SAM)
also uses the lambci/lambda Docker images when you run `sam local start-api`

This project uses some custom build recipes to try to minimize a lambda layer
zip archive.  There are better projects for simple lambda layers and various
lambda runtimes, such as serverless-python-requirements and the aws-samcli.
This project only exists because those projects can provide a lot functionality
but this project goes one step further to pin and then eliminate built-in lambda
libraries for a python runtime, assuming that layer-size needs to be optimized
by removing them and that the lambda runtime already provides versions that are
compatible with the project.

See also

- https://github.com/developmentseed/geolambda
- https://github.com/RemotePixel/amazonlinux-gdal
    - it was archived (read-only) in 2019
    - there are some forks in:
        - https://github.com/dazza-codes/amazonlinux-gdal/tree/gdal2.4.2-py3.6
        - https://github.com/dazza-codes/amazonlinux-gdal/tree/gdal2.4.2-py3.6
- https://medium.com/@korniichuk/lambda-with-pandas-fd81aa2ff25e
- https://aws.amazon.com/blogs/aws/new-for-aws-lambda-use-any-programming-language-and-share-common-components/
- AWSLambda-Python36-SciPy1x is a public lambda layer with numpy and scipy
    - scipy 1.1.0
    - numpy 1.15.4

## Project Strategy and Limitations

To understand the project, start with the `pyproject.toml` and `Makefile`.  To
get started, create a python3.6 virtual env and run:

```text
make init
make layer-package
```

- build lambda layers using Docker builds for python
  - [lambci/lambda](https://hub.docker.com/r/lambci/lambda/) has build images
  - currently specific to `lambci/lambda:build-python3.6`
  - could use different docker files for other python runtimes,
    but it might also require changes to the root `pyproject.toml`
- use poetry to resolve python library dependencies
  - it benefits from the analysis of the dependency engine
    that respects the version specs in the dependency tree
- this is not an effective template project
  - too many parameters are hard-coded
  - make recipes and shell scripts coordinate and build layers
  - parameters are passed via env-vars, could be fragile
- use optional extras to package different layers
  - poetry export is called from `make poetry-export`
  - manually edit the make recipe for optional extras

## Lambda Limits

See https://docs.aws.amazon.com/lambda/latest/dg/limits.html
- Function and layer storage: 75 GB
- Deployment package size
  - 250 MB (unzipped, including layers)
  -  50 MB (zipped, for direct upload)
  -   3 MB (console editor)

To check layer sizes run `make layer-size`, e.g.:

```text
MAX BYTES   262144000 bytes
            244883095 bytes in py36-lambda-project-0.1.0-fastparquet.zip
            212613224 bytes in py36-lambda-project-0.1.0-gis.zip
            102077096 bytes in py36-lambda-project-0.1.0-pyarrow.zip
```

## AWS SDK packages

Use `poetry show -t --no-dev`, `pip freeze` or `pipdeptree` to check poetry installed
versions and pin common deps to use the same, consistent versions in lambda layers.

AWS lambda bundles the python SDK in lambda layers, but they advise that bundling it into
a project layer is a best practice.

- https://aws.amazon.com/blogs/compute/upcoming-changes-to-the-python-sdk-in-aws-lambda/

See also the current versions of botocore in lambda - listed at

- https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html

Also consider what is supported by aiobotocore, see:

- https://github.com/aio-libs/aiobotocore/blob/master/setup.py

release 0.12.0 of aiobotocore uses:

```text
1.15.3 < botocore < 1.15.16
boto3 == 1.12.3
```

To view the packages installed in the [lambci/lambda](https://hub.docker.com/r/lambci/lambda/)
image for python (3.6):

```sh
bash-4.2# ls -1d /var/runtime/*.dist-info
/var/runtime/boto3-1.12.49.dist-info
/var/runtime/botocore-1.15.49.dist-info
/var/runtime/docutils-0.15.2.dist-info
/var/runtime/jmespath-0.9.5.dist-info
/var/runtime/python_dateutil-2.8.1.dist-info
/var/runtime/s3transfer-0.3.3.dist-info
/var/runtime/six-1.14.0.dist-info
/var/runtime/urllib3-1.25.9.dist-info
```

The `layer_create_zip.sh:clean_aws_packages` function will remove all
of these SDK packages from layer zip files.  It might not discriminate
package versions that differ from the SDK versions.

The `lambda/layer_builds.sh` will use the SDK versions provided to
try to pin dependencies to those versions.  For project dependencies
that require incompatible versions, a `pip check` should identify
the problem for that layer during the build.

## GIS Packages and Binaries

Many python packages for GIS package binary wheels for their dependencies.
For example:

```text
$ unzip -t /tmp/lambda-project/py36-lambda-project-0.1.0-gis.zip | grep '\.libs'
    testing: python/lib/python3.6/site-packages/pyproj/.libs/   OK
    testing: python/lib/python3.6/site-packages/pyproj/.libs/libz-eb09ad1d.so.1.2.3   OK
    testing: python/lib/python3.6/site-packages/pyproj/.libs/libsqlite3-b65a32f0.so.0.8.6   OK
    testing: python/lib/python3.6/site-packages/pyproj/.libs/libproj-d352b7c6.so.15.2.1   OK
    testing: python/lib/python3.6/site-packages/numpy.libs/   OK
    testing: python/lib/python3.6/site-packages/numpy.libs/libz-eb09ad1d.so.1.2.3   OK
    testing: python/lib/python3.6/site-packages/numpy.libs/libopenblasp-r0-ae94cfde.3.9.dev.so   OK
    testing: python/lib/python3.6/site-packages/numpy.libs/libgfortran-2e0d59d6.so.5.0.0   OK
    testing: python/lib/python3.6/site-packages/numpy.libs/libquadmath-2d0c479f.so.0.0.0   OK
    testing: python/lib/python3.6/site-packages/shapely/.libs/   OK
    testing: python/lib/python3.6/site-packages/shapely/.libs/libgeos--no-undefined-fab82081.so   OK
    testing: python/lib/python3.6/site-packages/shapely/.libs/libgeos_c-5031f9ac.so.1.13.1   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libgeos_c-1aedf783.so.1.10.2   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libopenjp2-8f6da918.so.2.3.0   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libpng16-898afbbd.so.16.35.0   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libcurl-ed5c192c.so.4.4.0   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libgeos-3-9b41901c.6.2.so   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libwebp-8ccd29fd.so.7.0.2   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libnetcdf-350a79a5.so.11.0.4   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libsqlite3-fdd57a2d.so.0.8.6   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libgdal-4653656c.so.20.5.3   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libnghttp2-11cb20b8.so.14.17.1   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libhdf5_hl-db841637.so.100.1.1   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libjson-c-5f02f62c.so.2.0.2   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libz-a147dcb0.so.1.2.3   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libexpat-09c47d4c.so.1.6.8   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libjpeg-3fe7dfc0.so.9.3.0   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libaec-2147abcd.so.0.0.4   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libsz-1c7dd0cf.so.2.0.1   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libhdf5-2c0f0a3e.so.103.0.0   OK
    testing: python/lib/python3.6/site-packages/rasterio/.libs/libproj-cd06b982.so.12.0.0   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libpng16-898afbbd.so.16.35.0   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libgeos--no-undefined-b94097bf.so   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libnghttp2-11cb20b8.so.14.17.1   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libjson-c-5f02f62c.so.2.0.2   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libz-a147dcb0.so.1.2.3   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libgdal-0f908958.so.20.5.4   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libjpeg-3fe7dfc0.so.9.3.0   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libcurl-ea538880.so.4.4.0   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libsqlite3-25a4bc97.so.0.8.6   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libexpat-c4a93fc7.so.1.6.8   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libgeos_c-a68605fd.so.1.13.1   OK
    testing: python/lib/python3.6/site-packages/fiona/.libs/libproj-cd06b982.so.12.0.0   OK
```

## Splitting Layers for Large Packages

There are several large libs:

```text
$ du -sh /opt/python/lib/python3.6/site-packages/* | grep -E '^[0-9]*M' | sort
11M  /opt/python/lib/python3.6/site-packages/numba
14M  /opt/python/lib/python3.6/site-packages/numpy
24M  /opt/python/lib/python3.6/site-packages/pandas
24M  /opt/python/lib/python3.6/site-packages/pyproj
32M  /opt/python/lib/python3.6/site-packages/numpy.libs
44M  /opt/python/lib/python3.6/site-packages/fiona
55M  /opt/python/lib/python3.6/site-packages/rasterio
57M  /opt/python/lib/python3.6/site-packages/llvmlite
```

The `pip show` command can list a package dependencies and
the packages that depend on it, e.g.

```text
$ pip show boto3
Name: boto3
Version: 1.12.49
Summary: The AWS SDK for Python
Home-page: https://github.com/boto/boto3
Author: Amazon Web Services
Author-email: UNKNOWN
License: Apache License 2.0
Location: /opt/conda/envs/aws-lambda-layer-packing/lib/python3.6/site-packages
Requires: jmespath, s3transfer, botocore
Required-by: moto, aws-sam-translator
```

The dependency graph can be displayed and explored using
`poetry show -t` and `poetry show -t {package}`.  For example,
the `llvmlite` package is a dependency of `numba`, which is a
dependency of `fastparquet`, which also depends on `pandas`
and therefore `numpy`:

```text
$ poetry show -t fastparquet
fastparquet 0.3.3 Python support for Parquet file format
├── numba >=0.28
│   ├── llvmlite >=0.33.0.dev0,<0.34
│   ├── numpy >=1.15
│   └── setuptools *
├── numpy >=1.11
├── pandas >=0.19
│   ├── numpy >=1.13.3
│   ├── python-dateutil >=2.6.1
│   │   └── six >=1.5
│   └── pytz >=2017.2
├── six *
└── thrift >=0.11.0
    └── six >=1.7.2
```

Using `pipdeptree` can also identify package dependencies, including
reverse dependencies.  For example, it is useful to remove all the packages
that lambda already provides, like `boto3`, and it can help to find
anything that depends on it:

```text
$ pip install pipdeptree
$ pipdeptree --help
$ pipdeptree -r -p boto3
boto3==1.12.49
  - aws-sam-translator==1.25.0 [requires: boto3~=1.5]
    - cfn-lint==0.34.1 [requires: aws-sam-translator>=1.25.0]
      - moto==1.3.14 [requires: cfn-lint>=0.4.0]
  - moto==1.3.14 [requires: boto3>=1.9.201]
```

To isolate the dependency tree to only the package libs without any
development libs, it can help to create a clean virtualenv and only
install the required packages.  After initial analysis of the dep-tree,
then install package extras and repeat the analysis.

```text
# create and activate a new venv any way you like
$ poetry install  # only required packages
$ pip install pipdeptree
$ pipdeptree -p boto3  # what does boto3 depend on
$ pipdeptree -r -p boto3  # what depends on boto3
```

In a similar way, continue with dependencies of a dependency, such
as the dependencies of boto3 and so on.
