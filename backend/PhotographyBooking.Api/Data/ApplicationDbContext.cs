using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Data;

public class ApplicationDbContext : DbContext
{
    public DbSet<Studio> Studios { get; set; }
    public DbSet<StudioPortfolio> StudioPortfolios { get; set; }
    public DbSet<StudioPortfolioImage> StudioPortfolioImages { get; set; }
    public DbSet<StudioService> StudioServices { get; set; }
    public DbSet<StudioAvailability> StudioAvailabilities { get; set; }
    public DbSet<PhotographyPackage> PhotographyPackages { get; set; }
    public DbSet<PhotographyPackageService> PhotographyPackageServices { get; set; }
    public DbSet<PackageAddon> PackageAddons { get; set; }

    public DbSet<User> Users { get; set; }
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AiWorkflow> AiWorkflows => Set<AiWorkflow>();
    public DbSet<AiWorkflowEvent> AiWorkflowEvents => Set<AiWorkflowEvent>();
    public DbSet<AiWorkflowApproval> AiWorkflowApprovals => Set<AiWorkflowApproval>();

    public ApplicationDbContext(
        DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<Review> Reviews => Set<Review>();
    public DbSet<BookingStatusHistory> BookingStatusHistories => Set<BookingStatusHistory>();
    public DbSet<BookingLocation> BookingLocations => Set<BookingLocation>();

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        AiWorkflowPersistenceGuard.Validate(ChangeTracker);
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(bool acceptAllChangesOnSuccess, CancellationToken cancellationToken = default)
    {
        AiWorkflowPersistenceGuard.Validate(ChangeTracker);
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        AiWorkflowConfiguration.Configure(modelBuilder);

        modelBuilder.Entity<Notification>(entity =>
        {
            entity.Property(n => n.Title).HasMaxLength(160).IsRequired();
            entity.Property(n => n.Message).HasMaxLength(1000).IsRequired();
            entity.Property(n => n.Type).HasMaxLength(60).IsRequired();
            entity.HasIndex(n => new { n.CustomerId, n.CreatedAt });
            entity.HasIndex(n => new { n.CustomerId, n.IsRead });
            entity.HasOne(n => n.Customer).WithMany().HasForeignKey(n => n.CustomerId)
                .OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(n => n.Booking).WithMany().HasForeignKey(n => n.BookingId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        // Keep the existing database email uniqueness constraint in the EF model.
        modelBuilder.Entity<User>().HasIndex(user => user.Email).IsUnique();

        modelBuilder.Entity<Review>(entity =>
        {
            entity.ToTable("Reviews", table => table.HasCheckConstraint(
                "CK_Reviews_Rating", "\"Rating\" BETWEEN 1 AND 5"));
            entity.Property(review => review.Comment).HasMaxLength(2000);
            entity.HasIndex(review => review.BookingId).IsUnique();
            entity.HasIndex(review => new { review.BookingId, review.CustomerId, review.StudioId }).IsUnique();
            entity.HasIndex(review => new { review.StudioId, review.CreatedAt });
            entity.HasOne(review => review.Booking).WithOne()
                .HasForeignKey<Review>(review => new { review.BookingId, review.CustomerId, review.StudioId })
                .HasPrincipalKey<Booking>(booking => new { booking.Id, booking.CustomerId, booking.StudioId })
                .OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(review => review.Customer).WithMany()
                .HasForeignKey(review => review.CustomerId).OnDelete(DeleteBehavior.Restrict);
            entity.HasOne(review => review.Studio).WithMany()
                .HasForeignKey(review => review.StudioId).OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Booking>(entity =>
        {
            entity.Property(booking => booking.Location).HasMaxLength(500);
            entity.Property(booking => booking.Notes).HasMaxLength(1_000);
            entity.Property(booking => booking.TotalPrice).HasPrecision(18, 2);
            entity.Property(booking => booking.PricingSnapshotJson).HasColumnType("jsonb");

            entity.HasOne(booking => booking.Customer)
                .WithMany()
                .HasForeignKey(booking => booking.CustomerId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(booking => booking.Studio)
                .WithMany()
                .HasForeignKey(booking => booking.StudioId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(booking => booking.Package)
                .WithMany()
                .HasForeignKey(booking => booking.PackageId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasMany(booking => booking.StatusHistory)
                .WithOne(history => history.Booking)
                .HasForeignKey(history => history.BookingId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(booking => booking.BookingLocation)
                .WithOne(location => location.Booking)
                .HasForeignKey<BookingLocation>(location => location.BookingId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<BookingStatusHistory>(entity =>
        {
            entity.Property(history => history.ChangedBy).HasMaxLength(200);
            entity.Property(history => history.Reason).HasMaxLength(1_000);
        });

        modelBuilder.Entity<BookingLocation>(entity =>
        {
            entity.Property(location => location.Address).HasMaxLength(500);
            entity.Property(location => location.City).HasMaxLength(100);
            entity.Property(location => location.Notes).HasMaxLength(1_000);
            entity.Property(location => location.Latitude).HasPrecision(9, 6);
            entity.Property(location => location.Longitude).HasPrecision(9, 6);

        });

        modelBuilder.Entity<Studio>(entity =>
        {
            entity.HasIndex(s => s.UserId).IsUnique();
            entity.Property(s => s.StudioName).HasMaxLength(120);
            entity.Property(s => s.Description).HasMaxLength(1000);
            entity.Property(s => s.Location).HasMaxLength(160);
            entity.Property(s => s.Address).HasMaxLength(240);
            entity.Property(s => s.Latitude).HasPrecision(9, 6);
            entity.Property(s => s.Longitude).HasPrecision(9, 6);
            entity.ToTable("Studios", table => table.HasCheckConstraint("CK_Studios_Coordinates",
                "(\"Latitude\" IS NULL AND \"Longitude\" IS NULL) OR " +
                "(\"Latitude\" IS NOT NULL AND \"Longitude\" IS NOT NULL AND " +
                "\"Latitude\" BETWEEN -90 AND 90 AND \"Longitude\" BETWEEN -180 AND 180)"));
            entity.Property(s => s.ContactNumber).HasMaxLength(30);
            entity.Property(s => s.Email).HasMaxLength(254);
            entity.Property(s => s.PhotographyTypes).HasMaxLength(500);
            entity.Property(s => s.StartingPrice).HasPrecision(12, 2);
            entity.Property(s => s.LogoUrl).HasMaxLength(2048);
            entity.Property(s => s.CoverPhotoUrl).HasMaxLength(2048);
            entity.HasOne(s => s.User).WithOne().HasForeignKey<Studio>(s => s.UserId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<StudioPortfolio>(entity =>
        {
            entity.Property(p => p.Title).HasMaxLength(160);
            entity.Property(p => p.Description).HasMaxLength(1000);
            entity.Property(p => p.ImageUrl).HasMaxLength(2048);
            entity.Property(p => p.Category).HasMaxLength(60);
            entity.HasIndex(p => p.StudioId);
            entity.HasOne(p => p.Studio).WithMany().HasForeignKey(p => p.StudioId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<StudioPortfolioImage>(entity =>
        {
            entity.Property(image => image.ImageUrl).HasMaxLength(2048);
            entity.HasIndex(image => new { image.StudioPortfolioId, image.DisplayOrder });
            entity.HasOne(image => image.StudioPortfolio).WithMany(portfolio => portfolio.Images).HasForeignKey(image => image.StudioPortfolioId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<StudioService>(entity =>
        {
            entity.Property(s => s.ServiceName).HasMaxLength(160);
            entity.Property(s => s.Description).HasMaxLength(1000);
            entity.Property(s => s.PackageDetails).HasColumnType("text[]");
            entity.Property(s => s.StartingPrice).HasPrecision(12, 2);
            entity.HasIndex(s => s.StudioId);
            entity.HasOne(s => s.Studio).WithMany().HasForeignKey(s => s.StudioId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<StudioAvailability>(entity =>
        {
            entity.Property(a => a.Date).HasColumnType("date");
            entity.Property(a => a.StartTime).HasColumnType("time without time zone");
            entity.Property(a => a.EndTime).HasColumnType("time without time zone");
            entity.Property(a => a.Notes).HasMaxLength(1000);
            entity.HasIndex(a => new { a.StudioId, a.Date }).IsUnique();
            entity.HasOne(a => a.Studio).WithMany().HasForeignKey(a => a.StudioId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<PhotographyPackage>(entity =>
        {
            entity.Property(p => p.Name).HasMaxLength(160);
            entity.Property(p => p.BasePrice).HasPrecision(12, 2);
            entity.Property(p => p.ExtraHourRate).HasPrecision(12, 2);
            entity.Property(p => p.AdditionalPhotographerRate).HasPrecision(12, 2);
            entity.Property(p => p.DurationHours).HasPrecision(5, 2);
            entity.Property(p => p.PackageName).HasMaxLength(160);
            entity.Property(p => p.Category).HasMaxLength(100);
            entity.Property(p => p.Description).HasMaxLength(2000);
            entity.Property(p => p.Price).HasPrecision(12, 2);
            entity.Property(p => p.Duration).HasMaxLength(100);
            entity.Property(p => p.CoverImageUrl).HasMaxLength(2048);
            entity.Property(p => p.Status).HasConversion<string>().HasMaxLength(20);
            entity.HasIndex(p => p.StudioId);
            entity.HasOne(p => p.Studio).WithMany().HasForeignKey(p => p.StudioId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<PhotographyPackageService>(entity =>
        {
            entity.HasKey(link => new { link.PhotographyPackageId, link.StudioServiceId });
            entity.HasOne(link => link.PhotographyPackage).WithMany(package => package.PackageServices).HasForeignKey(link => link.PhotographyPackageId).OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(link => link.StudioService).WithMany().HasForeignKey(link => link.StudioServiceId).OnDelete(DeleteBehavior.Cascade);
        });
        modelBuilder.Entity<PackageAddon>(entity =>
        {
            entity.Property(addon => addon.Name).HasMaxLength(160);
            entity.Property(addon => addon.Description).HasMaxLength(1000);
            entity.Property(addon => addon.Price).HasPrecision(12, 2);
            entity.HasIndex(addon => addon.PackageId);
            entity.HasOne(addon => addon.Package).WithMany(package => package.Addons).HasForeignKey(addon => addon.PackageId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}
