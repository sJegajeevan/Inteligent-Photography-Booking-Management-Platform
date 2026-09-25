from fastapi import FastAPI
from fastapi.responses import JSONResponse

from app.config import Settings
from app.llm import AiUnavailable, GeminiService
from app.workflow import build_workflow
from app.studio_discovery import StudioDiscoveryTool
from app.studio_matching import StudioMatchingAgent
from app.package_discovery import PackageDiscoveryTool
from app.package_recommendation import PackageRecommendationAgent
from app.scheduling import SchedulingAgent
from app.scheduling_discovery import SchedulingDiscoveryTool
from app.validation import ValidationAgent
from app.validation_discovery import ValidationDiscoveryTool
from app.internal_execution import register_execution


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings if settings is not None else Settings()
    service = FastAPI(title="SnapSync Agentic AI", version="0.4.3")
    service.state.llm = GeminiService(settings)
    service.state.studio_matching = StudioMatchingAgent(StudioDiscoveryTool(settings), service.state.llm)
    service.state.package_recommendation = PackageRecommendationAgent(PackageDiscoveryTool(settings), service.state.llm)
    service.state.scheduling = SchedulingAgent(SchedulingDiscoveryTool(settings), service.state.llm)
    service.state.validation = ValidationAgent(ValidationDiscoveryTool(settings))
    service.state.workflow = build_workflow(service.state.studio_matching, service.state.package_recommendation,
                                            service.state.scheduling, service.state.validation)
    register_execution(service, settings)

    @service.get("/health")
    async def health():
        return {"status": "ok", "service": "snapsync-agentic-ai"}

    @service.get("/health/ai")
    async def ai_health():
        try:
            await service.state.llm.check_connectivity()
        except AiUnavailable as exc:
            return JSONResponse(status_code=503, content={"status": "unavailable", "code": exc.code})
        return {"status": "ok", "provider": "gemini", "check": "model_metadata"}

    return service
