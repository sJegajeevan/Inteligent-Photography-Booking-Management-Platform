import socket

import pytest


@pytest.fixture(autouse=True)
def isolated_environment(monkeypatch):
    for name in ("GEMINI_API_KEY", "GEMINI_MODEL", "ASPNET_API_BASE_URL",
                 "AI_TIMEOUT_SECONDS", "AI_MAX_ATTEMPTS", "ASPNET_TIMEOUT_SECONDS",
                 "INTERNAL_WORKFLOW_TOKEN", "WORKFLOW_TIMEOUT_SECONDS"):
        monkeypatch.delenv(name, raising=False)

    original_connect = socket.socket.connect
    original_connect_ex = socket.socket.connect_ex

    def guarded(original):
        def connect(sock, address):
            # Windows asyncio creates a loopback socket pair for its wakeup pipe.
            if isinstance(address, tuple) and address[0] in {"127.0.0.1", "::1"}:
                return original(sock, address)
            raise AssertionError("External network access is forbidden in foundation tests")
        return connect

    monkeypatch.setattr(socket.socket, "connect", guarded(original_connect))
    monkeypatch.setattr(socket.socket, "connect_ex", guarded(original_connect_ex))
