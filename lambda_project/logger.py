"""
Console logger
"""
import logging
import sys
import time

logging.Formatter.converter = time.gmtime

LOG_FORMAT = (
    "%(asctime)s | %(levelname)-10s | %(name)s:%(funcName)s:%(lineno)d | %(message)s"
)
LOG_FORMATTER = logging.Formatter(LOG_FORMAT)


def console_logger(name: str) -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.formatter = LOG_FORMATTER
    logger = logging.getLogger(name)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger
