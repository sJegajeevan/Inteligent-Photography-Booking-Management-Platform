using Microsoft.EntityFrameworkCore;
using PhotographyBooking.Api.Models;

namespace PhotographyBooking.Api.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(
        DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<Booking> Bookings => Set<Booking>();
    public DbSet<BookingStatusHistory> BookingStatusHistories => Set<BookingStatusHistory>();
    public DbSet<BookingLocation> BookingLocations => Set<BookingLocation>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Booking>(entity =>
        {
            entity.Property(booking => booking.Location).HasMaxLength(500);
            entity.Property(booking => booking.Notes).HasMaxLength(1_000);
            entity.Property(booking => booking.TotalPrice).HasPrecision(18, 2);

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
    }
}
