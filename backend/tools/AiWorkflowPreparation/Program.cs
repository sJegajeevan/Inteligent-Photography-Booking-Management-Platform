using System.Data.Common;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using PhotographyBooking.Api.AiWorkflowReview;
using PhotographyBooking.Api.Contracts.AgenticAi;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;
using PhotographyBooking.Api.Services;

// No API startup, configuration/secrets loading, connection string or apply mode.
if (args.Length != 2 || args[0] is not ("--generate" or "--verify"))
{
    Console.Error.WriteLine("Usage: --generate|--verify <SQL-file>");
    return 2;
}
var options = new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql()
    .AddInterceptors(new RejectConnections()).Options;
using var target = new ApplicationDbContext(options);
using var baseline = new BeforeAiWorkflowContext(options);
var count = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException(name);
    count++;
}
Check(target.GetService<IMigrationsAssembly>().Migrations.Count == 0, "Archived migrations must remain excluded.");
var operations = AiWorkflowSchemaChange.GetOperations(target, baseline);
var tables = operations.OfType<CreateTableOperation>().ToList();
Check(tables.Count == 3, "Exactly three new tables.");
Check(!tables.SelectMany(t => t.Columns).Any(c => c.Name == "RowVersion"), "No application RowVersion column.");
Check(!tables.SelectMany(t => t.ForeignKeys).Any(fk => fk.PrincipalTable == "Bookings"), "No booking relationship.");
Check(tables.SelectMany(t => t.ForeignKeys).All(fk => fk.OnDelete == ReferentialAction.Restrict), "Audit/ownership deletion must be restricted.");
var model = target.GetService<IDesignTimeModel>().Model;
var workflow = model.FindEntityType(typeof(AiWorkflow))!;
var approval = model.FindEntityType(typeof(AiWorkflowApproval))!;
var audit = model.FindEntityType(typeof(AiWorkflowEvent))!;
Check(workflow.FindProperty(nameof(AiWorkflow.RowVersion))!.IsConcurrencyToken, "Optimistic concurrency required.");
Check(workflow.FindProperty(nameof(AiWorkflow.RowVersion))!.GetColumnName() == "xmin", "Npgsql xmin mapping required.");
Check(workflow.FindProperty(nameof(AiWorkflow.CustomerId))!.IsNullable == false, "Customer ownership required.");
Check(approval.GetIndexes().Any(i => i.IsUnique && i.Properties.Select(p => p.Name).SequenceEqual(new[] { "WorkflowId", "ProposalVersion" })), "One decision per proposal version.");
foreach (var pair in new[] { (workflow, "NormalizedRequirementsJson"), (workflow, "FinalProposalJson"), (approval, "ProposalSnapshotJson"), (audit, "DetailsJson") })
    Check(pair.Item1.FindProperty(pair.Item2)!.GetColumnType() == "jsonb", "JSONB mapping required.");
Check(audit.GetCheckConstraints().Any(c => c.Name == "CK_AiWorkflowEvents_Details" && c.Sql.Contains("errorCode")), "Audit details allow-list required.");
foreach (var status in Enum.GetNames<AiWorkflowStatus>())
    Check(workflow.GetCheckConstraints().Single(c => c.Name == "CK_AiWorkflows_Status").Sql.Contains($"'{status}'"), "Status missing from database constraint.");
foreach (var decision in Enum.GetNames<AiApprovalDecision>())
    Check(approval.GetCheckConstraints().Single(c => c.Name == "CK_AiWorkflowApprovals_Decision").Sql.Contains($"'{decision}'"), "Decision missing from database constraint.");

var now = new DateTime(2026, 9, 21, 12, 0, 0, DateTimeKind.Utc);
var state = new AiWorkflow { Status = AiWorkflowStatus.AwaitingApproval, ProposalVersion = 2,
    FinalProposalJson = "{\"version\":2}", SelectedStudioId = Guid.NewGuid(), SelectedPackageId = Guid.NewGuid(), ExpiresAt = now.AddHours(1) };
