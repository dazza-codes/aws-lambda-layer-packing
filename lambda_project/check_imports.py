from types import ModuleType

from importlib import import_module

from lambda_project.logger import console_logger

LOGGER = console_logger(__name__)


def check_import(module_name):

    try:
        mod = import_module(module_name)
        assert isinstance(mod, ModuleType)
        LOGGER.info("Import success: %s", module_name)

    except ModuleNotFoundError:
        LOGGER.error("Import failed: %s", module_name)


def check_gis_libs():
    """Check Imports for GIS libs"""

    for lib in [
        "numpy",
        "geopandas",
        "pandas",
        "fiona",
        "pycrs",
        "pyproj",
        "shapely",
        "s2sphere",
    ]:
        check_import(lib)


def check_raster_libs():
    """Check Imports for Raster libs"""
    for lib in ["affine", "rasterio", "rasterstats"]:
        check_import(lib)


def check_aws_libs():
    """Check Imports for AWS libs"""
    for lib in ["boto3", "botocore"]:
        check_import(lib)


def check_util_libs():
    """Check Imports for Util libs"""
    for lib in ["dataclasses", "requests", "urllib3"]:
        check_import(lib)


def check_libs():
    check_gis_libs()
    check_raster_libs()
    check_aws_libs()
    check_util_libs()


if __name__ == "__main__":
    check_libs()
