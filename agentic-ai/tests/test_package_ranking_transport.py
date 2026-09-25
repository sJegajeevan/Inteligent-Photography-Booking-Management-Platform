"""Exercise the real Google SDK's JSON Schema serialization without network access."""
import asyncio
import json

import httpx
import pytest
from google import genai

from app.config import Settings
from app.llm import GeminiService
from app.matching_contracts import StudioMatchingInput
from app.package_contracts import PackageRanking
from app.main import create_app
from app.workflow import MatchingContext
from test_package_recommendation import SID, PID, REASON, package, quote, ranking, request
from test_scheduling_discovery import payload as slot_payload
from test_scheduling import ranking as slot_ranking


@pytest.mark.parametrize('scenario,expected', [
    ('valid', 'backend_unavailable'),
    ('extra', 'invalid_gemini_output'),
    ('malformed', 'invalid_gemini_output'),
    ('empty', 'invalid_gemini_output'),
    ('provider400', 'gemini_unavailable'),
    ('provider503', 'gemini_unavailable'),
    ('timeout', 'gemini_timeout'),
])
def test_full_app_sdk_transport_and_validation(monkeypatch, scenario, expected):
    real_client = genai.Client
    provider_calls, configs = [], []

    async def run():
        async def provider_response(req):
            body = json.loads(req.content)
            config = body['generationConfig']
            is_package = 'rankedPackages' in config['responseJsonSchema']['properties']
            is_scheduling = 'rankedSlots' in config['responseJsonSchema']['properties']
            provider_calls.append('scheduling' if is_scheduling else 'package' if is_package else 'studio')
            if is_scheduling:
                output = slot_ranking()
            elif not is_package:
                output = json.dumps({'rankedStudios': [{'studioId': SID, 'explanationSummary':
                    'Supports all photography types and lists a starting price within the maximum budget.'}]})
            else:
                configs.append(config)
                assert config['responseMimeType'] == 'application/json'
                assert config['responseJsonSchema'] == PackageRanking.model_json_schema()
                assert config['responseJsonSchema']['additionalProperties'] is False
                assert config['responseJsonSchema']['$defs']['PackageMatch']['additionalProperties'] is False
                assert 'responseSchema' not in config
                assert 'additional_properties' not in req.content.decode()
                assert 'tools' not in body
                if scenario == 'timeout':
                    await asyncio.sleep(1)
                if scenario in ('provider400', 'provider503'):
                    code = 400 if scenario == 'provider400' else 503
                    return httpx.Response(code, json={'error': {'code': code, 'message': 'private provider detail test-only-dummy-key',
                                                              'status': 'INVALID_ARGUMENT' if code == 400 else 'UNAVAILABLE'}})
                output = {'extra': ranking(price=1), 'malformed': 'not json', 'empty': ''}.get(scenario, ranking())
            return httpx.Response(200, json={'candidates': [{'content': {'role': 'model', 'parts': [{'text': output}]},
                                                          'finishReason': 'STOP'}]})

        async with httpx.AsyncClient(transport=httpx.MockTransport(provider_response)) as provider:
            clients = []
            def client_factory(**kwargs):
                kwargs['http_options'].httpx_async_client = provider
                client = real_client(**kwargs)
                clients.append(client)
                return client
            monkeypatch.setattr('app.llm.genai.Client', client_factory)
            settings = Settings(_env_file=None, gemini_api_key='test-only-dummy-key', gemini_model='test-model',
                                ai_timeout_seconds=0.1 if scenario == 'timeout' else 5)
            app = create_app(settings)
            def backend(req):
                if req.url.path == '/api/public/studios':
                    return httpx.Response(200, json=[dict(id=SID, studioName='Studio', location='Jaffna',
                        descriptionSummary='', photographyTypes=['All'], startingPrice=0, distanceKm=None)])
                if req.method == 'GET':
                    return httpx.Response(200, json=[package()])
                assert req.method == 'POST'
                if req.url.path == f'/api/public/studios/{SID}/packages/{PID}/available-slots':
                    return httpx.Response(200, json=slot_payload(studioId=SID, packageId=PID, packageDurationHours=4, extraHours=0))
                if req.url.path.endswith('/validate-recommendation'):
                    return httpx.Response(500, text='private backend detail')
                assert req.url.path == f'/api/public/studios/{SID}/packages/{PID}/calculate-price'
                return httpx.Response(200, json=quote())
            app.state.studio_matching.discovery.transport = httpx.MockTransport(backend)
            app.state.package_recommendation.discovery.transport = httpx.MockTransport(backend)
            app.state.scheduling.discovery.transport = httpx.MockTransport(backend)
            app.state.validation.discovery._transport = httpx.MockTransport(backend)
            try:
                stages, result = [], {}
                async for update in app.state.workflow.astream({}, context=MatchingContext(request()), stream_mode='updates'):
                    stages.extend(update)
                    for values in update.values():
                        result.update(values)
                assert result['error_code'] == expected
                assert stages == ['Submitted', 'StudioMatching', 'PackageRecommendation'] + (
                    ['Scheduling', 'Validation', 'Failed'] if scenario == 'valid' else ['Failed'])
                assert result['blocked_stage'] == ('Validation' if scenario == 'valid' else 'PackageRecommendation')
                assert result['events'][0]['eventType'] == 'StudioMatchingCompleted'
                assert result['events'][1]['success'] == (scenario == 'valid')
                for private in ['private provider detail', 'test-only-dummy-key']:
                    assert private not in json.dumps(result)
                if scenario != 'valid':
                    assert result['package_recommendation'] is None
            finally:
                for client in clients:
                    client.close()
        assert provider_calls.count('studio') == 1
        assert provider_calls.count('package') == (2 if scenario in ('provider503', 'timeout') else 1)
        assert provider_calls.count('scheduling') == (1 if scenario == 'valid' else 0)
        assert configs

    asyncio.run(run())
