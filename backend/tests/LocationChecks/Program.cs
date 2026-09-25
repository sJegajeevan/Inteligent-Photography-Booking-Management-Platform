using System.ComponentModel.DataAnnotations;
using PhotographyBooking.Api.DTOs.Studio;
using PhotographyBooking.Api.Services;

var service = new DistanceService();
var count = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception(name);
    count++;
}
Check(service.CalculateKilometers(0, 0, 0, 0) == 0, "Identical points");
Check(Math.Abs(service.CalculateKilometers(0, 0, 0, 1) - 111.195) < 0.01, "Equatorial degree");
Check(Math.Abs(service.CalculateKilometers(51.5074, -0.1278, 40.7128, -74.0060) - 5570.23) < 1, "London to New York");
Check(Math.Abs(service.CalculateKilometers(0, 179, 0, -179) - 222.39) < 0.1, "Antimeridian");
Check(Math.Abs(service.CalculateKilometers(90, 0, -90, 0) - 20015.114) < 0.1, "Antipodal poles");
Check(service.CalculateKilometers(6, 79, 7, 80) == service.CalculateKilometers(7, 80, 6, 79), "Symmetry");
foreach (var pair in new[] { (double.NaN, 0d), (0d, double.PositiveInfinity), (91d, 0d), (0d, -181d) })
{
    try { service.CalculateKilometers(pair.Item1, pair.Item2, 0, 0); throw new Exception("Accepted invalid coordinate"); }
    catch (ArgumentOutOfRangeException) { count++; }
}
foreach (var (latitude, longitude, valid) in new (decimal?, decimal?, bool)[]
{
    (null, null, true), (0, 0, true), (-90, -180, true), (90, 180, true),
    (null, 79, false), (6, null, false), (90.1m, 0, false), (0, -180.1m, false)
})
{
    var dto = new UpdateStudioDto {
        StudioName = "Test studio", Description = "A test studio profile", Location = "Colombo",
        Address = "123 Test Street", ContactNumber = "0771234567", Email = "test@example.com",
        PhotographyTypes = "Wedding", Latitude = latitude, Longitude = longitude
    };
    Check(Validator.TryValidateObject(dto, new ValidationContext(dto), new List<ValidationResult>(), true) == valid,
        "Profile coordinate validation");
}
Console.WriteLine($"Passed {count} location checks. No database accessed.");
