using System.Data.Common;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using PhotographyBooking.Api.Data;

// Offline SQL generation only. Does not load API configuration or start its host.
// No apply command exists; a connection interceptor also prevents database access.
if (args.Length != 2 || args[0] is not ("--generate" or "--verify"))
{
    Console.Error.WriteLine("Usage: SchemaReconciliation --generate|--verify <artifact-directory>");
    return 2;
}

var options = new DbContextOptionsBuilder<ApplicationDbContext>()
    .UseNpgsql()
    .AddInterceptors(new RejectConnections())
    .Options;
using var db = new ApplicationDbContext(options);
if (db.GetService<IMigrationsAssembly>().Migrations.Count != 0)
    throw new InvalidOperationException("Legacy migrations must be excluded from the API assembly.");

var model = db.GetService<IDesignTimeModel>().Model;
var allOperations = db.GetService<IMigrationsModelDiffer>()
    .GetDifferences(null, model.GetRelationalModel());
var allTables = allOperations.OfType<CreateTableOperation>().ToArray();
var allIndexes = allOperations.OfType<CreateIndexOperation>().ToArray();
var existingTables = new HashSet<string>(StringComparer.Ordinal)
{
    "Users", "Studios", "StudioPortfolios", "StudioPortfolioImages", "StudioServices",
    "StudioAvailabilities", "PhotographyPackages", "PhotographyPackageServices", "PackageAddons"
};
var missingTables = new HashSet<string>(StringComparer.Ordinal)
{
    "Bookings", "BookingLocations", "BookingStatusHistories", "Reviews", "Notifications"
};
var missingUserColumns = new HashSet<string>(StringComparer.Ordinal) { "PhoneNumber", "ProfilePhotoUrl" };
if (!allTables.Select(t => t.Name).ToHashSet().SetEquals(existingTables.Concat(missingTables)) ||
    allOperations.Any(o => o is not (CreateTableOperation or CreateIndexOperation)))
    throw new InvalidOperationException("Model table/operation scope changed; review reconciliation manually.");

var users = allTables.Single(t => t.Name == "Users");
var additions = users.Columns.Where(c => missingUserColumns.Contains(c.Name)).ToArray();
if (additions.Length != 2 || additions.Any(c => !c.IsNullable || c.DefaultValue != null || c.DefaultValueSql != null) ||
    additions.Single(c => c.Name == "PhoneNumber").ColumnType != "character varying(30)" ||
    additions.Single(c => c.Name == "ProfilePhotoUrl").ColumnType != "character varying(2048)")
    throw new InvalidOperationException("User column scope changed; review reconciliation manually.");
var bookings = allTables.Single(t => t.Name == "Bookings");
foreach (var (name, type) in new[] { ("CustomerId", "integer"), ("StudioId", "uuid"), ("PackageId", "uuid"), ("PricingSnapshotJson", "jsonb") })
    if (bookings.Columns.Single(c => c.Name == name).ColumnType != type)
        throw new InvalidOperationException($"Unexpected booking type: {name}");
if (!bookings.Columns.Single(c => c.Name == "PricingSnapshotJson").IsNullable)
    throw new InvalidOperationException("PricingSnapshotJson must remain nullable.");

var packageLink = allTables.Single(t => t.Name == "PhotographyPackageServices");
var packageFk = packageLink.ForeignKeys.Single(f => f.PrincipalTable == "PhotographyPackages");
if (!packageFk.Columns.SequenceEqual(new[] { "PhotographyPackageId" }) ||
    !packageFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    packageFk.OnDelete != ReferentialAction.Cascade || packageFk.OnUpdate != ReferentialAction.NoAction ||
    packageFk.Name != "FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~")
    throw new InvalidOperationException("Approved missing package FK scope changed; review manually.");

var serviceFk = packageLink.ForeignKeys.Single(f => f.PrincipalTable == "StudioServices");
if (!serviceFk.Columns.SequenceEqual(new[] { "StudioServiceId" }) ||
    !serviceFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    serviceFk.OnDelete != ReferentialAction.Cascade || serviceFk.OnUpdate != ReferentialAction.NoAction ||
    serviceFk.Name != "FK_PhotographyPackageServices_StudioServices_StudioServiceId")
    throw new InvalidOperationException("Approved missing service FK scope changed; review manually.");
