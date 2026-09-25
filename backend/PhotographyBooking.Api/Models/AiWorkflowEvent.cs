namespace PhotographyBooking.Api.Models;

public sealed class AiWorkflowEvent
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid WorkflowId { get; set; }
    public AiWorkflow Workflow { get; set; } = null!;
    public string EventType { get; set; } = string.Empty;
    public string StepName { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    // Allow-listed operational metadata only: proposalVersion, errorCode, attempt.
    public string? DetailsJson { get; set; }
    public bool Success { get; set; }
    public long? DurationMs { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
