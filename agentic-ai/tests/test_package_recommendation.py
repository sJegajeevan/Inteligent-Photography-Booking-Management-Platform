"""Phase 4.2 uses mocked ASP.NET and Gemini boundaries only."""
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest

from app.config import Settings
from app.llm import AiUnavailable
from app.matching_contracts import StudioMatchingInput, StudioMatchingOutput
from app.package_contracts import PackageCustomization
from app.package_discovery import PackageDiscoveryFailure, PackageDiscoveryTool
from app.package_recommendation import PackageRecommendationAgent
from app.workflow import MatchingContext, build_workflow

SID = 'aaaaaaaa-1234-4234-8234-123456789012'
SID2 = 'bbbbbbbb-1234-4234-8234-123456789012'
PID = 'cccccccc-1234-4234-8234-123456789012'
PID2 = 'dddddddd-1234-4234-8234-123456789012'
SERVICE_ID = 'eeeeeeee-1234-4234-8234-123456789012'
ADDON_ID = 'ffffffff-1234-4234-8234-123456789012'
REASON = 'Includes every requested service and the backend quote is within the requested budget.'
STAMP = '2026-09-22T00:00:00Z'


def package(**changes):
    value = dict(id=PID, studioId=SID, name='Wedding package', description='Backend text',
        basePrice=50000, extraHourRate=1000, additionalPhotographerRate=2000,
        durationHours=4, numberOfPhotographers=1, editedPhotoCount=100,
        albumIncluded=False, videoIncluded=False, coverImageUrl='', status='Active',
        createdAt=STAMP, updatedAt=STAMP,
        services=[dict(id=SERVICE_ID, serviceName='Photography', description='Included')],
        addons=[dict(id=ADDON_ID, packageId=PID, name='Album', description='Optional',
                     price=5000, createdAt=STAMP, updatedAt=STAMP)])
    value.update(changes)
    return value


def quote(**changes):
    value = dict(packageId=PID, packageName='Wedding package', basePrice=50000,
        selectedAddons=[], extraHours=0, extraHoursCost=0, additionalPhotographers=0,
        additionalPhotographersCost=0, finalPrice=50000)
    value.update(changes)
    return value


def request(**changes):
    value = dict(photographyType='Wedding', location='Jaffna', maximumBudget=100000,
        earliestDate='2026-12-01', latestDate='2026-12-02', coverageHours=4,
        requestedServices=['Photography'])
    value.update(changes)
    return StudioMatchingInput(requirements=value)


def studios(ids=(SID,)):
    return StudioMatchingOutput(rankedStudios=[dict(studioId=s, explanationSummary='Validated studio')
        for s in ids], unmetPreferences=[])


def ranking(**changes):
    item = dict(studioId=SID, packageId=PID, explanationSummary=REASON)
    item.update(changes)
    return json.dumps(dict(rankedPackages=[item]))


def execute(*, packages=None, priced=None, raw=None, handler=None, error=None, req=None,
            selected=None, timeout=10):
    calls = []
    def backend(http_request):
        calls.append(http_request)
        if handler:
            return handler(http_request)
        if http_request.method == 'GET':
            return httpx.Response(200, json=[package()] if packages is None else packages)
        return httpx.Response(200, json=quote() if priced is None else priced)
    tool = PackageDiscoveryTool(Settings(_env_file=None, aspnet_timeout_seconds=timeout),
                                transport=httpx.MockTransport(backend))
    llm = SimpleNamespace(rank_packages=AsyncMock(return_value=ranking() if raw is None else raw, side_effect=error))
    studio_agent = SimpleNamespace(match=AsyncMock(return_value=studios() if selected is None else selected))
    graph = build_workflow(studio_agent, PackageRecommendationAgent(tool, llm))
    result = asyncio.run(graph.ainvoke({'package_recommendation': {'stale': True}},
        context=MatchingContext(req or request())))
    return result, llm, calls