var photographyPackages = allTables.Single(t => t.Name == "PhotographyPackages");
var studioFk = photographyPackages.ForeignKeys.Single(f => f.PrincipalTable == "Studios");
if (!studioFk.Columns.SequenceEqual(new[] { "StudioId" }) ||
    !studioFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    studioFk.OnDelete != ReferentialAction.Cascade || studioFk.OnUpdate != ReferentialAction.NoAction ||
    studioFk.Name != "FK_PhotographyPackages_Studios_StudioId")
    throw new InvalidOperationException("Approved missing package-studio FK scope changed; review manually.");
var availabilities = allTables.Single(t => t.Name == "StudioAvailabilities");
var availabilityFk = availabilities.ForeignKeys.Single(f => f.PrincipalTable == "Studios");
if (!availabilityFk.Columns.SequenceEqual(new[] { "StudioId" }) ||
    !availabilityFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    availabilityFk.OnDelete != ReferentialAction.Cascade || availabilityFk.OnUpdate != ReferentialAction.NoAction ||
    availabilityFk.Name != "FK_StudioAvailabilities_Studios_StudioId")
    throw new InvalidOperationException("Approved availability-studio FK scope changed; review manually.");
var portfolios = allTables.Single(t => t.Name == "StudioPortfolios");
var portfolioFk = portfolios.ForeignKeys.Single(f => f.PrincipalTable == "Studios");
if (!portfolioFk.Columns.SequenceEqual(new[] { "StudioId" }) ||
    !portfolioFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    portfolioFk.OnDelete != ReferentialAction.Cascade || portfolioFk.OnUpdate != ReferentialAction.NoAction ||
    portfolioFk.Name != "FK_StudioPortfolios_Studios_StudioId")
    throw new InvalidOperationException("Approved portfolio-studio FK scope changed; review manually.");
var studioServices = allTables.Single(t => t.Name == "StudioServices");
var serviceOwnerFk = studioServices.ForeignKeys.Single(f => f.PrincipalTable == "Studios");
if (!serviceOwnerFk.Columns.SequenceEqual(new[] { "StudioId" }) ||
    !serviceOwnerFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    serviceOwnerFk.OnDelete != ReferentialAction.Cascade || serviceOwnerFk.OnUpdate != ReferentialAction.NoAction ||
    serviceOwnerFk.Name != "FK_StudioServices_Studios_StudioId")
    throw new InvalidOperationException("Approved serviceOwner-studio FK scope changed; review manually.");
foreach (var fk in new[] { packageFk, serviceFk, studioFk, availabilityFk, portfolioFk, serviceOwnerFk })
{
    var principal = allTables.Single(t => t.Name == fk.PrincipalTable);
    var dependent = ReferenceEquals(fk, serviceOwnerFk) ? studioServices :
        ReferenceEquals(fk, portfolioFk) ? portfolios :
        ReferenceEquals(fk, availabilityFk) ? availabilities :
        ReferenceEquals(fk, studioFk) ? photographyPackages : packageLink;
    var dependentColumn = dependent.Columns.Single(c => c.Name == fk.Columns.Single());
    var principalColumn = principal.Columns.Single(c => c.Name == "Id");
    if (dependentColumn.ColumnType != "uuid" || dependentColumn.IsNullable ||
        principalColumn.ColumnType != "uuid" || principalColumn.IsNullable ||
        !principal.PrimaryKey!.Columns.SequenceEqual(new[] { "Id" }))
        throw new InvalidOperationException("Approved FK UUID/nullability/primary-key scope changed.");
}

