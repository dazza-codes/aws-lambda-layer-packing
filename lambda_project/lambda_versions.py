"""
Lambda Library Versions
***********************

This lambda function handler prints built-in package versions.

"""
from typing import Dict

import boto3
import botocore
import jmespath
import dateutil
import s3transfer
import six
import urllib3

import os
import pprint
import sysconfig


def boto_versions() -> Dict:
    versions = {
        "boto3": boto3.__version__,
        "botocore": botocore.__version__,
        "jmespath": jmespath.__version__,
        "dateutil": dateutil.__version__,
        "s3transfer": s3transfer.__version__,
        "six": six.__version__,
        "urllib3": urllib3.__version__,
    }
    return versions


def lambda_handler(event, context):

    os.system("ls -1d /var/runtime/*.dist-info | sort")
    print()

    sys_paths = sysconfig.get_paths()
    pprint.pprint(sys_paths)
    print()

    versions = boto_versions()
    pprint.pprint(versions)
    print()

    # pip requirements format
    for k, v in versions.items():
        print(f"{k}=={v}")
    print()

    return {"statusCode": 200, "body": "lambda versions done"}
