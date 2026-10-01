using System.Data.Common;
using System.Reflection;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

// Offline only: no API startup, configuration, connection string, or SQL execution.
var count = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception("FAIL: " + name);
    count++;
}
string Resource(string name)
{
    using var reader = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream(name)!);
    return reader.ReadToEnd().Replace("\r\n", "\n");
}
var deployment = Resource("JourneyDeployment.sql");
var sql = AiJourneyDetailsConstraint.Sql.Replace("\r\n", "\n");
var literal = Regex.Match(deployment, @"new_expr text := \$journey\$\n([\s\S]*?)\n\$journey\$;").Groups[1].Value;
Check(literal == sql, "deployment and model literal ordinal parity");
var options = new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql()
    .AddInterceptors(new RejectConnections()).Options;
using var db = new ApplicationDbContext(options);
var model = db.GetService<IDesignTimeModel>().Model;
var entity = model.FindEntityType(typeof(AiWorkflowEvent))!;
Check(entity.GetCheckConstraints().Single(c => c.Name == "CK_AiWorkflowEvents_Details").Sql == AiJourneyDetailsConstraint.Sql,
    "actual EF event constraint uses reviewed expression");
Check(entity.FindProperty(nameof(AiWorkflowEvent.DetailsJson))!.GetColumnType() == "jsonb", "JSONB mapping unchanged");
var legacy = Regex.Match(deployment, @"legacy_expr text := \$legacy\$([\s\S]*?)\$legacy\$;").Groups[1].Value;
Check(Resource("LegacyDeployment.sql").Contains("CHECK (" + legacy + ")"), "legacy predicate identical to historical deployment");
Check(sql.EndsWith("ELSE (" + legacy + ") END"), "legacy branch preserved verbatim");
foreach (var predicate in new[] {
    "AND octet_length(\"DetailsJson\"::text) <= 4096",
    "char_length((\"DetailsJson\"->'journey')->>'reason') BETWEEN 1 AND 300",
    "->>'kind' = 'failed' AND NOT \"Success\"",
    "->>'kind' <> 'failed' AND \"Success\"",
    "WHEN 'StudioMatching' THEN 'PackageRecommendation'",
    "WHEN 'PackageRecommendation' THEN 'Scheduling'",
    "WHEN 'Scheduling' THEN 'Validation' END",
    "->>'invalidatesFrom' = \"StepName\"",
    "), FALSE) ELSE (" })
    Check(sql.Contains(predicate), "SQL semantic gate: " + predicate);
foreach (var name in new[] { "AiWorkflows", "AiWorkflowApprovals", "Bookings" })
{
    Check(!deployment.Contains('"' + name + '"'), "deployment does not address " + name);
}
foreach (var marker in new[] { "BEGIN;", "COMMIT;", "IN ACCESS EXCLUSIVE MODE", "current_expr = expected_legacy",
    "current_expr = expected_new", "Unexpected details constraint definition", "convalidated AND conislocal",
    "VALIDATE CONSTRAINT", "JourneyV1 already in use", "SET LOCAL lock_timeout" })
    Check(deployment.Contains(marker), "deployment guard: " + marker);
Check(!Regex.IsMatch(deployment, @"(?im)^\s*(DELETE|UPDATE|INSERT|TRUNCATE|CREATE TABLE|DROP TABLE)\b"), "no row or table DML/DDL");

