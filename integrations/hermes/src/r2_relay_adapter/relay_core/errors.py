from __future__ import annotations


class RelayTransportError(RuntimeError):
    """Base error for shared relay transport failures."""


class PreconditionFailedError(RelayTransportError):
    """Raised when an object-store CAS precondition fails."""


class CASRetryExceededError(RelayTransportError):
    """Raised when a message append cannot win the head CAS race in time."""
