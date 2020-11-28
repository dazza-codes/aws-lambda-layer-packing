"""
Test the lambda_project package
"""
from types import ModuleType

import lambda_project
from lambda_project.check_imports import check_libs


def test_lambda_project():
    assert isinstance(lambda_project, ModuleType)


def test_lambda_project_version():
    assert isinstance(lambda_project.version, ModuleType)
    assert isinstance(lambda_project.VERSION, str)


def test_check_libs():
    assert check_libs()
