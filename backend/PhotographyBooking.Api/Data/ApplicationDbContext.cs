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

    public DbSet<User> Users { get; set; }

    public ApplicationDbContext(
        DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        modelBuilder.Entity<Studio>(entity =>
        {
            entity.HasIndex(s => s.UserId).IsUnique();
            entity.Property(s => s.StudioName).HasMaxLength(120);
            entity.Property(s => s.Description).HasMaxLength(1000);
            entity.Property(s => s.Location).HasMaxLength(160);
            entity.Property(s => s.Address).HasMaxLength(240);
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
    }
}
