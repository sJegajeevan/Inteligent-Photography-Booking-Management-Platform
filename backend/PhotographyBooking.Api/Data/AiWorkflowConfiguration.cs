using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Data;

public static class AiWorkflowConfiguration
{
    public static void Configure(ModelBuilder model)
    {
        model.Entity<AiWorkflow>(entity =>
        {
            entity.ToTable("AiWorkflows", "public", table =>
            {
                table.HasCheckConstraint("CK_AiWorkflows_Status", "\"Status\" IN ('Submitted','StudioMatching','PackageRecommendation','Scheduling','Validation','AwaitingApproval','Approved','Rejected','NeedsInput','Failed','Cancelled','Expired','RevalidationRequired')");
                table.HasCheckConstraint("CK_AiWorkflows_Step", "\"CurrentStep\" IN ('Submitted','StudioMatching','PackageRecommendation','Scheduling','Validation','HumanApproval','Completed')");
                table.HasCheckConstraint("CK_AiWorkflows_Requirements", "jsonb_typeof(\"NormalizedRequirementsJson\") = 'object'");
                table.HasCheckConstraint("CK_AiWorkflows_Proposal", "(\"FinalProposalJson\" IS NULL AND \"ProposalVersion\" = 0) OR (\"FinalProposalJson\" IS NOT NULL AND jsonb_typeof(\"FinalProposalJson\") = 'object' AND \"ProposalVersion\" > 0 AND \"SelectedStudioId\" IS NOT NULL AND \"SelectedPackageId\" IS NOT NULL)");
                table.HasCheckConstraint("CK_AiWorkflows_ApprovalReady", "\"Status\" NOT IN ('AwaitingApproval','Approved','Rejected') OR \"FinalProposalJson\" IS NOT NULL");
                table.HasCheckConstraint("CK_AiWorkflows_PackageStudio", "\"SelectedPackageId\" IS NULL OR \"SelectedStudioId\" IS NOT NULL");
                table.HasCheckConstraint("CK_AiWorkflows_Timestamps", "\"UpdatedAt\" >= \"CreatedAt\" AND \"ExpiresAt\" > \"CreatedAt\"");
            });
            entity.HasKey(w => w.Id);
            entity.Property(w => w.Status).HasConversion<string>().HasMaxLength(32);
            entity.Property(w => w.CurrentStep).HasMaxLength(32).IsRequired();
            entity.Property(w => w.NormalizedRequirementsJson).HasColumnType("jsonb").IsRequired();
            entity.Property(w => w.FinalProposalJson).HasColumnType("jsonb");
            entity.Property(w => w.RowVersion).IsRowVersion();
            entity.HasOne(w => w.Customer).WithMany().HasForeignKey(w => w.CustomerId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(w => w.SelectedStudio).WithMany().HasForeignKey(w => w.SelectedStudioId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(w => w.SelectedPackage).WithMany().HasForeignKey(w => w.SelectedPackageId).OnDelete(DeleteBehavior.Restrict);
            entity.HasIndex(w => new { w.CustomerId, w.CreatedAt });
            entity.HasIndex(w => new { w.Status, w.ExpiresAt });
            entity.HasIndex(w => new { w.SelectedStudioId, w.Status, w.UpdatedAt });
        });
        model.Entity<AiWorkflowEvent>(entity =>
        {
            entity.ToTable("AiWorkflowEvents", "public", table =>
            {
                table.HasCheckConstraint("CK_AiWorkflowEvents_Duration", "\"DurationMs\" IS NULL OR \"DurationMs\" >= 0");
                table.HasCheckConstraint("CK_AiWorkflowEvents_Details", "\"DetailsJson\" IS NULL OR (jsonb_typeof(\"DetailsJson\") = 'object' AND (\"DetailsJson\" - ARRAY['proposalVersion','errorCode','attempt']::text[]) = '{}'::jsonb)");
            });
            entity.HasKey(e => e.Id);
            entity.Property(e => e.EventType).HasMaxLength(64).IsRequired();
            entity.Property(e => e.StepName).HasMaxLength(64).IsRequired();
            entity.Property(e => e.Summary).HasMaxLength(500).IsRequired();
            entity.Property(e => e.DetailsJson).HasColumnType("jsonb");
            entity.HasOne(e => e.Workflow).WithMany(w => w.Events).HasForeignKey(e => e.WorkflowId).OnDelete(DeleteBehavior.Restrict);
            entity.HasIndex(e => new { e.WorkflowId, e.CreatedAt, e.Id });
        });
        model.Entity<AiWorkflowApproval>(entity =>
        {
            entity.ToTable("AiWorkflowApprovals", "public", table =>
            {
                table.HasCheckConstraint("CK_AiWorkflowApprovals_Version", "\"ProposalVersion\" > 0");
                table.HasCheckConstraint("CK_AiWorkflowApprovals_Decision", "\"Decision\" IN ('Approved','Rejected','RevisionRequested')");
                table.HasCheckConstraint("CK_AiWorkflowApprovals_Snapshot", "jsonb_typeof(\"ProposalSnapshotJson\") = 'object'");
            });
            entity.HasKey(a => a.Id);
            entity.Property(a => a.Decision).HasConversion<string>().HasMaxLength(32);
            entity.Property(a => a.Reason).HasMaxLength(1000);
            entity.Property(a => a.ProposalSnapshotJson).HasColumnType("jsonb").IsRequired();
            entity.HasOne(a => a.Workflow).WithMany(w => w.Approvals).HasForeignKey(a => a.WorkflowId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(a => a.Reviewer).WithMany().HasForeignKey(a => a.ReviewerUserId).OnDelete(DeleteBehavior.Restrict);
            entity.HasIndex(a => new { a.WorkflowId, a.ProposalVersion }).IsUnique();
            entity.HasIndex(a => new { a.ReviewerUserId, a.CreatedAt });
        });
    }
}