var studios = allTables.Single(t => t.Name == "Studios");
var ownershipFk = studios.ForeignKeys.Single(f => f.PrincipalTable == "Users");
var ownershipIndex = allIndexes.Single(i => i.Table == "Studios" && i.Name == "IX_Studios_UserId");
if (ownershipFk.Name != "FK_Studios_Users_UserId" ||
    !ownershipFk.Columns.SequenceEqual(new[] { "UserId" }) ||
    !ownershipFk.PrincipalColumns!.SequenceEqual(new[] { "Id" }) ||
    ownershipFk.OnDelete != ReferentialAction.Cascade || ownershipFk.OnUpdate != ReferentialAction.NoAction ||
    studios.Columns.Single(c => c.Name == "UserId").ColumnType != "integer" ||
    studios.Columns.Single(c => c.Name == "UserId").IsNullable ||
    users.Columns.Single(c => c.Name == "Id").ColumnType != "integer" ||
    users.Columns.Single(c => c.Name == "Id").IsNullable ||
    !users.PrimaryKey!.Columns.SequenceEqual(new[] { "Id" }) ||
    !ownershipIndex.Columns.SequenceEqual(new[] { "UserId" }) || !ownershipIndex.IsUnique ||
    ownershipIndex.Filter != null || ownershipIndex.IsDescending?.Any(d => d) == true)
    throw new InvalidOperationException("Approved ownership relationship/index scope changed.");

var serviceIndex = allIndexes.Single(i => i.Table == "PhotographyPackageServices" &&
    i.Name == "IX_PhotographyPackageServices_StudioServiceId");
if (!serviceIndex.Columns.SequenceEqual(new[] { "StudioServiceId" }) || serviceIndex.IsUnique ||
    serviceIndex.Filter != null || serviceIndex.IsDescending?.Any(d => d) == true)
    throw new InvalidOperationException("Approved missing service index scope changed; review manually.");

// Strict rerun validation is limited to generated target tables/additions.
string IdentityCode(AddColumnOperation column) => column["Npgsql:ValueGenerationStrategy"]?.ToString() switch
{
    "IdentityByDefaultColumn" => "d", "IdentityAlwaysColumn" => "a",
    null or "None" => "", _ => throw new InvalidOperationException("Unreviewed identity strategy.")
};
foreach (var column in allTables.Where(t => missingTables.Contains(t.Name)).SelectMany(t => t.Columns).Concat(additions))
    if (column.DefaultValue != null || column.DefaultValueSql != null || column.ComputedColumnSql != null)
        throw new InvalidOperationException("Target default/generated expression scope changed; review validator.");
foreach (var check in allTables.Where(t => missingTables.Contains(t.Name)).SelectMany(t => t.CheckConstraints))
    if (check.Name != "CK_Reviews_Rating" || check.Sql != "\"Rating\" BETWEEN 1 AND 5")
        throw new InvalidOperationException("Target check expression scope changed; review catalog expression.");

// The manifest covers the ENTIRE current model, not the stale migration snapshot.
var manifest = JsonSerializer.Serialize(new
{
    schema = "public",
    preservedHistory = "202609020001_AddPortfolioImages",
    tables = allTables.OrderBy(t => t.Name, StringComparer.Ordinal).Select(t => new
    {
        name = t.Name,
        create = missingTables.Contains(t.Name),
        columns = t.Columns.Select(c => new
        {
            name = c.Name, type = c.ColumnType, nullable = c.IsNullable,
            identity = IdentityCode(c), generated = "", defaultSql = c.DefaultValueSql,
            add = t.Name == "Users" && missingUserColumns.Contains(c.Name),
            reconcileNotNull = (t.Name == "StudioAvailabilities" || t.Name == "StudioPortfolios" || t.Name == "StudioServices") && c.Name == "StudioId" || (t.Name == "Studios" && c.Name == "UserId")
        }),
        keys = new[] { t.PrimaryKey! }.Select(k => new { name = k.Name, columns = k.Columns, primary = true })
            .Concat(t.UniqueConstraints.Select(k => new { name = k.Name, columns = k.Columns, primary = false })),
        foreignKeys = t.ForeignKeys.Select(f => new
        {
            name = f.Name, columns = f.Columns, principalTable = f.PrincipalTable,
            principalColumns = f.PrincipalColumns,
            reconcileWhenMissing = ReferenceEquals(f, packageFk) || ReferenceEquals(f, serviceFk) || ReferenceEquals(f, studioFk) || ReferenceEquals(f, availabilityFk) || ReferenceEquals(f, portfolioFk) || ReferenceEquals(f, serviceOwnerFk) || ReferenceEquals(f, ownershipFk),
            deleteAction = f.OnDelete switch
            {
                ReferentialAction.Cascade => "c", ReferentialAction.Restrict => "r",
                ReferentialAction.SetNull => "n", ReferentialAction.NoAction => "a",
                _ => throw new InvalidOperationException("Unsupported foreign key action.")
            }
        }),
        indexes = allIndexes.Where(i => i.Table == t.Name).Select(i => new
        {
            name = i.Name, columns = i.Columns, unique = i.IsUnique, filter = i.Filter,
            reconcileKnownPartial = ReferenceEquals(i, ownershipIndex),
            reconcileWhenMissing = ReferenceEquals(i, serviceIndex)
        }),
        checks = t.CheckConstraints.Select(c => new { name = c.Name, sql = c.Sql, catalogSql = c.Name == "CK_Reviews_Rating" ? "((\"Rating\" >= 1) AND (\"Rating\" <= 5))" : c.Sql })
    })
}, new JsonSerializerOptions { WriteIndented = true });

