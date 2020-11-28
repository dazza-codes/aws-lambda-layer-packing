
# AWS Lambda Packaging

## Getting Started

Use the `make` recipes to build and deploy lambda layers for this project.
The layer builds use a docker container with the AWS lambda build system
for python (3.6 is used at the time of writing, depends on the venv).

The layer packages are based on the `pyproject.toml` specs;
by using `poetry export` to identify the project dependencies and `poetry build` to
create a pip wheel for the project. The layer zip archives are generated in
`/tmp/{project_name}/*.zip`.

- `make docker-boto-libs` checks the boto libraries in an AWS Lambda runtime
- `make docker-base-build` prepares the docker base image to build layers
- `make docker-base-shell` a bash shell in a base container
- `make docker-test-build` prepares the docker test image to run tests
- `make docker-test-shell` a bash shell in a test container
- `make docker-test-run` runs the docker test image
  - this runs a pytest suite on a pip installation that is like the layer
  - this is not a trivial test setup and test suite (it might be fragile)
- `make docker-shell` drops into a bash shell in the test docker container
- `make layer-package` builds one or more lambda layers
  - it reports on the location of the layer artifacts and their sizes
  - it does not publish anything to AWS S3 or Lambda
- `make layer-size` reports the total size of each layer
  - this report is also provided by `make layer-package`
  - this assumes that `make layer-package` has been run already
- `make layer-publish` pushes updated layers to AWS S3 and Lambda
  - this assumes that `make layer-package` has been run already
  - use `source aws_profile.sh` and `aws-profile` to manage AWS credentials
  - use `make aws-check` and `make aws-settings` to verify AWS details
  - this assumes that AWS S3_BUCKET is defined allows uploads
  - this assumes that AWS credentials are available and allow publishing
  - this calculates zip archive metadata to detect when an update is required (or not)
- `make function-publish` pushes a test lambda function to AWS Lambda
  - at present, the AWS console is required to update the layer it uses

After `make layer-package`, check the layer sizes are within limits, and
then use `make layer-publish` to release new versioned layers.

```text
$ make layer-size

MAX BYTES   262144000 bytes
                28458 bytes in py36-lambda-project-0.1.0-nodeps.zip
            249618460 bytes in py36-lambda-project-0.1.0-pyarrow.zip
            254553398 bytes in py36-lambda-project-0.1.0-sql.zip
            228347643 bytes in py36-lambda-project-0.1.0-xarray.zip
            209424398 bytes in py36-lambda-project-0.1.0.zip

```

These package sizes are just an example - as this project for lambda packaging
evolves, the optional package details may change and some details of the package
optimizations may change.  The packages that include optional extra dependencies
use a suffix to suggest the extras included, but check the project
`pyproject.toml` for details.  Some layer packages with additional extras are
too large for AWS lambda.  If a project requires optional extras that exceed the
AWS Lambda limits, the project will need to use a docker container or other
solution that isolates only the dependencies required in some custom dependency
solution.  Additional details about optimizing packages are noted below.

## AWS Lambda Notes

The following notes relate to packaging this project for AWS lambda.
The creation of a lambda layer for the project is not trivial, for
several reasons:

- the library versions and APIs are complicated
- the CRS systems are complex in python libraries
- the size of the dependency libraries and restrictions on lambda package size

The builds follow the guidelines from the
[AWS knowledge center](https://aws.amazon.com/premiumsupport/knowledge-center/lambda-layer-simulated-docker/).
It recommends using the [lambci/lambda](https://hub.docker.com/r/lambci/lambda/) Docker images,
to simulate the live Lambda environment and create a layer that's compatible
with the runtimes that you specify. For more information, see
[lambci/lambda](https://hub.docker.com/r/lambci/lambda/) on the Docker website.
Note that lambci/lambda images are not an exact copy of the Lambda environment
and some files may be missing. The AWS Serverless Application Model (AWS SAM)
also uses the lambci/lambda Docker images when you run `sam local start-api`

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

### Lambda Limits

See https://docs.aws.amazon.com/lambda/latest/dg/limits.html
- Function and layer storage: 75 GB
- Deployment package size
  - 250 MB (unzipped, including layers)
  -  50 MB (zipped, for direct upload)
  -   3 MB (console editor)

### AWS SDK packages

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

### Splitting Layers for Large Packages

There are several large packages for scientific python projects:

```text
$ du -sh /opt/python/lib/python3.6/site-packages/* | grep -E '^[0-9]*M' | sort
11M	/opt/python/lib/python3.6/site-packages/numba
14M	/opt/python/lib/python3.6/site-packages/numpy
24M	/opt/python/lib/python3.6/site-packages/pandas
24M	/opt/python/lib/python3.6/site-packages/pyproj
32M	/opt/python/lib/python3.6/site-packages/numpy.libs
44M	/opt/python/lib/python3.6/site-packages/fiona
55M	/opt/python/lib/python3.6/site-packages/rasterio
57M	/opt/python/lib/python3.6/site-packages/llvmlite
```

The `pip show` command can list a package dependencies and
the packages that depend on it, e.g.

```text
$ python -m pip show boto3
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
