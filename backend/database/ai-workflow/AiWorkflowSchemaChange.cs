using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.AiWorkflowReview;

// Dedicated review-only schema delta. No Up/Down execution or migration-history mutation.
// Compiled by the offline preparation tool, never by the API or archived migration chain.
public static class AiWorkflowSchemaChange
{
    public static IReadOnlyList<MigrationOperation> GetOperations(ApplicationDbContext target, ApplicationDbContext baseline)
    {
        var operations = target.GetService<IMigrationsModelDiffer>().GetDifferences(
            baseline.GetService<IDesignTimeModel>().Model.GetRelationalModel(),
            target.GetService<IDesignTimeModel>().Model.GetRelationalModel());
        var names = new[] { "AiWorkflows", "AiWorkflowEvents", "AiWorkflowApprovals" };
        if (!operations.OfType<CreateTableOperation>().Select(t => t.Name).Order().SequenceEqual(names.Order()) ||
            operations.Any(op => op switch {
                CreateTableOperation t => !names.Contains(t.Name) || t.Schema != "public",
                CreateIndexOperation i => !names.Contains(i.Table) || i.Schema != "public",
                EnsureSchemaOperation s => s.Name != "public",
                _ => true
            })) throw new InvalidOperationException("Schema change exceeds the three new AI tables/indexes.");
        return operations.Where(op => op is not EnsureSchemaOperation).ToList();
    }
}

public sealed class BeforeAiWorkflowContext(DbContextOptions<ApplicationDbContext> options) : ApplicationDbContext(options)
{
    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);
        builder.Ignore<AiWorkflowApproval>();
        builder.Ignore<AiWorkflowEvent>();
        builder.Ignore<AiWorkflow>();
    }
}
