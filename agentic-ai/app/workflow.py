"""Execute through deterministic validation; approval remains an in-memory boundary."""
from dataclasses import dataclass
import json
from enum import StrEnum
from time import monotonic
from typing import TypedDict

from langgraph.graph import END, START, StateGraph
from langgraph.runtime import Runtime
from pydantic import ValidationError

from app.llm import AiUnavailable
from app.matching_contracts import StudioMatchingInput, StudioMatchingOutput
from app.package_discovery import PackageDiscoveryFailure
from app.package_contracts import PackageRecommendationOutput
from app.scheduling import SchedulingAgent, SchedulingFailure
from app.scheduling_contracts import SchedulingOutput
from app.scheduling_discovery import SchedulingDiscoveryFailure
from app.package_recommendation import PackageFailure, PackageRecommendationAgent
from app.studio_discovery import DiscoveryFailure
from app.studio_matching import MatchingFailure, StudioMatchingAgent
from app.validation import ValidationAgent, ValidationFailure
from app.validation_contracts import FinalValidationResult, ValidationSelection


class WorkflowStatus(StrEnum):
    SUBMITTED = "Submitted"
    STUDIO_MATCHING = "StudioMatching"
    PACKAGE_RECOMMENDATION = "PackageRecommendation"
    SCHEDULING = "Scheduling"
    VALIDATION = "Validation"
    AWAITING_APPROVAL = "AwaitingApproval"
    APPROVED = "Approved"
    REJECTED = "Rejected"
    FAILED = "Failed"
    REVALIDATION_REQUIRED = "RevalidationRequired"


@dataclass
class MatchingContext:
    # Invocation-only. Never place precise GPS into persisted workflow state.
    request: StudioMatchingInput | dict


class WorkflowState(TypedDict, total=False):
    status: WorkflowStatus
    error_code: str | None
    blocked_stage: str | None
    studio_matching: dict | None
    package_recommendation: dict | None
    scheduling: dict | None
    validation: dict | None
    validation_requirements: dict | None
    events: list[dict]


def _submitted(state: WorkflowState) -> WorkflowState:
    return {"status": WorkflowStatus.SUBMITTED, "error_code": None,
            "blocked_stage": None, "studio_matching": None,
            "package_recommendation": None, "scheduling": None, "validation": None,
            "validation_requirements": None, "events": []}


def _boundary(state: WorkflowState) -> WorkflowState:
    return {"status": WorkflowStatus.PACKAGE_RECOMMENDATION,
            "blocked_stage": WorkflowStatus.PACKAGE_RECOMMENDATION.value,
            "error_code": "package_agent_not_implemented"}


def _failed(state: WorkflowState) -> WorkflowState:
    return {"status": WorkflowStatus.FAILED}


def _scheduling_boundary(state: WorkflowState) -> WorkflowState:
    return {"status": WorkflowStatus.SCHEDULING, "blocked_stage": "Scheduling",
            "error_code": "scheduling_agent_not_implemented"}


def _awaiting_approval(state: WorkflowState) -> WorkflowState:
    return {"status": WorkflowStatus.AWAITING_APPROVAL, "blocked_stage": "AwaitingApproval", "error_code": None}


