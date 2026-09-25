// Optional Studio Profile visual picker. Never required for profile saving or distance.
export const googleMapsApiKey = (import.meta.env.VITE_GOOGLE_MAPS_API_KEY || "").trim();
export const hasGoogleMapsApiKey = googleMapsApiKey.length > 0;
