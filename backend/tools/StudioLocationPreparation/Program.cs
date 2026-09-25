using System.Data.Common;
using System.ComponentModel.DataAnnotations;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.EntityFrameworkCore.Metadata;
using PhotographyBooking.Api.Data;
using PhotographyBooking.Api.LocationMigrationReview;
using PhotographyBooking.Api.Models;

// Offline generation/verification only: no settings, secrets, API host or database.
if (!(args.Length == 1 && args[0] == "--verify-model") &&
    !(args.Length == 2 && args[0] is "--generate" or "--verify"))
{
    Console.Error.WriteLine("Usage: StudioLocationPreparation --generate|--verify <SQL-file> | --verify-model");
    return 2;
}

using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>()
    .UseNpgsql().AddInterceptors(new RejectConnections()).Options);
if (db.GetService<IMigrationsAssembly>().Migrations.Count != 0)
    throw new InvalidOperationException("The API must continue excluding archived migrations.");

if (args[0] == "--verify-model")
{
    var studio = db.GetService<IDesignTimeModel>().Model.FindEntityType(typeof(Studio))!;
    if (studio.GetTableName() != "Studios")
        throw new InvalidOperationException("Studio table mapping changed.");
    foreach (var name in new[] { nameof(Studio.Latitude), nameof(Studio.Longitude) })
    {
        var property = studio.FindProperty(name);
        if (property is null || property.ClrType != typeof(decimal?) || !property.IsNullable ||
            property.GetPrecision() != 9 || property.GetScale() != 6 || property.GetColumnType() != "numeric(9,6)")
            throw new InvalidOperationException($"Incorrect EF coordinate mapping: {name}");
    }
    if (studio.GetCheckConstraints().Single(c => c.Name == "CK_Studios_Coordinates").Sql !=
        AddStudioCoordinates.CoordinateConstraint)
        throw new InvalidOperationException("EF coordinate constraint differs from the reviewed SQL.");

    (decimal? Latitude, decimal? Longitude, bool Valid)[] cases = [
        (null, null, true), (0, 0, true), (-90, -180, true), (90, 180, true),
        (6.927079m, 79.861244m, true), (null, 0, false), (0, null, false),
        (-90.000001m, 0, false), (90.000001m, 0, false),
        (0, -180.000001m, false), (0, 180.000001m, false)
    ];
    foreach (var test in cases)
    {
        var value = new Studio { Latitude = test.Latitude, Longitude = test.Longitude };
        if (Validator.TryValidateObject(value, new ValidationContext(value), [], true) != test.Valid)
            throw new InvalidOperationException("Studio coordinate model validation failed.");
    }
    Console.WriteLine("PASS: EF maps nullable numeric(9,6) coordinates and the exact database check; 11 model validation cases pass; archived migrations remain excluded. No database connection.");
    return 0;
}

var migration = new AddStudioCoordinates();
var operations = migration.UpOperations;
var columns = operations.OfType<AddColumnOperation>().ToArray();
if (operations.Count != 3 || columns.Length != 2 ||
    !columns.Select(column => column.Name).Order().SequenceEqual(new[] { "Latitude", "Longitude" }) ||
    columns.Any(column => column.Schema != "public" || column.Table != "Studios" ||
        column.ColumnType != "numeric(9,6)" || !column.IsNullable || column.ClrType != typeof(decimal) ||
        column.Precision != 9 || column.Scale != 6 || column.DefaultValue is not null || column.DefaultValueSql is not null) ||
    operations.OfType<AddCheckConstraintOperation>().Single() is not
        { Schema: "public", Table: "Studios", Name: "CK_Studios_Coordinates" } check ||
    check.Sql != AddStudioCoordinates.CoordinateConstraint)
    throw new InvalidOperationException("Migration exceeds the reviewed two-column/one-check scope.");

var commands = db.GetService<IMigrationsSqlGenerator>().Generate(operations);
var sql = """
    -- PREPARED ONLY. Requires separate review and authorization before execution.
    -- Generated offline from 20260921000100_AddStudioCoordinates.cs.
    -- No backfill, defaults, row updates or migration-history changes.
    BEGIN;
    SET LOCAL lock_timeout = '5s';
    SET LOCAL statement_timeout = '30s';
    DO $preflight$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'Studios' AND c.relkind = 'r'
      ) THEN
        RAISE EXCEPTION 'Expected an existing ordinary public.Studios table; stop for review';
      END IF;
    END;
    $preflight$;
    LOCK TABLE public."Studios" IN ACCESS EXCLUSIVE MODE;
    DO $preflight$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public."Studios"'::regclass AND NOT attisdropped
          AND attname IN ('Latitude', 'Longitude')
      ) OR EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public."Studios"'::regclass AND conname = 'CK_Studios_Coordinates'
      ) THEN
        RAISE EXCEPTION 'Coordinate columns or constraint already exist; stop for review';
      END IF;
    END;
    $preflight$;
    """ + "\n" + string.Join("\n", commands.Select(command => command.CommandText)) + "COMMIT;\n";
sql = sql.Replace("\r\n", "\n");

if (args[0] == "--verify")
{
    if (!File.Exists(args[1]) || File.ReadAllText(args[1]).Replace("\r\n", "\n") != sql)
        throw new InvalidOperationException("Prepared SQL differs from the reviewed migration.");
    Console.WriteLine("PASS: migration compiles; two nullable coordinates and one check; SQL matches; no database connection.");
}
else
{
    File.WriteAllText(args[1], sql, new UTF8Encoding(false));
    Console.WriteLine("Prepared SQL only. No database connection or migration execution.");
}
return 0;

sealed class RejectConnections : DbConnectionInterceptor
{
    public override InterceptionResult ConnectionOpening(DbConnection connection, ConnectionEventData eventData, InterceptionResult result)
        => throw new InvalidOperationException("Database access is prohibited during location preparation.");

    public override ValueTask<InterceptionResult> ConnectionOpeningAsync(DbConnection connection,
        ConnectionEventData eventData, InterceptionResult result, CancellationToken cancellationToken = default)
        => throw new InvalidOperationException("Database access is prohibited during location preparation.");
}
