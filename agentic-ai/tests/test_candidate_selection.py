"""Real discovery/quote adapters, shared eligibility, and ranking validation; no external IO."""
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import UUID

import httpx
import pytest

from app.config import Settings
from app.package_discovery import PackageDiscoveryTool, PackageDiscoveryFailure
from app.package_recommendation import PackageRecommendationAgent, PackageFailure
from app.studio_discovery import StudioDiscoveryTool
from app.studio_matching import StudioMatchingAgent, MatchingFailure
from tests.test_package_recommendation import package, quote, studios
from tests.test_studio_matching import studio, request


def uid(number):
    return str(UUID(int=number))


def setup(count, *, package_stage=False, mutation=None, ranking_mutation=None):
    settings = Settings(_env_file=None)
    sids = [uid(100 + i) for i in range(1 if package_stage else count)]
    rows = {sid: [package(id=uid(1000 + i), studioId=sid, addons=[])] for i, sid in enumerate(sids)}
    if package_stage:
        rows[sids[0]] = [package(id=uid(1000 + i), studioId=sids[0], addons=[]) for i in range(count)]
    prices = {p['id']: 60000 for ps in rows.values() for p in ps}
    studio_rows = [studio(id=sid) for sid in sids]
    if mutation:
        mutation(studio_rows, rows, prices)
    calls = []
    def backend(req):
        calls.append(req)
        if req.url.path == '/api/public/studios':
            return httpx.Response(200, json=studio_rows)
        parts = req.url.path.split('/')
        sid = parts[4]
        assert sid in sids
        if req.method == 'GET':
            return httpx.Response(200, json=rows[sid])
        pid = parts[6]
        body = json.loads(req.content)
        return httpx.Response(200, json=quote(packageId=pid, finalPrice=prices[pid], extraHours=body['extraHours']))
    tool = PackageDiscoveryTool(settings, transport=httpx.MockTransport(backend))
    prompts = []
    async def rank(payload):
        data = json.loads(payload)
        prompts.append(data)
        # Explicitly rank reverse to prove we preserve model order rather than backend order.
        chosen = list(reversed(data['candidates']))[:data['targetCount']]
        key = 'rankedPackages' if package_stage else 'rankedStudios'
        items = [{**{k: c[k] for k in (['studioId', 'packageId'] if package_stage else ['studioId'])},
                  'explanationSummary': c['allowedReasons'][0]} for c in chosen]
        if ranking_mutation:
            ranking_mutation(items)
        return json.dumps({key: items})
    llm = SimpleNamespace(rank_studios=AsyncMock(side_effect=rank), rank_packages=AsyncMock(side_effect=rank))
    if package_stage:
        agent = PackageRecommendationAgent(tool, llm)
        run = lambda: agent.recommend(request().requirements, studios(sids))
    else:
        agent = StudioMatchingAgent(StudioDiscoveryTool(settings, transport=httpx.MockTransport(backend)), llm, tool)
        run = lambda: agent.match(request())
    return run, prompts, calls, llm


@pytest.mark.parametrize('count', [1, 2, 3, 5])
@pytest.mark.parametrize('package_stage', [False, True])
def test_exact_target_and_authoritative_model_order(count, package_stage):
    run, prompts, calls, llm = setup(count, package_stage=package_stage)
    result = asyncio.run(run())
    options = result.rankedPackages if package_stage else result.rankedStudios
    assert len(options) == min(3, count) == prompts[0]['targetCount']
    key = 'packageId' if package_stage else 'studioId'
    assert [getattr(o, key) for o in options] == [c[key] for c in list(reversed(prompts[0]['candidates']))[:3]]
    if package_stage:
        assert all(str(o.pricing.finalPrice) == '60000' for o in options)  # not basePrice=50000
        assert all(o.studioId == uid(100) for o in options)
        assert all('/studios/' + uid(100) + '/packages' in str(c.url) for c in calls)
    else:
        llm.rank_packages.assert_not_awaited()  # feasibility is not Agent 2


@pytest.mark.parametrize('package_stage', [False, True])
@pytest.mark.parametrize('bad', ['incomplete', 'invented', 'duplicate', 'excess', 'malformed'])
def test_invalid_rankings_fail_closed(package_stage, bad):
    def mutate(items):
        if bad == 'incomplete': del items[1:]
        if bad == 'invented': items[0]['packageId' if package_stage else 'studioId'] = uid(9999)
        if bad == 'duplicate': items[1] = items[0]
        if bad == 'excess': items.append(items[0])
        if bad == 'malformed': items[0]['unexpectedPrice'] = 1
    run, _, _, _ = setup(3, package_stage=package_stage, ranking_mutation=mutate)
    with pytest.raises((MatchingFailure, PackageFailure)):
        asyncio.run(run())


@pytest.mark.parametrize('package_stage', [False, True])
@pytest.mark.parametrize('why', ['budget', 'services', 'duration'])
def test_unsuitable_candidate_excluded_before_ranking(package_stage, why):
    def mutate(studio_rows, rows, prices):
        first = next(iter(rows.values()))[0]
        if why == 'budget': prices[first['id']] = 100001
        if why == 'services': first['services'] = []
        if why == 'duration': first['durationHours'] = 25
    run, prompts, _, _ = setup(2, package_stage=package_stage, mutation=mutate)
    result = asyncio.run(run())
    assert len(result.rankedPackages if package_stage else result.rankedStudios) == 1
    assert prompts[0]['targetCount'] == 1