def test_success_quotes_and_preserves_events_at_scheduling_boundary():
    result, llm, calls = execute()
    assert result['status'] == 'Scheduling'
    assert result['blocked_stage'] == 'Scheduling'
    assert result['error_code'] == 'scheduling_agent_not_implemented'
    rec = result['package_recommendation']['rankedPackages'][0]
    assert rec['packageId'] == PID
    assert rec['customization'] == dict(selectedAddonIds=[], extraHours=0, additionalPhotographers=0)
    assert rec['pricing']['finalPrice'] == '50000'
    assert [e['eventType'] for e in result['events']] == ['StudioMatchingCompleted', 'PackageRecommendationCompleted']
    assert all(e['success'] for e in result['events'])
    assert [(r.method, r.url.path) for r in calls] == [
        ('GET', f'/api/public/studios/{SID}/packages'),
        ('POST', f'/api/public/studios/{SID}/packages/{PID}/calculate-price')]
    assert json.loads(calls[1].content) == rec['customization']
    llm.rank_packages.assert_awaited_once()


def test_ranked_studios_constrain_retrieval_and_allow_ordering():
    def handler(req):
        if req.method == 'GET':
            return httpx.Response(200, json=[package()] if SID in req.url.path else
                [package(id=PID2, studioId=SID2, addons=[])])
        return httpx.Response(200, json=quote(packageId=PID if PID in req.url.path else PID2))
    raw = json.dumps({'rankedPackages': [json.loads(ranking(studioId=SID2, packageId=PID2))['rankedPackages'][0],
                                       json.loads(ranking())['rankedPackages'][0]]})
    result, llm, calls = execute(handler=handler, raw=raw, selected=studios((SID, SID2)))
    assert [r.url.path for r in calls if r.method == 'GET'] == [
        f'/api/public/studios/{SID}/packages', f'/api/public/studios/{SID2}/packages']
    assert [r['packageId'] for r in result['package_recommendation']['rankedPackages']] == [PID2, PID]


@pytest.mark.parametrize('data', [
    [package(studioId=SID2)], [package(status='Inactive')], [package(), package()],
    [dict(id=PID)], {}, [package(id='../bookings')], [package(basePrice=-1)],
    [package(durationHours=0)], [package(durationHours=-1)], [package(durationHours='NaN')],
    [package(addons=[dict(id=ADDON_ID, packageId=PID2, name='Album', description='', price=0, createdAt=STAMP, updatedAt=STAMP)])],
    [package(addons=[dict(id='bad', packageId=PID, name='Album', description='', price=0, createdAt=STAMP, updatedAt=STAMP)])],
    [package(services=[dict(id='bad', serviceName='Photography', description='')])],
    [package(services=package()['services'] * 2)], [package(addons=package()['addons'] * 2)],
    [package(untrusted='extra')], [package(numberOfPhotographers=True)],
])
def test_invalid_backend_packages_fail_closed(data):
    result, llm, calls = execute(packages=data)
    assert result['error_code'] == 'invalid_backend_response'
    assert result['blocked_stage'] == 'PackageRecommendation'
    assert result['package_recommendation'] is None
    assert len(calls) == 1
    llm.rank_packages.assert_not_called()


@pytest.mark.parametrize('names,requested,eligible', [
    ([' Photography '], ['photography'], True),
    (['PHOTOGRAPHY', ' Video '], [' Photography ', 'video'], True),
    (['Photography'], ['Photography', 'Video'], False),
    (['Portrait'], ['Photography'], False),
    (['All'], ['Photography'], False),
    ([], ['Photography'], False),
    ([], [], True),
])
def test_requested_services_require_exact_included_names(names, requested, eligible):
    service_list = [dict(id=f'eeeeeeee-1234-4234-8234-{i:012d}', serviceName=name, description='')
                    for i, name in enumerate(names)]
    reason = REASON if requested else 'The backend quote for the selected customization is within the requested budget.'
    result, llm, calls = execute(packages=[package(services=service_list, description='We offer all Photography and Video services')],
        req=request(requestedServices=requested), raw=ranking(explanationSummary=reason))
    assert result['error_code'] == ('scheduling_agent_not_implemented' if eligible else 'no_matching_packages')
    assert llm.rank_packages.await_count == int(eligible)
    assert len(calls) == (2 if eligible else 1)


