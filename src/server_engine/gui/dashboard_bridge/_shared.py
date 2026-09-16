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


class SslCertificateWorker(QObject):
    completed = Signal(bool, str)

    def __init__(self, container, kind: str, entity_id: str) -> None:
        super().__init__()
        self._container = container
        self._kind = kind
        self._entity_id = entity_id

    @Slot()
    def run(self) -> None:
        try:
            if self._kind == "site":
                entity = self._container.site_service.get_site(self._entity_id)
                ensure = self._container.config_service.ensure_site_ssl_certificate
            elif self._kind == "node":
                entity = self._container.node_project_service.repository.get(self._entity_id)
                ensure = self._container.config_service.ensure_node_project_ssl_certificate
            else:
                entity = self._container.proxy_service.repository.get(self._entity_id)
                ensure = self._container.config_service.ensure_proxy_ssl_certificate
            if entity is None:
                raise ValueError(f"{self._kind.title()} project not found.")
            result = ensure(entity)
            if not result.success:
                raise ValueError(result.message)
            self.completed.emit(True, f"SSL certificate ready for {entity.local_domain}")
        except Exception as exc:
            self.completed.emit(False, str(exc))


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