var selected = new List<MigrationOperation>();
foreach (var column in additions)
{
    column.Table = "Users";
    column.Schema = "public";
    selected.Add(column);
}
foreach (var operation in allOperations)
{
    if (operation is CreateTableOperation table && missingTables.Contains(table.Name))
    {
        table.Schema = "public";
        foreach (var fk in table.ForeignKeys) { fk.Schema = "public"; fk.PrincipalSchema = "public"; }
        selected.Add(table);
    }
    else if (operation is CreateIndexOperation index && missingTables.Contains(index.Table))
    {
        index.Schema = "public";
        selected.Add(index);
    }
}
if (selected.OfType<CreateTableOperation>().Count() != 5 ||
    selected.OfType<CreateIndexOperation>().Count() != 12 ||
    selected.OfType<CreateTableOperation>().Sum(t => t.ForeignKeys.Count) != 10)
    throw new InvalidOperationException("Constraint scope changed; review reconciliation manually.");

// Each operation is executed only from the validated absent-object plan.
// Keep EF's dependency ordering; indexes are created only with their new table.
var ddlBuilder = new StringBuilder();
foreach (var operation in selected)
{
    var condition = operation switch
    {
        AddColumnOperation column => $"'{column.Name}' = ANY(planned_user_columns)",
        CreateTableOperation table => $"'{table.Name}' = ANY(planned_tables)",
        CreateIndexOperation index => $"'{index.Table}' = ANY(planned_tables)",
        _ => throw new InvalidOperationException("Unexpected conditional operation.")
    };
    var commands = db.GetService<IMigrationsSqlGenerator>().Generate(new[] { operation }, model);
    if (commands.Any(c => c.TransactionSuppressed))
        throw new InvalidOperationException("All reconciliation operations must be transactional.");
    ddlBuilder.AppendLine($"    IF {condition} THEN");
    foreach (var command in commands) ddlBuilder.AppendLine(command.CommandText);
    ddlBuilder.AppendLine("    END IF;");
}
var ddl = ddlBuilder.ToString();
var preflightTemplate = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "preflight.sql"));
var preflight = preflightTemplate.Replace("__MODEL_JSON__", manifest);
const string ownershipNotNullDdl = "ALTER TABLE public.\"Studios\" ALTER COLUMN \"UserId\" SET NOT NULL;";
const string ownershipFkDdl = "ALTER TABLE public.\"Studios\" ADD CONSTRAINT \"FK_Studios_Users_UserId\" FOREIGN KEY (\"UserId\") REFERENCES public.\"Users\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string ownershipIndexDdl = "CREATE UNIQUE INDEX \"IX_Studios_UserId_reconciliation\" ON public.\"Studios\" USING btree (\"UserId\");\n" +
    "        DROP INDEX public.\"IX_Studios_UserId\" RESTRICT;\n" +
    "        ALTER INDEX public.\"IX_Studios_UserId_reconciliation\" RENAME TO \"IX_Studios_UserId\";";
