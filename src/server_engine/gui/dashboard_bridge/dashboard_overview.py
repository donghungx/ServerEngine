from ._shared import *


class DashboardOverviewMixin(DashboardBridgeSignals):
    @Property("QVariantList", notify=metricsChanged)
    def heroMetrics(self) -> list[dict[str, object]]:
        return self._hero_metrics

    @Property("QVariantMap", notify=metricsChanged)
    def diskMetric(self) -> dict[str, object]:
        return self._disk_metric

    @Property("QVariantList", notify=dataChanged)
    def overviewCards(self) -> list[dict[str, str]]:
        sites = self._container.site_service.list_sites()
        php_versions = self._container.php_runtime_service.list_versions()
        database_runtimes = self._container.database_runtime_service.list_ids()
        redis_runtimes = self._container.redis_runtime_service.list_ids()
        log_sources = self._container.log_service.list_sources()
        return [
            {
                "title": "Website",
                "value": str(len(sites)),
                "accent": "Ready",
                "detail": "Managed local sites",
            },
            {
                "title": "PHP",
                "value": str(len(php_versions)),
                "accent": "Bundled",
                "detail": "Detected runtimes",
            },
            {
                "title": "Database",
                "value": str(len(database_runtimes)),
                "accent": "Versioned",
                "detail": "Available engines",
            },
            {
                "title": "Redis",
                "value": str(len(redis_runtimes)),
                "accent": "Cached",
                "detail": "Detected runtimes",
            },
            {
                "title": "Logs",
                "value": str(len(log_sources)),
                "accent": "Monitored",
                "detail": "Known sources",
            },
        ]

    @Slot()
    def refreshMetrics(self) -> None:
        if self._shutting_down or not self._metrics_thread.isRunning():
            return
        QMetaObject.invokeMethod(self._metrics_worker, "refresh", Qt.QueuedConnection)

    @Slot("QVariantList", "QVariantMap")
    def _apply_metrics(self, hero_metrics: list[dict[str, object]], disk_metric: dict[str, object]) -> None:
        self._hero_metrics = hero_metrics
        self._disk_metric = disk_metric
        self.metricsChanged.emit()
