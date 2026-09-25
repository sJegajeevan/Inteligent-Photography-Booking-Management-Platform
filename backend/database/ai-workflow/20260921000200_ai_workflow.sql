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
CREATE TABLE public."AiWorkflows" (
    "Id" uuid NOT NULL,
    "CustomerId" integer NOT NULL,
    "Status" character varying(32) NOT NULL,
    "NormalizedRequirementsJson" jsonb NOT NULL,
    "CurrentStep" character varying(32) NOT NULL,
    "FinalProposalJson" jsonb,
    "ProposalVersion" integer NOT NULL,
    "SelectedStudioId" uuid,
    "SelectedPackageId" uuid,
    "CreatedAt" timestamp with time zone NOT NULL,
    "UpdatedAt" timestamp with time zone NOT NULL,
    "ExpiresAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_AiWorkflows" PRIMARY KEY ("Id"),
    CONSTRAINT "CK_AiWorkflows_ApprovalReady" CHECK ("Status" NOT IN ('AwaitingApproval','Approved','Rejected') OR "FinalProposalJson" IS NOT NULL),
    CONSTRAINT "CK_AiWorkflows_PackageStudio" CHECK ("SelectedPackageId" IS NULL OR "SelectedStudioId" IS NOT NULL),
    CONSTRAINT "CK_AiWorkflows_Proposal" CHECK (("FinalProposalJson" IS NULL AND "ProposalVersion" = 0) OR ("FinalProposalJson" IS NOT NULL AND jsonb_typeof("FinalProposalJson") = 'object' AND "ProposalVersion" > 0 AND "SelectedStudioId" IS NOT NULL AND "SelectedPackageId" IS NOT NULL)),
    CONSTRAINT "CK_AiWorkflows_Requirements" CHECK (jsonb_typeof("NormalizedRequirementsJson") = 'object'),
    CONSTRAINT "CK_AiWorkflows_Status" CHECK ("Status" IN ('Submitted','StudioMatching','PackageRecommendation','Scheduling','Validation','AwaitingApproval','Approved','Rejected','NeedsInput','Failed','Cancelled','Expired','RevalidationRequired')),
    CONSTRAINT "CK_AiWorkflows_Step" CHECK ("CurrentStep" IN ('Submitted','StudioMatching','PackageRecommendation','Scheduling','Validation','HumanApproval','Completed')),
    CONSTRAINT "CK_AiWorkflows_Timestamps" CHECK ("UpdatedAt" >= "CreatedAt" AND "ExpiresAt" > "CreatedAt"),
    CONSTRAINT "FK_AiWorkflows_PhotographyPackages_SelectedPackageId" FOREIGN KEY ("SelectedPackageId") REFERENCES "PhotographyPackages" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_AiWorkflows_Studios_SelectedStudioId" FOREIGN KEY ("SelectedStudioId") REFERENCES "Studios" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_AiWorkflows_Users_CustomerId" FOREIGN KEY ("CustomerId") REFERENCES "Users" ("Id") ON DELETE RESTRICT
);

CREATE TABLE public."AiWorkflowApprovals" (
    "Id" uuid NOT NULL,
    "WorkflowId" uuid NOT NULL,
    "ProposalVersion" integer NOT NULL,
    "ReviewerUserId" integer NOT NULL,
    "Decision" character varying(32) NOT NULL,
    "ProposalSnapshotJson" jsonb NOT NULL,
    "Reason" character varying(1000),
    "CreatedAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_AiWorkflowApprovals" PRIMARY KEY ("Id"),
    CONSTRAINT "CK_AiWorkflowApprovals_Decision" CHECK ("Decision" IN ('Approved','Rejected','RevisionRequested')),
    CONSTRAINT "CK_AiWorkflowApprovals_Snapshot" CHECK (jsonb_typeof("ProposalSnapshotJson") = 'object'),
    CONSTRAINT "CK_AiWorkflowApprovals_Version" CHECK ("ProposalVersion" > 0),
    CONSTRAINT "FK_AiWorkflowApprovals_AiWorkflows_WorkflowId" FOREIGN KEY ("WorkflowId") REFERENCES public."AiWorkflows" ("Id") ON DELETE RESTRICT,
    CONSTRAINT "FK_AiWorkflowApprovals_Users_ReviewerUserId" FOREIGN KEY ("ReviewerUserId") REFERENCES "Users" ("Id") ON DELETE RESTRICT
);

CREATE TABLE public."AiWorkflowEvents" (
    "Id" uuid NOT NULL,
    "WorkflowId" uuid NOT NULL,
    "EventType" character varying(64) NOT NULL,
    "StepName" character varying(64) NOT NULL,
    "Summary" character varying(500) NOT NULL,
    "DetailsJson" jsonb,
    "Success" boolean NOT NULL,
    "DurationMs" bigint,
    "CreatedAt" timestamp with time zone NOT NULL,
    CONSTRAINT "PK_AiWorkflowEvents" PRIMARY KEY ("Id"),
    CONSTRAINT "CK_AiWorkflowEvents_Details" CHECK ("DetailsJson" IS NULL OR (jsonb_typeof("DetailsJson") = 'object' AND ("DetailsJson" - ARRAY['proposalVersion','errorCode','attempt']::text[]) = '{}'::jsonb)),
    CONSTRAINT "CK_AiWorkflowEvents_Duration" CHECK ("DurationMs" IS NULL OR "DurationMs" >= 0),
    CONSTRAINT "FK_AiWorkflowEvents_AiWorkflows_WorkflowId" FOREIGN KEY ("WorkflowId") REFERENCES public."AiWorkflows" ("Id") ON DELETE RESTRICT
);

CREATE INDEX "IX_AiWorkflowApprovals_ReviewerUserId_CreatedAt" ON public."AiWorkflowApprovals" ("ReviewerUserId", "CreatedAt");

CREATE UNIQUE INDEX "IX_AiWorkflowApprovals_WorkflowId_ProposalVersion" ON public."AiWorkflowApprovals" ("WorkflowId", "ProposalVersion");

CREATE INDEX "IX_AiWorkflowEvents_WorkflowId_CreatedAt_Id" ON public."AiWorkflowEvents" ("WorkflowId", "CreatedAt", "Id");

CREATE INDEX "IX_AiWorkflows_CustomerId_CreatedAt" ON public."AiWorkflows" ("CustomerId", "CreatedAt");

CREATE INDEX "IX_AiWorkflows_SelectedPackageId" ON public."AiWorkflows" ("SelectedPackageId");

CREATE INDEX "IX_AiWorkflows_SelectedStudioId_Status_UpdatedAt" ON public."AiWorkflows" ("SelectedStudioId", "Status", "UpdatedAt");

CREATE INDEX "IX_AiWorkflows_Status_ExpiresAt" ON public."AiWorkflows" ("Status", "ExpiresAt");
COMMIT;
