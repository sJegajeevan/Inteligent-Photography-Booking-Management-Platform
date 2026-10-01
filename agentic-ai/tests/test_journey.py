"""Real one-node LangGraph and authenticated boundary; provider/backend IO are offline doubles."""
import asyncio
import json
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import httpx
import pytest

from app.config import Settings
from app.main import create_app
from app.validation import ValidationAgent
from test_validation import state
from test_validation_discovery import payload, tool

TOKEN = 'offline-journey-token-with-at-least-32-characters'
STAGES = ['StudioMatching', 'PackageRecommendation', 'Scheduling', 'Validation']


def setup(stage):
    values = state()
    app = create_app(Settings(_env_file=None, internal_workflow_token=TOKEN))
    agents = [SimpleNamespace(match=AsyncMock(return_value=values['studios'])),
              SimpleNamespace(recommend=AsyncMock(return_value=values['packages'])),
              SimpleNamespace(schedule=AsyncMock(return_value=values['scheduling']))]
    calls = []
    def backend(request):
        calls.append(request)
        return httpx.Response(200, json=payload())
    app.state.studio_matching, app.state.package_recommendation, app.state.scheduling = agents
    app.state.validation = ValidationAgent(tool(backend))
    body = dict(operationId=str(uuid4()), stage=stage, requirements=values['requirements'].model_dump(mode='json'),
                studios=None, packages=None, scheduling=None)
    for i, key in enumerate(['studios', 'packages', 'scheduling']):
        if STAGES.index(stage) > i:
            body[key] = values[key].model_dump(mode='json')
    return app, body, agents, calls


def send(app, body, token=TOKEN, workflow=None):
    async def run():
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://internal') as client:
            return await client.post(f'/internal/ai-workflows/{workflow or uuid4()}/stage', json=body,
                                     headers={'X-Internal-Token': token})
    return asyncio.run(run())


def test_real_matching_200_matches_aspnet_persistence_regression_fixture():
    from app.studio_discovery import StudioDiscoveryTool
    from app.studio_matching import StudioMatchingAgent
    from test_studio_matching import studio, request

    fixture = json.loads((Path(__file__).resolve().parents[2] /
        'backend/tests/Phase1Checks/Fixtures/python-studio-stage.json').read_text(encoding='utf-8'))
    settings = Settings(_env_file=None, internal_workflow_token=TOKEN)
    app = create_app(settings)
    backend_studios = [studio(id=item['studioId']) for item in fixture['output']['rankedStudios']]
    from tests.test_studio_matching import with_feasible_packages
    discovery = StudioDiscoveryTool(settings, transport=httpx.MockTransport(with_feasible_packages(lambda _: httpx.Response(200, json=backend_studios))))
    llm = SimpleNamespace(rank_studios=AsyncMock(return_value=json.dumps({'rankedStudios': fixture['output']['rankedStudios']})))
    app.state.studio_matching = StudioMatchingAgent(discovery, llm)
    app.state.package_recommendation = SimpleNamespace(recommend=AsyncMock())
    app.state.scheduling = SimpleNamespace(schedule=AsyncMock())
    app.state.validation = SimpleNamespace(validate=AsyncMock())
    body = dict(operationId=fixture['operationId'], stage='StudioMatching',
                requirements=request(requestedServices=[]).requirements.model_dump(mode='json'),
                studios=None, packages=None, scheduling=None)
    response = send(app, body, workflow=fixture['workflowId'])
    assert response.status_code == 200
    assert response.json() == fixture
    llm.rank_studios.assert_awaited_once()
    app.state.package_recommendation.recommend.assert_not_awaited()
    app.state.scheduling.schedule.assert_not_awaited()
    app.state.validation.validate.assert_not_awaited()


@pytest.mark.parametrize('stage', STAGES)
def test_exactly_one_real_graph_stage(stage):
    app, body, agents, calls = setup(stage)
    response = send(app, body)
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['errorCode'] is None, result
    assert result['stage'] == stage and result['operationId'] == body['operationId']
    for i, (agent, method) in enumerate(zip(agents, ['match', 'recommend', 'schedule'])):
        assert getattr(agent, method).await_count == (STAGES.index(stage) == i)
    assert len(calls) == (stage == 'Validation')
    if stage == 'Validation':
        assert result['output']['classification'] == 'Pass'
        assert result['output']['isReservation'] is False


@pytest.mark.parametrize('stage,missing', [('PackageRecommendation', 'studios'), ('Scheduling', 'packages'), ('Validation', 'scheduling')])
def test_no_downstream_stage_without_selected_prerequisite(stage, missing):
    app, body, agents, calls = setup(stage)
    body[missing] = None
    assert send(app, body).status_code == 400
    assert not calls
    for agent in agents:
        for method in vars(agent).values():
            method.assert_not_awaited()


def test_foreign_package_and_multiple_choices_rejected():
    for mutate in [lambda b: b['packages']['rankedPackages'][0].update(studioId=str(uuid4())),
                   lambda b: b['studios']['rankedStudios'].append(b['studios']['rankedStudios'][0])]:
        app, body, _, calls = setup('Scheduling')
        mutate(body)
        assert send(app, body).status_code == 400
        assert not calls


def test_authentication_and_failure_are_safe():
    app, body, agents, calls = setup('StudioMatching')
    assert send(app, body, 'wrong').status_code == 401
    agents[0].match.side_effect = RuntimeError('PRIVATE token provider response')
    response = send(app, body)
    assert response.json()['errorCode'] == 'invalid_execution_response'
    assert response.json()['output'] is None
    assert 'PRIVATE' not in response.text
    agents[1].recommend.assert_not_awaited()
    agents[2].schedule.assert_not_awaited()
    assert not calls
