"""Local manual runner for the private graph; never writes files or bookings."""
import argparse
import asyncio
import json
from pathlib import Path

from pydantic import ValidationError

from app.config import Settings
from app.main import create_app
from app.matching_contracts import StudioMatchingInput
from app.workflow import MatchingContext


def main():
    parser = argparse.ArgumentParser(description="Run recommendations through deterministic validation; no proposal publication")
    parser.add_argument("input", type=Path, help="JSON matching request file")
    args = parser.parse_args()
    try:
        request = StudioMatchingInput.model_validate_json(args.input.read_text(encoding="utf-8-sig"))
        settings = Settings()
    except (OSError, ValueError, ValidationError):
        print(json.dumps({"error_code": "invalid_local_input_or_configuration"}))
        return 1
    app = create_app(settings)
    result = asyncio.run(app.state.workflow.ainvoke({}, context=MatchingContext(request)))
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "AwaitingApproval" and result.get("error_code") is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
