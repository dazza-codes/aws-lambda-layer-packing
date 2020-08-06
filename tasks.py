"""
Configure the invoke release task
"""

from invoke_release.tasks import *  # noqa: F403
from invoke_release.plugins import PatternReplaceVersionInFilesPlugin

configure_release_parameters(  # noqa: F405
    module_name="lib",
    display_name="AWS Lambda Layer Builds",
    plugins=[
        PatternReplaceVersionInFilesPlugin(
            "lib/version.py", "pyproject.toml"
        )
    ],
)