foreach (var decision in Enum.GetValues<AiApprovalDecision>())
    Check(AiWorkflowApprovalRules.Validate(state, 2, decision, "Reviewed", now) is null, "Valid human decision.");
Check(AiWorkflowApprovalRules.Validate(state, 1, AiApprovalDecision.Approved, null, now) == "StaleProposal", "Stale approval rejected.");
Check(AiWorkflowApprovalRules.Validate(state, 0, AiApprovalDecision.Approved, null, now) == "StaleProposal", "Version zero rejected.");
Check(AiWorkflowApprovalRules.Validate(state, 2, (AiApprovalDecision)99, null, now) == "InvalidDecision", "Invalid enum rejected.");
Check(AiWorkflowApprovalRules.Validate(state, 2, AiApprovalDecision.Rejected, null, now) == "ReasonRequired", "Rejection reason required.");
Check(AiWorkflowApprovalRules.Validate(state, 2, AiApprovalDecision.Approved, new string('x', 1001), now) == "ReasonTooLong", "Reason bounded.");
Check(AiWorkflowApprovalRules.Validate(state, 2, AiApprovalDecision.Approved, null, state.ExpiresAt) == "Expired", "Expiration boundary.");
state.Status = AiWorkflowStatus.Approved;
Check(AiWorkflowApprovalRules.Validate(state, 2, AiApprovalDecision.Approved, null, now) == "NotAwaitingApproval", "Repeat decision rejected.");
state.Status = AiWorkflowStatus.AwaitingApproval; state.FinalProposalJson = null;
Check(AiWorkflowApprovalRules.Validate(state, 2, AiApprovalDecision.Approved, null, now) == "IncompleteProposal", "Incomplete proposal rejected.");
Check(AiWorkflowApprovalRules.ResultingStatus(AiApprovalDecision.RevisionRequested) == AiWorkflowStatus.RevalidationRequired, "Revision requests revalidate.");
var requirements = new CustomerPhotographyRequirements { PhotographyType = "Portrait", Location = "Colombo", MaximumBudget = 10000,
    EarliestDate = new(2026, 10, 1), LatestDate = new(2026, 10, 2), CoverageHours = 2 };
var serialized = JsonSerializer.Serialize(requirements, new JsonSerializerOptions(JsonSerializerDefaults.Web));
Check(JsonSerializer.Deserialize<CustomerPhotographyRequirements>(serialized, new JsonSerializerOptions(JsonSerializerDefaults.Web))?.PhotographyType == "Portrait", "Phase 1 requirements roundtrip.");

