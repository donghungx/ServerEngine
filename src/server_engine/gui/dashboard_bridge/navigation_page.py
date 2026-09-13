from ._shared import *


class NavigationPageMixin(DashboardBridgeSignals):
    def _navigation_items_value(self) -> list[dict[str, str]]:
        items = list(self._navigation_items)
        if self.optionalDatabaseRuntimeDownloaded("postgresql"):
            insert_at = next((index + 1 for index, item in enumerate(items) if item["id"] == "mail"), len(items))
            items.insert(insert_at, {"id": "postgresql", "label": "PostgreSQL", "badge": "", "icon": "postgresql"})
        if self.optionalDatabaseRuntimeDownloaded("mongodb"):
            insert_at = next((index + 1 for index, item in enumerate(items) if item["id"] == "postgresql"), None)
            if insert_at is None:
                insert_at = next((index + 1 for index, item in enumerate(items) if item["id"] == "mail"), len(items))
            items.insert(insert_at, {"id": "mongodb", "label": "MongoDB", "badge": "", "icon": "mongodb"})
        return items

    def _set_current_page_impl(self, page_id: str) -> None:
        if page_id == self._current_page:
            return
        if page_id == "database-backup" or any(item["id"] == page_id for item in self._navigation_items_value()):
            self._current_page = page_id
            self.currentPageChanged.emit()

    def _current_page_index_value(self) -> int:
        order = {
            "home": 0,
            "website": 1,
            "php": 2,
            "database": 3,
            "redis": 4,
            "cache": 5,
            "mail": 6,
            "postgresql": 7,
            "mongodb": 8,
            "database-backup": 9,
        }
        return order.get(self._current_page, 0)

    def _page_description_value(self) -> str:
        if self._current_page == "postgresql":
            return "PostgreSQL runtime controls, database management, and logs."
        if self._current_page == "mongodb":
            return "MongoDB runtime controls, database management, and logs."
        return super()._page_description_value()

    @Property("QVariantList", notify=dataChanged)
    def navigationItems(self) -> list[dict[str, str]]:
        return self._navigation_items_value()

    def _set_current_page(self, page_id: str) -> None:
        self._set_current_page_impl(page_id)

    @Property(str, fset=_set_current_page, notify=currentPageChanged)
    def currentPage(self) -> str:
        return self._current_page_value()

    @Property(int, notify=currentPageChanged)
    def currentPageIndex(self) -> int:
        return self._current_page_index_value()

    @Property(str, notify=currentPageChanged)
    def pageTitle(self) -> str:
        return self._page_title_value()

    @Property(str, notify=currentPageChanged)
    def pageDescription(self) -> str:
        return self._page_description_value()

    @Slot(str)
    def setCurrentPage(self, page_id: str) -> None:
        self._set_current_page(page_id)
