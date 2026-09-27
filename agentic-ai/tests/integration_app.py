"""Local integration harness: real four agents/tools; ONLY Gemini ranking is replaced.

Never used by the production app. No .env is loaded and no provider calls are made.
"""
import json
import os

from app.config import Settings
from app.main import create_app
from app.workflow import build_workflow


class FixtureRanking:
    async def rank_studios(self, payload):
        candidate = json.loads(payload)["candidates"][0]
        return json.dumps({"rankedStudios": [{"studioId": candidate["studioId"],
            "explanationSummary": candidate["allowedReasons"][0]}]})

    async def rank_packages(self, payload):
        candidate = json.loads(payload)["candidates"][0]
        return json.dumps({"rankedPackages": [{"studioId": candidate["studioId"],
            "packageId": candidate["packageId"], "explanationSummary": candidate["allowedReasons"][0]}]})

    async def rank_slots(self, payload):
        candidate = json.loads(payload)["candidates"][0]
        return json.dumps({"rankedSlots": [{"slotId": candidate["slotId"],
            "explanationSummary": candidate["allowedReasons"][0]}]})


def create_integration_app():
    settings = Settings(_env_file=None, aspnet_api_base_url=os.environ["ASPNET_API_BASE_URL"],
        internal_workflow_token=os.environ["INTERNAL_WORKFLOW_TOKEN"], gemini_api_key="", gemini_model="")
    app = create_app(settings)
    for agent in (app.state.studio_matching, app.state.package_recommendation, app.state.scheduling):
        agent.llm = FixtureRanking()
    app.state.workflow = build_workflow(app.state.studio_matching, app.state.package_recommendation,
        app.state.scheduling, app.state.validation)
    return app
