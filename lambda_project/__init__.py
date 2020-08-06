"""
AWS Lambda Layer Builds
"""

import logging

# invoke-release version information
from .version import __version__  # noqa: F401
from .version import __version_info__

VERSION = __version__

# Set default logging handler to avoid "No handler found" warnings.
logging.getLogger(__name__).addHandler(logging.NullHandler())