const string availabilityNotNullDdl = "ALTER TABLE public.\"StudioAvailabilities\" ALTER COLUMN \"StudioId\" SET NOT NULL;";
const string availabilityFkDdl = "ALTER TABLE public.\"StudioAvailabilities\" ADD CONSTRAINT \"FK_StudioAvailabilities_Studios_StudioId\" FOREIGN KEY (\"StudioId\") REFERENCES public.\"Studios\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string portfolioNotNullDdl = "ALTER TABLE public.\"StudioPortfolios\" ALTER COLUMN \"StudioId\" SET NOT NULL;";
const string portfolioFkDdl = "ALTER TABLE public.\"StudioPortfolios\" ADD CONSTRAINT \"FK_StudioPortfolios_Studios_StudioId\" FOREIGN KEY (\"StudioId\") REFERENCES public.\"Studios\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string serviceOwnerNotNullDdl = "ALTER TABLE public.\"StudioServices\" ALTER COLUMN \"StudioId\" SET NOT NULL;";
const string serviceOwnerFkDdl = "ALTER TABLE public.\"StudioServices\" ADD CONSTRAINT \"FK_StudioServices_Studios_StudioId\" FOREIGN KEY (\"StudioId\") REFERENCES public.\"Studios\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string studioFkDdl = "ALTER TABLE public.\"PhotographyPackages\" ADD CONSTRAINT \"FK_PhotographyPackages_Studios_StudioId\" FOREIGN KEY (\"StudioId\") REFERENCES public.\"Studios\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string packageFkDdl = "ALTER TABLE public.\"PhotographyPackageServices\" ADD CONSTRAINT \"FK_PhotographyPackageServices_PhotographyPackages_PhotographyP~\" FOREIGN KEY (\"PhotographyPackageId\") REFERENCES public.\"PhotographyPackages\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string serviceFkDdl = "ALTER TABLE public.\"PhotographyPackageServices\" ADD CONSTRAINT \"FK_PhotographyPackageServices_StudioServices_StudioServiceId\" FOREIGN KEY (\"StudioServiceId\") REFERENCES public.\"StudioServices\" (\"Id\") MATCH SIMPLE ON UPDATE NO ACTION ON DELETE CASCADE NOT DEFERRABLE;";
const string serviceIndexDdl = "CREATE INDEX \"IX_PhotographyPackageServices_StudioServiceId\" ON public.\"PhotographyPackageServices\" USING btree (\"StudioServiceId\");";
var header = "-- Generated offline from ApplicationDbContext. REVIEW BEFORE EXECUTION.\n" +
             "-- Requires PostgreSQL public schema and the exact documented starting state.\n" +
             "-- Legacy migrations/history are never executed or modified.\n";
var transaction = "BEGIN;\nSET LOCAL search_path = pg_catalog, public;\n" +
                  "SET LOCAL lock_timeout = '5s';\nSET LOCAL statement_timeout = '60s';\n";
var locks = "-- Run in a maintenance window. Freeze the existing tables before validating.\n" +
            "SELECT pg_advisory_xact_lock(20260918, 1);\n" +
            "LOCK TABLE public.\"Users\" IN ACCESS EXCLUSIVE MODE;\n" +
            string.Join("\n", existingTables.Where(t => t != "Users").OrderBy(t => t, StringComparer.Ordinal)
                .Select(t => $"LOCK TABLE public.\"{t}\" IN SHARE ROW EXCLUSIVE MODE;")) +
            "\nLOCK TABLE public.\"__EFMigrationsHistory\" IN SHARE MODE;\n";
locks += "DO $target_locks$ DECLARE target_name text; BEGIN\n" +
    "FOREACH target_name IN ARRAY ARRAY['BookingLocations','BookingStatusHistories','Bookings','Notifications','Reviews'] LOOP\n" +
    "IF to_regclass(format('public.%I', target_name)) IS NOT NULL THEN\n" +
    "EXECUTE format('LOCK TABLE public.%I IN SHARE ROW EXCLUSIVE MODE', target_name);\n" +
    "END IF; END LOOP; END; $target_locks$;\n";