def build_workflow(agent: StudioMatchingAgent | None = None,
                   package_agent: PackageRecommendationAgent | None = None,
                   scheduling_agent: SchedulingAgent | None = None,
                   validation_agent: ValidationAgent | None = None):
    async def matching(state: WorkflowState, runtime: Runtime[MatchingContext]):
        started = monotonic()
        output, code = None, None
        try:
            if agent is None:
                raise MatchingFailure("matching_agent_not_configured")
            if runtime.context is None:
                raise MatchingFailure("invalid_matching_input")
            request = StudioMatchingInput.model_validate(runtime.context.request)
            output = await agent.match(request)
            if not output.rankedStudios:
                code = "no_matching_studios"
        except ValidationError:
            code = "invalid_matching_input"
        except AiUnavailable as exc:
            code = {"not_configured": "gemini_not_configured", "timeout": "gemini_timeout",
                    "malformed_structured_output": "malformed_structured_output"}.get(
                        exc.code, "gemini_unavailable")
        except (DiscoveryFailure, MatchingFailure) as exc:
            code = exc.code
        # Operational event shape matches Phase 2; ASP.NET assigns workflow ID
        # and timestamps if/when a persistence adapter is added. No raw content.
        event = {"eventType": "StudioMatchingFailed" if code else "StudioMatchingCompleted",
                 "stepName": "StudioMatching", "summary": "Studio matching failed." if code
                 else "Studio matching completed.", "success": code is None,
                 "durationMs": int((monotonic() - started) * 1000),
                 "detailsJson": json.dumps({"errorCode": code}) if code else None}
        return {"status": WorkflowStatus.STUDIO_MATCHING, "error_code": code,
                "blocked_stage": "StudioMatching" if code else None,
                "studio_matching": output.model_dump(mode="json") if output else None,
                "events": [event]}

    async def recommending(state: WorkflowState, runtime: Runtime[MatchingContext]):
        started = monotonic()
        output, code = None, None
        try:
            if runtime.context is None:
                raise PackageFailure("invalid_package_input")
            request = StudioMatchingInput.model_validate(runtime.context.request)
            studios = StudioMatchingOutput.model_validate(state.get("studio_matching"))
            output = await package_agent.recommend(request.requirements, studios)
        except ValidationError:
            code = "invalid_package_input"
        except AiUnavailable as exc:
            code = {"not_configured": "gemini_not_configured", "timeout": "gemini_timeout",
                    "malformed_structured_output": "invalid_gemini_output"}.get(exc.code, "gemini_unavailable")
        except (PackageDiscoveryFailure, PackageFailure) as exc:
            code = exc.code
        event = {"eventType": "PackageRecommendationFailed" if code else "PackageRecommendationCompleted",
                 "stepName": "PackageRecommendation", "summary": "Package recommendation failed." if code
                 else "Package recommendation completed.", "success": code is None,
                 "durationMs": int((monotonic() - started) * 1000),
                 "detailsJson": json.dumps({"errorCode": code}) if code else None}
        return {"status": WorkflowStatus.PACKAGE_RECOMMENDATION, "error_code": code,
                "blocked_stage": "PackageRecommendation" if code else None,
                "package_recommendation": output.model_dump(mode="json") if output else None,
                "events": [*state.get("events", []), event]}

    async def scheduling(state: WorkflowState, runtime: Runtime[MatchingContext]):
        started = monotonic()
        output, code = None, None
        try:
            if runtime.context is None:
                raise SchedulingFailure("invalid_scheduling_input")
            request = StudioMatchingInput.model_validate(runtime.context.request)
            studios = StudioMatchingOutput.model_validate(state.get("studio_matching"))
            # Workflow state is JSON-shaped: strict wire validation restores Decimal values.
            packages = PackageRecommendationOutput.model_validate_json(json.dumps(state.get("package_recommendation")))
            result = await scheduling_agent.schedule(request.requirements, studios, packages)
            output = SchedulingOutput.model_validate(result.model_dump(), strict=True)
        except ValidationError:
            code = "invalid_scheduling_input"
        except (SchedulingFailure, SchedulingDiscoveryFailure) as exc:
            code = exc.code
        except AiUnavailable as exc:
            code = {"not_configured": "gemini_not_configured", "timeout": "gemini_timeout",
                    "malformed_structured_output": "invalid_gemini_output"}.get(exc.code, "gemini_unavailable")
        event = {"eventType": "SchedulingFailed" if code else "SchedulingCompleted",
                 "stepName": "Scheduling", "summary": "Scheduling failed." if code else "Scheduling completed.",
                 "success": code is None, "durationMs": int((monotonic() - started) * 1000),
                 "detailsJson": json.dumps({"errorCode": code}) if code else None}
        return {"status": WorkflowStatus.SCHEDULING, "error_code": code,
                "blocked_stage": "Scheduling" if code else None,
                "scheduling": output.model_dump(mode="json") if output is not None and code is None else None,
                "events": [*state.get("events", []), event]}

    async def validating(state: WorkflowState, runtime: Runtime[MatchingContext]):
        started = monotonic()
        output, code, normalized = None, None, None
        safe_codes = {"invalid_workflow_state", "validation_failed", "stale_recommendation", "price_changed",
                      "slot_unavailable", "booking_conflict", "budget_failure", "invalid_backend_response",
                      "backend_timeout", "backend_unavailable"}
        try:
            if runtime.context is None or validation_agent is None:
                raise ValidationFailure("invalid_workflow_state")
            request = StudioMatchingInput.model_validate(runtime.context.request)
            studios = StudioMatchingOutput.model_validate(state.get("studio_matching"))
            packages = PackageRecommendationOutput.model_validate_json(json.dumps(state.get("package_recommendation")))
            scheduled = SchedulingOutput.model_validate_json(json.dumps(state.get("scheduling")))
            # Deterministic selection policy: validate the first ranked slot, never fall back.
            slot = scheduled.rankedSlots[0]
            package = next(p for p in packages.rankedPackages if
                           (p.studioId, p.packageId) == (slot.studioId, slot.packageId))
            selection = ValidationSelection.model_validate({
                **slot.model_dump(include={"studioId", "packageId", "date", "startTime", "endTime"}),
                "customization": package.customization.model_dump()}, strict=True)
        except (ValidationError, ValueError, TypeError, AttributeError, StopIteration, IndexError, ValidationFailure):
            code = "invalid_workflow_state"
        if code is None:
            try:
                result = await validation_agent.validate(request.requirements, studios, packages, scheduled, selection)
                output = FinalValidationResult.model_validate(result.model_dump(warnings=False), strict=True)
                if output.current is not None and output.current.selection != selection:
                    raise ValueError("Altered validation selection")
                if output.classification != "Pass":
                    reasons = [f.code for f in output.validation.findings if f.severity == "Error" and f.code in safe_codes]
                    code = next((reason for reason in ("price_changed", "slot_unavailable", "booking_conflict", "stale_recommendation")
                                 if reason in reasons), reasons[0] if reasons else "validation_failed")
                normalized = request.requirements.model_dump(mode="json", exclude={"notes"})
            except (ValidationError, ValueError, TypeError, AttributeError):
                output, code = None, "invalid_backend_response"
            except ValidationFailure as error:
                code = error.code if error.code in safe_codes else "backend_unavailable"
            except TimeoutError:
                code = "backend_timeout"
            except Exception:
                code = "backend_unavailable"
        revalidation = output is not None and output.classification == "RevalidationRequired"
        event_type = "ValidationRevalidationRequired" if revalidation else "ValidationFailed" if code else "ValidationCompleted"
        event = {"eventType": event_type, "stepName": "Validation",
                 "summary": "Recommendation requires revalidation." if revalidation else
                            "Validation failed." if code else "Validation completed.",
                 "success": code is None, "durationMs": int((monotonic() - started) * 1000),
                 "detailsJson": json.dumps({"errorCode": code}) if code else None}
        return {"status": WorkflowStatus.REVALIDATION_REQUIRED if revalidation else WorkflowStatus.VALIDATION,
                "error_code": code, "blocked_stage": "Validation",
                "validation": output.model_dump(mode="json") if output is not None else None,
                "validation_requirements": normalized, "events": [*state.get("events", []), event]}

    graph = StateGraph(WorkflowState, context_schema=MatchingContext)
    graph.add_node("Submitted", _submitted)
    graph.add_node("StudioMatching", matching)
    # Explicit omission supports isolated earlier-phase callers/tests. Production
    # create_app injects all four agents; no publication or approval action occurs.
    graph.add_node("PackageRecommendation", recommending if package_agent is not None else _boundary)
    if package_agent is not None:
        graph.add_node("Scheduling", scheduling if scheduling_agent is not None else _scheduling_boundary)
        if scheduling_agent is None:
            graph.add_edge("Scheduling", END)
        else:
            graph.add_node("Validation", validating)
            graph.add_node("AwaitingApproval", _awaiting_approval)
            graph.add_conditional_edges("Scheduling",
                lambda state: "Failed" if state.get("error_code") else "Validation", ["Failed", "Validation"])
            graph.add_conditional_edges("Validation", lambda state:
                END if state["status"] == WorkflowStatus.REVALIDATION_REQUIRED else
                "Failed" if state.get("error_code") else "AwaitingApproval", [END, "Failed", "AwaitingApproval"])
            graph.add_edge("AwaitingApproval", END)
    graph.add_node("Failed", _failed)
    graph.add_edge(START, "Submitted")
    graph.add_edge("Submitted", "StudioMatching")
    graph.add_conditional_edges("StudioMatching",
                                lambda state: "Failed" if state.get("error_code") else "PackageRecommendation",
                                ["Failed", "PackageRecommendation"])
    if package_agent is None:
        graph.add_edge("PackageRecommendation", END)
    else:
        graph.add_conditional_edges("PackageRecommendation",
                                    lambda state: "Failed" if state.get("error_code") else "Scheduling",
                                    ["Failed", "Scheduling"])
    graph.add_edge("Failed", END)
    return graph.compile()
