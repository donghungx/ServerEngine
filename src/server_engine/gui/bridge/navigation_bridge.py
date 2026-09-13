from __future__ import annotations

class NavigationBridgeMixin:
    def _navigation_items_value(self) -> list[dict[str, str]]:
        return self._navigation_items

    def _set_current_page_impl(self, page_id: str) -> None:
        if page_id == self._current_page:
            return
        if any(item["id"] == page_id for item in self._navigation_items):
            self._current_page = page_id
            self.currentPageChanged.emit()

    def _current_page_value(self) -> str:
        return self._current_page

    def _current_page_index_value(self) -> int:
        order = {
            "home": 0,
            "website": 1,
            "php": 2,
            "database": 3,
            "redis": 4,
            "cache": 5,
            "mail": 6,
            "logs": 7,
        }
        return order.get(self._current_page, 0)

    def _page_title_value(self) -> str:
        for item in self._navigation_items:
            if item["id"] == self._current_page:
                return item["label"]
        return "Home"

    def _page_description_value(self) -> str:
        descriptions = {
            "home": "Overview of the local stack and core runtime health.",
            "website": "Website management surface is ready for the next iteration.",
            "php": "PHP runtime management screen is reserved and ready.",
            "database": "Database runtime controls, creation, and logs.",
            "redis": "Redis runtime controls, version switching, and service logs.",
            "cache": "Memcached runtime controls, version switching, and service logs.",
            "mail": "Mail server tools are staged as a future page.",
            "logs": "Logs and diagnostics page shell is ready.",
        }
        return descriptions.get(self._current_page, "")