var outputs = new Dictionary<string, string>
{
    ["current-model.json"] = manifest + "\n",
    ["001_reconcile.sql"] = header + transaction + locks + preflight.Replace("__PACKAGE_FK_DDL__", packageFkDdl).Replace("__SERVICE_FK_DDL__", serviceFkDdl).Replace("__STUDIO_FK_DDL__", studioFkDdl).Replace("__AVAILABILITY_NOT_NULL_DDL__", availabilityNotNullDdl).Replace("__AVAILABILITY_FK_DDL__", availabilityFkDdl).Replace("__PORTFOLIO_NOT_NULL_DDL__", portfolioNotNullDdl).Replace("__PORTFOLIO_FK_DDL__", portfolioFkDdl).Replace("__SERVICE_OWNER_NOT_NULL_DDL__", serviceOwnerNotNullDdl).Replace("__SERVICE_OWNER_FK_DDL__", serviceOwnerFkDdl).Replace("__SERVICE_INDEX_DDL__", serviceIndexDdl).Replace("__OWNERSHIP_NOT_NULL_DDL__", ownershipNotNullDdl).Replace("__OWNERSHIP_FK_DDL__", ownershipFkDdl).Replace("__OWNERSHIP_INDEX_DDL__", ownershipIndexDdl).Replace("__TARGET_OBJECT_DDL__", ddl) +
        "\n-- No DML, migration-history writes, or destructive rollback.\nCOMMIT;\n",
    ["001_preflight.sql"] = header + transaction + "SET TRANSACTION READ ONLY;\n" + preflight.Replace("__PACKAGE_FK_DDL__", "-- Inspection only; no DDL.").Replace("__SERVICE_FK_DDL__", "-- Inspection only; no DDL.").Replace("__STUDIO_FK_DDL__", "-- Inspection only; no DDL.").Replace("__AVAILABILITY_NOT_NULL_DDL__", "-- Inspection only; no DDL.").Replace("__AVAILABILITY_FK_DDL__", "-- Inspection only; no DDL.").Replace("__PORTFOLIO_NOT_NULL_DDL__", "-- Inspection only; no DDL.").Replace("__PORTFOLIO_FK_DDL__", "-- Inspection only; no DDL.").Replace("__SERVICE_OWNER_NOT_NULL_DDL__", "-- Inspection only; no DDL.").Replace("__SERVICE_OWNER_FK_DDL__", "-- Inspection only; no DDL.").Replace("__SERVICE_INDEX_DDL__", "-- Inspection only; no DDL.").Replace("__OWNERSHIP_NOT_NULL_DDL__", "-- Inspection only; no DDL.").Replace("__OWNERSHIP_FK_DDL__", "-- Inspection only; no DDL.").Replace("__OWNERSHIP_INDEX_DDL__", "-- Inspection only; no DDL.").Replace("__TARGET_OBJECT_DDL__", "-- Inspection only; planned absent objects reported above.") +
        "\n-- Read-only check; the apply script repeats checks under locks.\nROLLBACK;\n"
};
var outputDirectory = Path.GetFullPath(args[1]);
foreach (var (name, contents) in outputs)
{
    var normalized = contents.Replace("\r\n", "\n");
    var path = Path.Combine(outputDirectory, name);
    if (args[0] == "--generate")
    {
        Directory.CreateDirectory(outputDirectory);
        File.WriteAllText(path, normalized, new UTF8Encoding(false));
    }
    else if (!File.Exists(path) || File.ReadAllText(path).Replace("\r\n", "\n") != normalized)
        throw new InvalidOperationException($"Artifact differs from current model/generator: {name}");
}
Console.WriteLine($"{args[0]}: 2 nullable columns, 5 tables, 10 new-table foreign keys, 7 guarded existing-table FKs, 4 guarded NOT NULL changes, 1 guarded ownership index replacement, 12 new-table indexes, 1 guarded service index. No database connection opened.");
return 0;

sealed class RejectConnections : DbConnectionInterceptor
{
    public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData eventData,
        InterceptionResult result) => throw new InvalidOperationException("Database access is forbidden in this offline generator.");

    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection,
        ConnectionEventData eventData, InterceptionResult result, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database access is forbidden in this offline generator.");
}