// Interpret the bounded shape/rule subset offline. This is NOT a PostgreSQL engine.
// Extract predicates from the actual model SQL, so fixture checks exercise its
// keys, scalar regexes and variants, rather than a separate duplicated allow-list.
var contract = new OfflineContract(sql);
Check(contract.FieldRuleCount == 18, "all scalar predicates extracted");
Check(contract.ShapeCount == 9, "all variants extracted");
const string id = "11111111-1111-4111-8111-111111111111";
const string zero = "00000000-0000-0000-0000-000000000000";
JsonObject Fixture(string kind)
{
    var j = new JsonObject { ["v"] = 1, ["revision"] = 1, ["sequence"] = 1, ["operationId"] = id, ["kind"] = kind };
    switch (kind)
    {
        case "studio-option": j["studioId"] = id; j["rank"] = 1; break;
        case "package-option":
            j["sourceEventId"] = id; j["studioId"] = id; j["packageId"] = id; j["rank"] = 1;
            j["extraHours"] = 0; j["quotedPrice"] = "5000.00"; j["durationHours"] = "2"; break;
        case "schedule-option":
            j["sourceEventId"] = id; j["studioId"] = id; j["packageId"] = id; j["rank"] = 1;
            j["date"] = "2030-01-01"; j["startTime"] = "10:00:00"; j["endTime"] = "12:00:00"; break;
        case "completed": j["optionEventIds"] = new JsonArray(id); break;
        case "selected": j["sourceEventId"] = id; j["optionEventId"] = id; j["invalidatesFrom"] = "PackageRecommendation"; break;
        case "validated": j["sourceEventId"] = id; j["quotedPrice"] = "5000"; j["expiresAt"] = "2030-01-01T12:00:00Z"; break;
        case "failed": j["errorCode"] = "gemini_unavailable"; break;
        case "rewound": j["invalidatesFrom"] = "StudioMatching"; break;
    }
    return new JsonObject { ["journey"] = j };
}
var stages = new[] { "StudioMatching", "PackageRecommendation", "Scheduling", "Validation" };
var cases = new Dictionary<string, string[]> {
    ["started"] = stages, ["studio-option"] = stages[..1], ["package-option"] = stages[1..2],
    ["schedule-option"] = stages[2..3], ["completed"] = stages[..3], ["selected"] = stages[..3],
    ["validated"] = stages[3..], ["failed"] = stages, ["rewound"] = stages };
foreach (var (kind, validStages) in cases)
{
    foreach (var stage in stages)
    {
        var data = Fixture(kind);
        if (kind == "selected") data["journey"]!["invalidatesFrom"] = stages[Array.IndexOf(stages, stage) is var i && i < 3 ? i + 1 : 3];
        if (kind == "rewound") data["journey"]!["invalidatesFrom"] = stage;
        Check(contract.Accepts(data, stage, kind != "failed") == validStages.Contains(stage), kind + "/" + stage);
    }
    var valid = Fixture(kind);
    Check(!contract.Accepts(valid, validStages[0], kind == "failed"), kind + " wrong Success rejected");
    var j = (JsonObject)valid["journey"]!;
    foreach (var key in j.Select(x => x.Key).ToArray())
    {
        var missing = (JsonObject)valid.DeepClone(); ((JsonObject)missing["journey"]!).Remove(key);
        Check(!contract.Accepts(missing, validStages[0], kind != "failed"), kind + " missing " + key);
    }
}
foreach (var legacyJson in new string?[] { null, "{}", "{\"errorCode\":null}", "{\"proposalVersion\":1,\"attempt\":2}",
    "{\"errorCode\":{\"historical\":[1,2]}}", "{\"errorCode\":\"" + new string('x', 5000) + "\"}" })
    Check(contract.Accepts(legacyJson is null ? null : JsonNode.Parse(legacyJson), "Completed", true, "Legacy"), "legacy accepted unchanged");
foreach (var invalid in new[] { "[]", "123", "{\"unknown\":1}" })
    Check(!contract.Accepts(JsonNode.Parse(invalid), "Completed", true, "Legacy"), "legacy shape rejected");