@pytest.mark.parametrize('duration,coverage,extra', [(4, 4, 0), (5, 4, 0), (3.5, 4, 1), (2.25, 4, 2)])
def test_coverage_customization_and_no_notes_inference(duration, coverage, extra):
    result, llm, calls = execute(packages=[package(durationHours=duration)], priced=quote(extraHours=extra),
        req=request(coverageHours=coverage, notes='PRIVATE: add an album and two photographers'))
    assert result['status'] == 'Scheduling'
    assert json.loads(calls[1].content) == dict(selectedAddonIds=[], extraHours=extra, additionalPhotographers=0)
    assert 'PRIVATE' not in llm.rank_packages.call_args.args[0]


@pytest.mark.parametrize('changes', [dict(packageId=PID2), dict(extraHours=1), dict(additionalPhotographers=1),
    dict(selectedAddons=[dict(id=ADDON_ID, name='Album', price=5000)]), dict(finalPrice=-1),
    dict(finalPrice='NaN'), dict(extraHours=True), dict(untrusted='extra')])
def test_authoritative_quote_binding(changes):
    result, llm, _ = execute(priced=quote(**changes))
    assert result['error_code'] == 'invalid_backend_response'
    assert result['package_recommendation'] is None
    llm.rank_packages.assert_not_called()


@pytest.mark.parametrize('total,minimum,maximum,eligible', [
    (50000, None, 50000, True), (50001, None, 50000, False),
    (50000, 50000, 100000, True), (49999, 50000, 100000, False),
    (50000, 50000, 50000, True),
])
def test_budget_uses_backend_final_price_only(total, minimum, maximum, eligible):
    # Deliberately different from base/component prices: never reconstruct total.
    result, llm, _ = execute(packages=[package(basePrice=1, extraHourRate=0)],
        priced=quote(basePrice=1, finalPrice=total), req=request(minimumBudget=minimum, maximumBudget=maximum))
    assert result['error_code'] == ('scheduling_agent_not_implemented' if eligible else 'no_matching_packages')
    assert llm.rank_packages.await_count == int(eligible)
    if eligible:
        assert result['package_recommendation']['rankedPackages'][0]['pricing']['finalPrice'] == str(total)


@pytest.mark.parametrize('method', ['GET', 'POST'])
@pytest.mark.parametrize('status', [302, 400, 404, 500, 503])
def test_backend_status_and_no_pricing_fallback(method, status):
    def handler(req):
        if req.method == method:
            return httpx.Response(status, headers={'location': 'https://untrusted.example/'})
        return httpx.Response(200, json=[package()])
    result, llm, calls = execute(handler=handler)
    assert result['error_code'] == 'backend_unavailable'
    assert len(calls) == (1 if method == 'GET' else 2)
    assert result['package_recommendation'] is None
    llm.rank_packages.assert_not_called()


@pytest.mark.parametrize('failure,code', [(httpx.ConnectError('private'), 'backend_unavailable'),
                                       (httpx.ReadTimeout('private'), 'backend_timeout')])
def test_backend_transport_errors(failure, code):
    def handler(req):
        raise failure
    result, llm, _ = execute(handler=handler)
    assert result['error_code'] == code
    assert 'private' not in json.dumps(result)
    llm.rank_packages.assert_not_called()


def test_backend_total_deadline():
    async def slow(req):
        await asyncio.sleep(1)
        return httpx.Response(200, json=[])
    result, llm, _ = execute(handler=slow, timeout=0.01)
    assert result['error_code'] == 'backend_timeout'
    llm.rank_packages.assert_not_called()


@pytest.mark.parametrize('content', [b'not json', b'x' * 1_000_001], ids=['malformed', 'oversized'])
def test_backend_malformed_or_oversized_body(content):
    result, llm, _ = execute(handler=lambda req: httpx.Response(200, content=content))
    assert result['error_code'] == 'invalid_backend_response'
    llm.rank_packages.assert_not_called()


def test_no_packages():
    result, llm, _ = execute(packages=[])
    assert result['error_code'] == 'no_packages'
    llm.rank_packages.assert_not_called()


