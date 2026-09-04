using System.ComponentModel.DataAnnotations;

namespace PhotographyBooking.Api.DTOs.StudioServices;

public class StudioServiceRequestDto
{
    [Required(AllowEmptyStrings = false)]
    [StringLength(160)]
    [RegularExpression(@".*\S.*", ErrorMessage = "Service name is required.")]
    public string ServiceName { get; set; } = string.Empty;

    [Required(AllowEmptyStrings = false)]
    [StringLength(1000)]
    [RegularExpression(@"[\s\S]*\S[\s\S]*", ErrorMessage = "Description is required.")]
    public string Description { get; set; } = string.Empty;

    public List<string> PackageDetails { get; set; } = [];

    [Range(typeof(decimal), "0", "9999999999.99", ErrorMessage = "Starting price must be a valid non-negative number.")]
    public decimal StartingPrice { get; set; }
}