Check(!contract.Accepts(null, "StudioMatching", true), "JourneyV1 SQL null rejected");
Check(!contract.Accepts(new JsonObject(), "StudioMatching", true), "missing journey rejected");
void RejectChange(string name, Action<JsonObject> change, string kind = "studio-option", string stage = "StudioMatching")
{
    var data = Fixture(kind); change((JsonObject)data["journey"]!);
    Check(!contract.Accepts(data, stage, kind != "failed"), name);
}
RejectChange("unknown key", j => j["raw"] = "private");
RejectChange("nested object", j => j["studioId"] = new JsonObject { ["id"] = id });
RejectChange("unknown kind", j => j["kind"] = "invented");
foreach (var field in new[] { "operationId", "studioId" })
    foreach (var bad in new[] { zero, "bad", id.ToUpperInvariant().Replace('1', 'A') + "x", id + "\n" })
        RejectChange(field + " malformed UUID", j => j[field] = bad);
foreach (var field in new[] { "sourceEventId", "packageId" })
    RejectChange(field + " zero UUID", j => j[field] = zero, "package-option", "PackageRecommendation");
RejectChange("optionEventId zero", j => j["optionEventId"] = zero, "selected");
RejectChange("oversized reason", j => j["reason"] = new string('x', 301));
RejectChange("null reason", j => j["reason"] = null);
RejectChange("empty reason", j => j["reason"] = "");
RejectChange("wrong version type", j => j["v"] = "1");
RejectChange("zero revision", j => j["revision"] = 0);
RejectChange("oversized sequence", j => j["sequence"] = 1000000000);
RejectChange("fractional rank", j => j["rank"] = 1.5);
RejectChange("wrong invalidation", j => j["invalidatesFrom"] = "Validation", "selected");
RejectChange("empty option IDs", j => j["optionEventIds"] = new JsonArray(), "completed");
RejectChange("six option IDs", j => j["optionEventIds"] = new JsonArray(Enumerable.Range(0, 6).Select(_ => JsonValue.Create(id) as JsonNode).ToArray()), "completed");
RejectChange("zero option ID", j => j["optionEventIds"] = new JsonArray(zero), "completed");
RejectChange("numeric option ID", j => j["optionEventIds"] = new JsonArray(1), "completed");
var boundary = Fixture("studio-option"); boundary["journey"]!["reason"] = new string('x', 300);
Check(contract.Accepts(boundary, stages[0], true), "300 character reason accepted");
var five = Fixture("completed"); five["journey"]!["optionEventIds"] = new JsonArray(Enumerable.Range(1, 5).Select(n => JsonValue.Create($"{n:D8}-1111-4111-8111-111111111111") as JsonNode).ToArray());
Check(contract.Accepts(five, stages[0], true), "five option IDs accepted");
// Test the byte guard independently: normal bounded variants are smaller than
// this cap. Do not pretend .NET serialization reproduces JSONB text bytes.
var large = Fixture("package-option"); large["journey"]!["reason"] = new string('\u0001', 300);
Check(!contract.Accepts(large, stages[1], true, jsonbTextBytes: 4097), "payload byte boundary rejected independently");
Check(contract.Accepts(Fixture("package-option"), stages[1], true, jsonbTextBytes: 4096), "payload byte boundary inclusive");
var outer = Fixture("started"); outer["extra"] = 1;
Check(!contract.Accepts(outer, stages[0], true), "unknown envelope key rejected");
Console.WriteLine($"PASS: {count} offline contract/model checks. No PostgreSQL connection or SQL execution.");

sealed class RejectConnections : DbConnectionInterceptor
{
    public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData eventData, InterceptionResult result)
        => throw new InvalidOperationException("Database access forbidden in offline checks.");
    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection, ConnectionEventData eventData,
        InterceptionResult result, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database access forbidden in offline checks.");
}

