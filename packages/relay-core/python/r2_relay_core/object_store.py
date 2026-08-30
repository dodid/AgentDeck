from __future__ import annotations

from typing import Any, Protocol


class ObjectStore(Protocol):
    async def put_object(
        self,
        key: str,
        body: bytes | str,
        content_type: str | None = None,
        tagging: str | None = None,
        if_match: str | None = None,
        if_none_match: str | None = None,
    ) -> Any:
        ...

    async def get_object(self, key: str) -> Any | None:
        ...

    async def get_json_with_etag(self, key: str) -> dict[str, Any] | None:
        ...

    async def delete_object(self, key: str) -> Any:
        ...

    async def delete_objects(self, keys: list[str]) -> Any:
        ...

    async def list_prefix_page(
        self,
        prefix: str,
        continuation_token: str | None = None,
        max_keys: int = 1000,
    ) -> dict[str, Any]:
        ...