def test_studio_without_packages_excluded():
    run, prompts, _, _ = setup(2, mutation=lambda ss, rows, prices: rows.__setitem__(ss[0]['id'], []))
    assert len(asyncio.run(run()).rankedStudios) == 1
    assert prompts[0]['candidates'][0]['studioId'] == uid(101)


@pytest.mark.parametrize('package_stage', [False, True])
@pytest.mark.parametrize('bad', ['foreign', 'inactive', 'invalid'])
def test_untrusted_package_response_cannot_establish_eligibility(package_stage, bad):
    def mutate(ss, rows, prices):
        p = next(iter(rows.values()))[0]
        if bad == 'foreign': p['studioId'] = uid(9999)
        if bad == 'inactive': p['status'] = 'Inactive'
        if bad == 'invalid': p['durationHours'] = 0
    run, prompts, _, _ = setup(1, package_stage=package_stage, mutation=mutate)
    with pytest.raises(PackageDiscoveryFailure):
        asyncio.run(run())
    assert not prompts


def test_gemini_foreign_studio_package_rejected():
    run, _, _, _ = setup(2, package_stage=True, ranking_mutation=lambda items: items[0].update(studioId=uid(9999)))
    with pytest.raises(PackageFailure, match='unknown_package_reference'):
        asyncio.run(run())


@pytest.mark.parametrize('affordable', [2, 4, 51])
def test_51_packages_are_quoted_before_budget_filtering_and_shortlisting(affordable):
    def mutate(ss, rows, prices):
        # The affordable candidates are at the end, beyond any pre-quote slice.
        for i, p in enumerate(rows[ss[0]['id']]):
            prices[p['id']] = 60000 if i >= 51 - affordable else 100001
    run, prompts, calls, _ = setup(51, package_stage=True, mutation=mutate)
    result = asyncio.run(run())
    assert len([c for c in calls if c.method == 'POST']) == 51
    assert prompts[0]['targetCount'] == len(result.rankedPackages) == min(3, affordable)
    supplied = prompts[0]['candidates']
    assert len(supplied) == min(50, affordable)
    assert all(c['pricing']['finalPrice'] == '60000' for c in supplied)
    assert all(c['studioId'] == uid(100) for c in supplied)
    assert [o.packageId for o in result.rankedPackages] == [c['packageId'] for c in list(reversed(supplied))[:3]]
    if affordable == 2:
        assert {o.packageId for o in result.rankedPackages} == {uid(1049), uid(1050)}
    assert any('50 lowest-priced' in c for c in result.unmetPreferences) == (affordable > 50)


def test_shortlist_uses_authoritative_price_then_stable_ids_after_all_quotes():
    def mutate(ss, rows, prices):
        rows[ss[0]['id']].reverse()
        prices[uid(1050)] = 50000
    run, prompts, calls, _ = setup(51, package_stage=True, mutation=mutate)
    asyncio.run(run())
    assert len([c for c in calls if c.method == 'POST']) == 51
    assert [c['packageId'] for c in prompts[0]['candidates']] == [uid(1050), *[uid(i) for i in range(1000, 1049)]]


@pytest.mark.parametrize('affordable', [0, 2, 51])
def test_studio_feasibility_with_51_packages_does_not_abort_other_studios(affordable):
    def mutate(ss, rows, prices):
        sid = ss[0]['id']
        rows[sid] = [package(id=uid(2000 + i), studioId=sid, addons=[]) for i in range(51)]
        for i, p in enumerate(rows[sid]):
            prices[p['id']] = 60000 if i >= 51 - affordable else 100001
    run, prompts, calls, llm = setup(2, mutation=mutate)
    result = asyncio.run(run())
    assert len([c for c in calls if c.method == 'POST']) == 52
    assert {o.studioId for o in result.rankedStudios} == ({uid(100), uid(101)} if affordable else {uid(101)})
    assert prompts[0]['targetCount'] == len(result.rankedStudios)
    llm.rank_packages.assert_not_awaited()


@pytest.mark.parametrize('bad', ['incomplete', 'invented', 'duplicate', 'excess', 'malformed', 'omitted'])
def test_bounded_package_ranking_still_rejects_untrusted_output(bad):
    def mutate(items):
        if bad == 'incomplete': del items[1:]
        if bad == 'invented': items[0]['packageId'] = uid(9999)
        if bad == 'duplicate': items[1] = items[0]
        if bad == 'excess': items.append(items[0])
        if bad == 'malformed': items[0]['unexpectedPrice'] = 1
        # Authoritatively eligible, but not supplied to Gemini: still forbidden.
        if bad == 'omitted': items[0]['packageId'] = uid(1050)
    run, _, _, _ = setup(51, package_stage=True, ranking_mutation=mutate)
    with pytest.raises(PackageFailure):
        asyncio.run(run())
