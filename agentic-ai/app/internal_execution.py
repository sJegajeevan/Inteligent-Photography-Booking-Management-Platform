"""Authenticated, bounded adapter around the existing graph. No persistence tools."""
import asyncio
import hmac
import json
from typing import Literal
from uuid import UUID

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from pydantic import model_validator

from app.matching_contracts import NearbySearch, StudioMatchingInput
from app.scheduling_contracts import SchedulingContract, SchedulingCandidateResponse, SchedulingOutput
from app.validation_contracts import FinalValidationResult, ValidationRequirements
from app.workflow import MatchingContext

REQUEST_LIMIT = 16_384
RESPONSE_LIMIT = 65_536


class ExecutionRequest(SchedulingContract):
    executionId: UUID
    requirements: ValidationRequirements
    nearby: NearbySearch | None = None

    @model_validator(mode="after")
    def normalized(self):
        if self.executionId.int == 0 or self.requirements.notes is not None:
            raise ValueError("Invalid execution request")
        return self


class ExecutionCompletion(SchedulingContract):
    workflowId: UUID
    executionId: UUID
    status: Literal["AwaitingApproval", "Failed", "RevalidationRequired", "NeedsInput"]
    requirements: ValidationRequirements
    evidence: FinalValidationResult | None
    schedulingEvidence: SchedulingCandidateResponse | None
    errorCode: Literal["execution_failed", "execution_timeout", "invalid_execution_response",
                       "revalidation_required", "needs_input"] | None

    @model_validator(mode="after")
    def consistent(self):
        if self.status == "AwaitingApproval":
            if (self.errorCode is not None or self.evidence is None or self.schedulingEvidence is None or
                    self.evidence.classification != "Pass" or self.evidence.validation.findings):
                raise ValueError("Incomplete successful completion")
        elif self.evidence is not None or self.schedulingEvidence is not None or self.errorCode is None:
            raise ValueError("Failure must not contain publication evidence")
        return self


def completion(workflow_id: UUID, request: ExecutionRequest, state: dict) -> ExecutionCompletion:
    status = state["status"]
    common = dict(workflowId=workflow_id, executionId=request.executionId, requirements=request.requirements)
    if status in ("Failed", "RevalidationRequired", "NeedsInput"):
        return ExecutionCompletion(**common, status=status, evidence=None, schedulingEvidence=None,
            errorCode={"Failed": "execution_failed", "RevalidationRequired": "revalidation_required",
                       "NeedsInput": "needs_input"}[status])
    if status != "AwaitingApproval" or state.get("error_code") is not None:
        raise ValueError("Invalid terminal state")
    normalized = ValidationRequirements.model_validate_json(json.dumps(state["validation_requirements"]))
    if normalized != request.requirements:
        raise ValueError("Changed requirements")
    evidence = FinalValidationResult.model_validate_json(json.dumps(state["validation"]))
    scheduling = SchedulingOutput.model_validate_json(json.dumps(state["scheduling"]))
    selection = evidence.current.selection
    slot = scheduling.rankedSlots[0]
    if any(getattr(slot, key) != getattr(selection, key) for key in
           ("studioId", "packageId", "date", "startTime", "endTime")):
        raise ValueError("Changed selection")
    retained = next(e for e in scheduling.backendEvidence if
                    (e.studioId, e.packageId) == (selection.studioId, selection.packageId))
    candidates = [c for c in retained.candidates if
                  (c.date, c.startTime, c.endTime, c.evidenceIds) ==
                  (slot.date, slot.startTime, slot.endTime, slot.evidenceIds)]
    if len(candidates) != 1:
        raise ValueError("Missing selected scheduling evidence")
    retained = retained.model_copy(update={"candidates": candidates})
    return ExecutionCompletion(**common, status="AwaitingApproval", evidence=evidence,
                               schedulingEvidence=retained, errorCode=None)


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate property")
        result[key] = value
    return result


def register_execution(service, settings):
    @service.post("/internal/ai-workflows/{workflow_id}/run", response_model=ExecutionCompletion)
    async def run(workflow_id: str, request: Request):
        expected = settings.internal_workflow_token.get_secret_value()
        supplied = request.headers.getlist("x-internal-token")
        if (not 32 <= len(expected) <= 512 or len(supplied) != 1 or
                not hmac.compare_digest(supplied[0].encode(), expected.encode())):
            return JSONResponse(status_code=401, content={"errorCode": "unauthorized"})
        try:
            identifier = UUID(workflow_id)
            if identifier.int == 0:
                raise ValueError("Empty workflow")
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > REQUEST_LIMIT:
                    return JSONResponse(status_code=413, content={"errorCode": "invalid_request"})
            json.loads(body, object_pairs_hook=_unique_object)
            data = ExecutionRequest.model_validate_json(body)
        except (ValueError, TypeError):
            return JSONResponse(status_code=400, content={"errorCode": "invalid_request"})
        try:
            async with asyncio.timeout(settings.workflow_timeout_seconds):
                state = await service.state.workflow.ainvoke({}, context=MatchingContext(
                    StudioMatchingInput(requirements=data.requirements, nearby=data.nearby)))
            result = completion(identifier, data, state)
            encoded = result.model_dump_json().encode()
            if len(encoded) > RESPONSE_LIMIT:
                raise ValueError("Oversized completion")
        except TimeoutError:
            result = ExecutionCompletion(workflowId=identifier, executionId=data.executionId,
                requirements=data.requirements, status="Failed", evidence=None, schedulingEvidence=None,
                errorCode="execution_timeout")
            encoded = result.model_dump_json().encode()
        except Exception:
            # Never emit/log graph state, provider messages, credentials, or exception text.
            result = ExecutionCompletion(workflowId=identifier, executionId=data.executionId,
                requirements=data.requirements, status="Failed", evidence=None, schedulingEvidence=None,
                errorCode="invalid_execution_response")
            encoded = result.model_dump_json().encode()
        return Response(content=encoded, media_type="application/json")
