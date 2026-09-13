from __future__ import annotations

import ssl


def default_ssl_context(url: str) -> ssl.SSLContext | None:
    if not str(url or "").lower().startswith("https://"):
        return None

    context = ssl.create_default_context()
    try:
        import certifi  # type: ignore

        context.load_verify_locations(cafile=certifi.where())
    except Exception:
        pass
    return context
