namespace PhotographyBooking.Api.Services;

/// <summary>Allow-listed diagnostics only; never store provider exceptions or model text.</summary>
public static class AiExecutionFailure
{
    private static readonly HashSet<string> Codes = [
        "matching_agent_not_configured", "invalid_matching_input", "no_matching_studios",
        "gemini_not_configured", "gemini_timeout", "gemini_unavailable", "malformed_structured_output",
        "backend_timeout", "backend_unavailable", "invalid_backend_response", "unknown_studio_id",
        "duplicate_studio_id", "unsupported_recommendation_claim", "package_agent_not_implemented",
        "invalid_package_input", "invalid_package_reference", "no_packages", "package_candidate_limit_exceeded",
        "no_matching_packages", "invalid_gemini_output", "unknown_package_reference", "duplicate_package_id",
        "scheduling_agent_not_implemented", "invalid_scheduling_input", "package_unavailable", "no_available_slots",
        "invalid_workflow_state", "validation_failed", "stale_recommendation", "price_changed", "slot_unavailable",
        "booking_conflict", "budget_failure", "execution_failed", "execution_timeout", "invalid_execution_response",
        "revalidation_required", "needs_input", "execution_unavailable", "execution_unauthorized", "execution_cancelled",
        "execution_started", "execution_validated", "publication_failed"
    ];
    public static bool ValidCode(string? code) => code is not null && Codes.Contains(code);
    public static bool ValidStage(string? stage) => stage is "StudioMatching" or "PackageRecommendation" or "Scheduling" or "Validation";
    public static string Message(string code) => code switch {
        "gemini_unavailable" or "gemini_timeout" => "The AI provider is temporarily unavailable. Please try again later.",
        "gemini_not_configured" => "The AI provider is not configured.",
        "no_matching_studios" => "No studio matches the requested requirements.",
        "no_packages" or "no_matching_packages" or "budget_failure" => "No package meets the requested services and budget.",
        "no_available_slots" or "slot_unavailable" or "booking_conflict" => "No available time fits this recommendation.",
        "price_changed" => "The package price changed. Generate a new recommendation.",
        "stale_recommendation" or "revalidation_required" => "The recommendation requires fresh validation.",
        "backend_timeout" or "backend_unavailable" => "Application data is temporarily unavailable.",
        _ => "The recommendation could not be safely completed. Please try again."
    };
}