void ExpectGuardFailure(Action arrange, string message)
{
    target.ChangeTracker.Clear();
    arrange();
    var rejected = false;
    try { AiWorkflowPersistenceGuard.Validate(target.ChangeTracker); }
    catch (InvalidOperationException) { rejected = true; }
    Check(rejected, message);
    target.ChangeTracker.Clear();
}
AiWorkflow AttachWorkflow()
{
    var value = new AiWorkflow { CustomerId = 1, ProposalVersion = 1, FinalProposalJson = "{\"version\":1}",
        NormalizedRequirementsJson = serialized, Status = AiWorkflowStatus.AwaitingApproval, ExpiresAt = now.AddDays(1) };
    target.Attach(value);
    return value;
}
ExpectGuardFailure(() => { var w = AttachWorkflow(); w.CustomerId = 2; }, "Ownership immutable.");
ExpectGuardFailure(() => { var w = AttachWorkflow(); w.ProposalVersion = 0; }, "Version rollback blocked.");
ExpectGuardFailure(() => { var w = AttachWorkflow(); w.FinalProposalJson = "{\"version\":1,\"changed\":true}"; }, "Same-version proposal mutation blocked.");
ExpectGuardFailure(() => { var w = AttachWorkflow(); w.SelectedStudioId = Guid.NewGuid(); }, "Same-version selection mutation blocked.");
ExpectGuardFailure(() => { var w = AttachWorkflow(); w.ProposalVersion = 2; w.FinalProposalJson = "{\"version\":2}"; w.Status = AiWorkflowStatus.Approved; }, "Approval invalidated by revision.");
ExpectGuardFailure(() => { var e = new AiWorkflowEvent { Summary = "Started" }; target.Attach(e); e.Summary = "Rewritten"; }, "Audit update blocked.");
ExpectGuardFailure(() => { var a = new AiWorkflowApproval(); target.Attach(a); target.Remove(a); }, "Approval deletion blocked.");
var revised = AttachWorkflow(); revised.ProposalVersion = 2; revised.FinalProposalJson = "{\"version\":2}"; revised.Status = AiWorkflowStatus.RevalidationRequired;
AiWorkflowPersistenceGuard.Validate(target.ChangeTracker);
Check(true, "New revision can revalidate."); target.ChangeTracker.Clear();
Check(await new AiWorkflowApprovalService(target, null!, TimeProvider.System).RecordAsync(Guid.NewGuid(), 1, AiApprovalDecision.Approved,
    null, new System.Security.Claims.ClaimsPrincipal()) == "Forbidden", "Unauthenticated approval rejected before database access.");

var header = """
-- PREPARED ONLY. Requires explicit database deployment approval. Do not run the historical EF chain.
-- Generated offline from AiWorkflowSchemaChange.cs and the EF model; no migration history edits.
BEGIN;
SET LOCAL search_path = public, pg_catalog;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $preflight$
DECLARE item record;
BEGIN
  FOR item IN SELECT * FROM (VALUES ('Users','integer'), ('Studios','uuid'), ('PhotographyPackages','uuid')) AS expected(name, id_type)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname=item.name AND c.relkind='r') THEN
      RAISE EXCEPTION 'Missing expected ordinary table: %', item.name;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
      AND table_name=item.name AND column_name='Id' AND data_type=item.id_type AND is_nullable='NO') THEN
      RAISE EXCEPTION 'Unexpected Id column definition: %', item.name;
    END IF;
  END LOOP;
  IF to_regclass('public."AiWorkflows"') IS NOT NULL OR to_regclass('public."AiWorkflowEvents"') IS NOT NULL
     OR to_regclass('public."AiWorkflowApprovals"') IS NOT NULL THEN
    RAISE EXCEPTION 'AI schema objects already exist; stop for reconciliation, do not reapply';
  END IF;
END;
$preflight$;
""";
var commands = target.GetService<IMigrationsSqlGenerator>().Generate(operations, model);
var sql = (header + "\n" + string.Join("\n", commands.Select(c => c.CommandText)) + "COMMIT;\n").Replace("\r\n", "\n");
Check(!sql.Contains("ALTER TABLE") && !sql.Contains("__EFMigrationsHistory") && !sql.Contains("DROP TABLE"), "Only additive table/index SQL permitted.");
Check(!sql.Contains("xmin xid"), "Npgsql must omit the xmin system column from table creation.");
if (args[0] == "--generate") File.WriteAllText(args[1], sql, new UTF8Encoding(false));
else Check(File.ReadAllText(args[1]).Replace("\r\n", "\n") == sql, "SQL drift: regenerate and review.");
Console.WriteLine($"PASS: {count} offline/model checks; three-table SQL {(args[0] == "--generate" ? "prepared" : "verified")}. No database access or migration execution.");
return 0;

sealed class RejectConnections : DbConnectionInterceptor
{
    public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData eventData, InterceptionResult result)
        => throw new InvalidOperationException("Database access is forbidden in offline preparation.");
    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection, ConnectionEventData eventData,
        InterceptionResult result, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database access is forbidden in offline preparation.");
}
