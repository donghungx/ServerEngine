from __future__ import annotations

from dataclasses import replace
import base64
import hashlib
import logging
import os
import re
import shlex
import shutil
import socket
import subprocess
import tarfile
import tempfile
import urllib.parse
import urllib.request
import urllib.error
import zipfile
import sys
from datetime import datetime
import json
from pathlib import Path
import time
from typing import Callable

from PySide6.QtCore import QCoreApplication, QObject, Property, QMetaObject, Qt, QThread, QTimer, QProcess, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtWidgets import QApplication, QFileDialog, QMessageBox, QDialog, QDialogButtonBox, QLabel, QVBoxLayout

from server_engine.gui.bridge.workers import (
    DatabaseBackupWorker,
    DatabaseBackupItemsWorker,
    DatabaseRestartWorker,
    DatabaseSizeWorker,
    AppSettingsSaveWorker,
    GlobalStackWorker,
    HomeServiceWorker,
    MailpitActionWorker,
    MemcachedRestartWorker,
    MetricsWorker,
    MongodbActionWorker,
    MongodbItemsWorker,
    NodeProjectInstallDependenciesWorker,
    NodeProjectModulesWorker,
    NodeProjectRuntimeActionWorker,
    NodeProjectSaveWorker,
    PhpRuntimeServiceActionWorker,
    PhpInfoWorker,
    PhpMyAdminWorker,
    RedisRestartWorker,
    RequiredRuntimeBootstrapWorker,
    RuntimeInstallWorker,
    RuntimeManifestWorker,
    SiteCreationWorker,
    WebRestartWorker,
    WebRouteReloadWorker,
)
from server_engine.gui.bridge.navigation_bridge import NavigationBridgeMixin
from server_engine.bootstrap import AppContainer
from server_engine.infrastructure.ssl_support import default_ssl_context

LOGGER = logging.getLogger("server_engine.runtime_install")
LOCAL_DOMAIN_PATTERN = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$")
RUNTIME_MANAGER_SERVICES = {
    "php",
    "phpmyadmin",
    "apache",
    "nginx",
    "mysql",
    "mariadb",
    "mongodb",
    "postgresql",
    "redis",
    "memcached",
    "mailpit",
    "node",
}
SQL_DATABASE_RUNTIME_SERVICES = {"mysql", "mariadb"}
OPTIONAL_DATABASE_RUNTIME_SERVICES = {"mongodb", "postgresql"}


def macos_prefers_dark_appearance() -> bool:
    if sys.platform != "darwin":
        return False
    try:
        import AppKit
    except ImportError:
        return False
    try:
        style = AppKit.NSUserDefaults.standardUserDefaults().stringForKey_("AppleInterfaceStyle")
        return bool(str(style or "").strip())
    except Exception:
        return False


from .signals import *
