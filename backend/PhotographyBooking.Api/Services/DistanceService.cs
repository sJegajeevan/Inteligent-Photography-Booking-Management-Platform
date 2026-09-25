namespace PhotographyBooking.Api.Services;

/// <summary>Pure great-circle distance calculation. No database, network or AI dependencies.</summary>
public sealed class DistanceService
{
    public static bool IsValidCoordinate(double latitude, double longitude) =>
        double.IsFinite(latitude) && double.IsFinite(longitude) &&
        latitude is >= -90 and <= 90 && longitude is >= -180 and <= 180;

    public double CalculateKilometers(double latitude, double longitude, double studioLatitude, double studioLongitude)
    {
        if (!IsValidCoordinate(latitude, longitude) || !IsValidCoordinate(studioLatitude, studioLongitude))
            throw new ArgumentOutOfRangeException(nameof(latitude), "Coordinates must be finite and within latitude/longitude bounds.");
        const double radians = Math.PI / 180;
        var deltaLatitude = (studioLatitude - latitude) * radians;
        var deltaLongitude = (studioLongitude - longitude) * radians;
        var a = Math.Pow(Math.Sin(deltaLatitude / 2), 2) +
            Math.Cos(latitude * radians) * Math.Cos(studioLatitude * radians) *
            Math.Pow(Math.Sin(deltaLongitude / 2), 2);
        return 6371.0088 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(a, 0, 1)));
    }
}
