"""Hermes user-plugin entry point for the AgentDeck R2 relay."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


def _load_bundled_package() -> None:
    """Load the src-layout package when installed by Hermes from Git."""
    if importlib.util.find_spec("r2_relay_adapter") is not None:
        return

    package_dir = Path(__file__).resolve().parent / "src" / "r2_relay_adapter"
    spec = importlib.util.spec_from_file_location(
        "r2_relay_adapter",
        package_dir / "__init__.py",
        submodule_search_locations=[str(package_dir)],
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load bundled r2_relay_adapter from {package_dir}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)


_load_bundled_package()

from r2_relay_adapter.hermes_plugin import register  # noqa: E402

__all__ = ["register"]
