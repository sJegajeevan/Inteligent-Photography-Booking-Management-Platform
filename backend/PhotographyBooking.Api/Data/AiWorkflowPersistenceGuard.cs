using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Data;

/// <summary>Protects normal EF writes. Administrative SQL/bulk writes must not bypass this policy.</summary>
public static class AiWorkflowPersistenceGuard
{
    public static void Validate(ChangeTracker tracker)
    {
        tracker.DetectChanges();
        foreach (var entry in tracker.Entries())
        {
            if (entry.Entity is AiWorkflowEvent or AiWorkflowApproval &&
                entry.State is EntityState.Modified or EntityState.Deleted)
                throw new InvalidOperationException("AI audit events and approval decisions are append-only.");
            if (entry.Entity is not AiWorkflow || entry.State != EntityState.Modified) continue;
            if (entry.Property(nameof(AiWorkflow.CustomerId)).IsModified)
                throw new InvalidOperationException("Workflow ownership cannot change.");
            var version = entry.Property(nameof(AiWorkflow.ProposalVersion));
            var previous = (int)version.OriginalValue!;
            var current = (int)version.CurrentValue!;
            if (current < previous)
                throw new InvalidOperationException("Proposal versions cannot decrease.");
            var proposalChanged = entry.Property(nameof(AiWorkflow.FinalProposalJson)).IsModified ||
                entry.Property(nameof(AiWorkflow.SelectedStudioId)).IsModified ||
                entry.Property(nameof(AiWorkflow.SelectedPackageId)).IsModified ||
                entry.Property(nameof(AiWorkflow.NormalizedRequirementsJson)).IsModified;
            if (previous > 0 && proposalChanged && current <= previous)
                throw new InvalidOperationException("Revising a published proposal requires a new version.");
            if (previous > 0 && proposalChanged &&
                ((AiWorkflow)entry.Entity).Status is AiWorkflowStatus.Approved or AiWorkflowStatus.Rejected)
                throw new InvalidOperationException("A revised proposal must be revalidated and approved again.");
        }
    }
}
