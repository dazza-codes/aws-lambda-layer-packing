from types import ModuleType

from importlib import import_module
from typing import List

from lambda_project.logger import console_logger

LOGGER = console_logger(__name__)


def check_import(module_name: str) -> bool:

    try:
        mod = import_module(module_name)
        assert isinstance(mod, ModuleType)
        LOGGER.info("Import success: %s", module_name)
        return True

    except ModuleNotFoundError:
        LOGGER.error("Import failed: %s", module_name)
        return False


def check_import_libs(libs: List[str]) -> bool:
    """Check Imports for libs"""
    return all([check_import(lib) for lib in libs])


def check_gis_libs() -> bool:
    """Check Imports for GIS libs"""
    libs = [
        "numpy",
        "geopandas",
        "pandas",
        "fiona",
        "pyproj",
        "shapely",
        "s2sphere",
    ]
    return check_import_libs(libs)


def check_raster_libs() -> bool:
    """Check Imports for Raster libs"""
    libs = ["affine", "rasterio", "rasterstats"]
    return check_import_libs(libs)


def check_parquet_libs() -> bool:
    """Check Imports for Parquet libs"""
    libs = ["pyarrow"]
    return check_import_libs(libs)


def check_aws_libs() -> bool:
    """Check Imports for AWS libs"""
    libs = ["boto3", "botocore"]
    return check_import_libs(libs)


def check_util_libs() -> bool:
    """Check Imports for Util libs"""
    libs = ["dataclasses", "requests", "urllib3"]
    return check_import_libs(libs)


def check_libs() -> bool:
    return all(
        [check_gis_libs(), check_raster_libs(), check_aws_libs(), check_util_libs(),]
    )


if __name__ == "__main__":
    check_libs()
