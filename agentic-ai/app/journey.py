"""One authenticated graph node per customer transition. ASP.NET owns all state."""
import asyncio
import hmac
import json
from typing import Literal
from uuid import UUID

from fastapi import Request
from fastapi.responses import JSONResponse, Response
from pydantic import model_validator

from app.internal_execution import REQUEST_LIMIT, RESPONSE_LIMIT, _unique_object, _DIAGNOSTIC_CODES
from app.matching_contracts import StudioMatchingInput, StudioMatchingOutput
from app.package_contracts import PackageRecommendationOutput
from app.scheduling_contracts import SchedulingContract, SchedulingOutput
from app.validation_contracts import ValidationRequirements
from app.workflow import build_workflow, MatchingContext


class StageRequest(SchedulingContract):
    operationId: UUID
    stage: Literal['StudioMatching', 'PackageRecommendation', 'Scheduling', 'Validation']
    requirements: ValidationRequirements
    studios: StudioMatchingOutput | None = None
    packages: PackageRecommendationOutput | None = None
    scheduling: SchedulingOutput | None = None

    @model_validator(mode='after')
    def prerequisites(self):
        if not self.operationId.int or self.requirements.notes is not None:
            raise ValueError('Invalid request')
        index = ['StudioMatching', 'PackageRecommendation', 'Scheduling', 'Validation'].index(self.stage)
        for needed, value in [(index >= 1, self.studios), (index >= 2, self.packages), (index >= 3, self.scheduling)]:
            if needed != (value is not None):
                raise ValueError('Invalid prerequisites')
        if self.studios is not None and len(self.studios.rankedStudios) != 1:
            raise ValueError('One selected studio required')
        if self.packages is not None:
            if len(self.packages.rankedPackages) != 1 or self.packages.rankedPackages[0].studioId != self.studios.rankedStudios[0].studioId:
                raise ValueError('One package from selected studio required')
        if self.scheduling is not None:
            if len(self.scheduling.rankedSlots) != 1:
                raise ValueError('One selected schedule required')
            slot, package = self.scheduling.rankedSlots[0], self.packages.rankedPackages[0]
            if (slot.studioId, slot.packageId) != (package.studioId, package.packageId):
                raise ValueError('Unrelated schedule')
        return self


def register_journey(service, settings):
    @service.post('/internal/ai-workflows/{workflow_id}/stage')
    async def stage(workflow_id: str, request: Request):
        expected = settings.internal_workflow_token.get_secret_value()
        supplied = request.headers.getlist('x-internal-token')
        if not 32 <= len(expected) <= 512 or len(supplied) != 1 or not hmac.compare_digest(supplied[0].encode(), expected.encode()):
            return JSONResponse(status_code=401, content={'errorCode': 'unauthorized'})
        try:
            if not UUID(workflow_id).int:
                raise ValueError('Invalid workflow')
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > REQUEST_LIMIT:
                    return JSONResponse(status_code=413, content={'errorCode': 'invalid_request'})
            json.loads(body, object_pairs_hook=_unique_object)
            data = StageRequest.model_validate_json(body)
        except (ValueError, TypeError):
            return JSONResponse(status_code=400, content={'errorCode': 'invalid_request'})
        output, code = None, None
        try:
            graph = build_workflow(service.state.studio_matching, service.state.package_recommendation,
                                   service.state.scheduling, service.state.validation, stage=data.stage)
            state = {key: value.model_dump(mode='json') for key, value in
                     [('studio_matching', data.studios), ('package_recommendation', data.packages),
                      ('scheduling', data.scheduling)] if value is not None}
            async with asyncio.timeout(settings.workflow_timeout_seconds):
                state = await graph.ainvoke(state, context=MatchingContext(StudioMatchingInput(requirements=data.requirements)))
            code = state.get('error_code')
            if code is None:
                output = state[{'StudioMatching': 'studio_matching', 'PackageRecommendation': 'package_recommendation',
                                'Scheduling': 'scheduling', 'Validation': 'validation'}[data.stage]]
            elif code not in _DIAGNOSTIC_CODES:
                code = 'execution_failed'
        except TimeoutError:
            code = 'execution_timeout'
        except Exception:
            code = 'invalid_execution_response'
        payload = dict(workflowId=workflow_id, operationId=str(data.operationId), stage=data.stage, output=output, errorCode=code)
        encoded = json.dumps(payload).encode()
        if len(encoded) > RESPONSE_LIMIT:
            payload.update(output=None, errorCode='invalid_execution_response')
            encoded = json.dumps(payload).encode()
        return Response(content=encoded, media_type='application/json')