sealed class OfflineContract
{
    private readonly string sql;
    private readonly MatchCollection fields;
    private readonly MatchCollection shapes;
    private readonly int byteLimit;
    public int FieldRuleCount => fields.Count;
    public int ShapeCount => shapes.Count;
    public OfflineContract(string expression)
    {
        sql = expression;
        byteLimit = int.Parse(Regex.Match(sql, @"octet_length\(""DetailsJson""::text\) <= ([0-9]+)").Groups[1].Value);
        fields = Regex.Matches(sql, @"jsonb_typeof\(\(""DetailsJson""->'journey'\)->'([^']+)'\) = '([^']+)' AND \(\(""DetailsJson""->'journey'\)->>'[^']+'\) ~ '([^']+)'");
        shapes = Regex.Matches(sql, @"->>'kind' = '([^']+)' AND ""StepName"" = ANY \(ARRAY\[([^\]]*)\]::text\[\]\) AND .*? \?& ARRAY\[([^\]]*)\]::text\[\] AND .*? - ARRAY\[([^\]]*)\]::text\[\]\) = '\{\}'::jsonb");
    }
    private static string[] Keys(string s) => Regex.Matches(s, "'([^']+)'").Select(m => m.Groups[1].Value).ToArray();
    private static bool Matches(string value, string pattern) => Regex.IsMatch(value, pattern.Replace("$", "\\z").Replace("[[:space:]]", "\\s"));
    public bool Accepts(JsonNode? data, string stage, bool success, string eventType = "JourneyV1", int? jsonbTextBytes = null)
    {
        if (eventType != "JourneyV1") return data is null || data is JsonObject old && old.All(x => new[] { "proposalVersion", "errorCode", "attempt" }.Contains(x.Key));
        if (data is not JsonObject root || root.Count != 1 || root["journey"] is not JsonObject j) return false;
        // Explicit byte input tests the SQL size gate without claiming to emulate
        // PostgreSQL's JSONB text encoding/key order in .NET.
        if (jsonbTextBytes > byteLimit) return false;
        var kind = j["kind"]?.ToString();
        var shape = shapes.SingleOrDefault(m => m.Groups[1].Value == kind);
        if (shape is null || !Keys(shape.Groups[2].Value).Contains(stage)
            || Keys(shape.Groups[3].Value).Any(k => !j.ContainsKey(k))
            || j.Any(kv => !Keys(shape.Groups[4].Value).Contains(kv.Key))) return false;
        foreach (Match rule in fields)
        {
            var name = rule.Groups[1].Value;
            if (!j.ContainsKey(name)) continue;
            var value = j[name];
            var expected = rule.Groups[2].Value == "string" ? System.Text.Json.JsonValueKind.String : System.Text.Json.JsonValueKind.Number;
            if (value is null || value.GetValueKind() != expected || !Matches(value.ToString(), rule.Groups[3].Value)) return false;
        }
        foreach (var key in new[] { "operationId", "studioId", "packageId", "sourceEventId", "optionEventId" })
            if (j[key]?.ToString() == "00000000-0000-0000-0000-000000000000") return false;
        if (j.ContainsKey("reason") && (j["reason"] is not JsonValue r || !r.TryGetValue<string>(out var reason) || reason.EnumerateRunes().Count() is < 1 or > 300)) return false;
        if (j.ContainsKey("optionEventIds"))
        {
            var pattern = Regex.Match(sql, @"optionEventIds'\)::text ~ '([^']+)'").Groups[1].Value;
            if (pattern.Length == 0) throw new Exception("Option array SQL predicate not extracted");
            if (j["optionEventIds"] is not JsonArray ids || !Matches(ids.ToJsonString(), pattern) || ids.ToJsonString().Contains("00000000-0000-0000-0000-000000000000")) return false;
        }
        if ((kind == "failed") == success) return false;
        if (kind == "selected" && j["invalidatesFrom"]?.ToString() != (stage switch {
            "StudioMatching" => "PackageRecommendation", "PackageRecommendation" => "Scheduling", "Scheduling" => "Validation", _ => "" })) return false;
        if (kind == "rewound" && j["invalidatesFrom"]?.ToString() != stage) return false;
        return true;
    }
}
