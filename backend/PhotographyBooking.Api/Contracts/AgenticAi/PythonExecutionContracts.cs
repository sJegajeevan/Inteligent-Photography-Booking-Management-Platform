using PhotographyBooking.Api.DTOs.Scheduling;

namespace PhotographyBooking.Api.Contracts.AgenticAi;

// No customer identity, proposal version, reviewer, or publication command on this boundary.
public sealed record PythonExecutionRequest(Guid ExecutionId, CustomerPhotographyRequirements Requirements);
public sealed record PythonExecutionCompletion(Guid WorkflowId, Guid ExecutionId, string Status,
    CustomerPhotographyRequirements Requirements, FinalValidationResult? Evidence,
    SchedulingCandidateResponseDto? SchedulingEvidence, string? ErrorCode);
public sealed record PythonExecutionResult(PythonExecutionCompletion? Completion, string? ErrorCode);
