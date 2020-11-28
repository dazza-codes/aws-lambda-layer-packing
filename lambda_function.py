"""
Lambda Layer Test
*****************

This lambda function handler can test that project dependencies
can be imported from the project layer(s).

"""

from lambda_project.check_imports import check_libs


def lambda_handler(event, context):

    check_libs()

    return {"statusCode": 200, "body": "lambda-project imports are OK!"}
