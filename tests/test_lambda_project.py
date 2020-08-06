"""
Test the lambda_project package
"""
from types import ModuleType

import lambda_project


def test_lambda_project():
    assert isinstance(lambda_project, ModuleType)


def test_lambda_project_version():
    assert isinstance(lambda_project.version, ModuleType)
    assert isinstance(lambda_project.VERSION, str)