@pytest.mark.parametrize('raw,code', [
    ('not json', 'invalid_gemini_output'), ('{}', 'invalid_gemini_output'),
    ('{"rankedPackages": []}', 'invalid_gemini_output'),
    (ranking(price=1), 'invalid_gemini_output'), (ranking(selectedAddonIds=[ADDON_ID]), 'invalid_gemini_output'),
    (ranking(extraHours=10), 'invalid_gemini_output'), (ranking(services=['Video']), 'invalid_gemini_output'),
    (ranking(additionalPhotographers=3), 'invalid_gemini_output'),
    (ranking(studioId=SID2), 'unknown_package_reference'), (ranking(packageId=PID2), 'unknown_package_reference'),
    (ranking(studioId=SID.upper()), 'unknown_package_reference'),
    (ranking(explanationSummary='Available on your date.'), 'unsupported_recommendation_claim'),
    (ranking(explanationSummary='Costs LKR 1.'), 'unsupported_recommendation_claim'),
    (ranking(explanationSummary='Includes a free album.'), 'unsupported_recommendation_claim'),
    (json.dumps({'rankedPackages': json.loads(ranking())['rankedPackages'] * 2}), 'duplicate_package_id'),
    (json.dumps({'rankedPackages': json.loads(ranking())['rankedPackages'], 'price': 1}), 'invalid_gemini_output'),
])
def test_untrusted_gemini_output_rejected(raw, code):
    result, _, _ = execute(raw=raw)
    assert result['status'] == 'Failed'
    assert result['blocked_stage'] == 'PackageRecommendation'
    assert result['error_code'] == code
    assert result['package_recommendation'] is None
    assert result['events'][0]['eventType'] == 'StudioMatchingCompleted'
    assert result['events'][1]['eventType'] == 'PackageRecommendationFailed'


def test_wrong_pairing_even_when_both_ids_exist():
    def handler(req):
        if req.method == 'GET':
            return httpx.Response(200, json=[package()] if SID in req.url.path else [package(id=PID2, studioId=SID2, addons=[])])
        return httpx.Response(200, json=quote(packageId=PID if PID in req.url.path else PID2))
    result, _, _ = execute(handler=handler, selected=studios((SID, SID2)), raw=ranking(studioId=SID2))
    assert result['error_code'] == 'unknown_package_reference'


@pytest.mark.parametrize('code,expected', [('timeout', 'gemini_timeout'), ('provider_unavailable', 'gemini_unavailable'),
    ('not_configured', 'gemini_not_configured'), ('malformed_structured_output', 'invalid_gemini_output')])
def test_gemini_failures(code, expected):
    result, _, _ = execute(error=AiUnavailable(code))
    assert result['error_code'] == expected
    assert result['blocked_stage'] == 'PackageRecommendation'
    assert result['package_recommendation'] is None


@pytest.mark.parametrize('bad_id', ['../bookings', 'https://example.com', '00000000-0000-0000-0000-000000000000'])
def test_invalid_uuid_path_cannot_make_request(bad_id):
    handler = AsyncMock()
    tool = PackageDiscoveryTool(Settings(_env_file=None), transport=httpx.MockTransport(handler))
    with pytest.raises(PackageDiscoveryFailure, match='invalid_package_reference'):
        asyncio.run(tool.packages(bad_id))
    with pytest.raises(PackageDiscoveryFailure, match='invalid_package_reference'):
        asyncio.run(tool.quote(SID, bad_id, PackageCustomization(extraHours=0)))
    handler.assert_not_called()


def test_candidate_limit_fails_before_quotes_or_gemini():
    data = [package(id=f'cccccccc-1234-4234-8234-{i:012d}', addons=[]) for i in range(51)]
    result, llm, calls = execute(packages=data)
    assert result['error_code'] == 'package_candidate_limit_exceeded'
    assert len(calls) == 1
    llm.rank_packages.assert_not_called()


def test_no_sensitive_input_in_prompt_or_events():
    req = request(notes='private-hidden-reasoning-marker').model_dump()
    req['nearby'] = dict(latitude=6.9271, longitude=79.8612, radiusKm=15)
    result, llm, _ = execute(req=StudioMatchingInput.model_validate(req))
    serialized = json.dumps(result['events']) + llm.rank_packages.call_args.args[0]
    for private in ['6.9271', '79.8612', 'private-hidden-reasoning-marker', 'GEMINI_API_KEY']:
        assert private not in serialized
    assert all(set(e) == {'eventType', 'stepName', 'summary', 'success', 'durationMs', 'detailsJson'} for e in result['events'])
