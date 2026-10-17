import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

import StudioBookings from "../src/pages/Studio/StudioBookings";
import { getBookings } from "../src/services/bookingService";
import ProtectedRoute from "../src/components/auth/ProtectedRoute";

const authState = {
  isAuthenticated: true,
  user: {
    role: "studio",
  },
};

vi.mock("../src/context/useAuth", () => ({
  useAuth: () => authState,
}));

describe("React Booking Application Tests", () => {
  beforeEach(() => {
    vi.restoreAllMocks();

    authState.isAuthenticated = true;
    authState.user = {
      role: "studio",
    };
  });

  it("fetches bookings with authentication and normalizes booking status", async () => {
    const mockBookings = [
      {
        id: 4,
        customerId: 10,
        studioId: "studio-1",
        packageId: 5,
        customerName: "Test Customer",
        studioName: "Test Studio",
        packageName: "Wedding Package",
        bookingDate: "2026-10-10",
        startTime: "10:00:00",
        endTime: "12:00:00",
        location: "Dambulla",
        status: 3,
      },
    ];

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => mockBookings,
      })
    );

    const result = await getBookings("test-token");

    expect(fetch).toHaveBeenCalledWith(
      "/api/bookings",
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer test-token",
          "Content-Type": "application/json",
        }),
      })
    );

    expect(result[0].status).toBe("Confirmed");
  });

  it("displays the booking error state and retry button", () => {
    const retryMock = vi.fn();

    render(
      <StudioBookings
        bookings={[]}
        isLoading={false}
        error="Unable to connect to the booking server."
        onRetry={retryMock}
      />
    );

    expect(
      screen.getByText("Unable to load bookings.")
    ).toBeInTheDocument();

    expect(
      screen.getByText("Unable to connect to the booking server.")
    ).toBeInTheDocument();

    expect(
      screen.getByRole("button", { name: "Retry" })
    ).toBeInTheDocument();
  });

  it("displays a booking and its status in the booking table", () => {
    const booking = {
      id: 4,
      customerId: 10,
      studioId: "studio-1",
      packageId: 5,
      customerName: "Test Customer",
      studioName: "Test Studio",
      packageName: "Wedding Package",
      bookingDate: "2026-10-10",
      startTime: "10:00:00",
      endTime: "12:00:00",
      location: "Dambulla",
      status: "Confirmed",
      createdAt: "2026-10-01T10:00:00Z",
    };

    render(
      <StudioBookings
        bookings={[booking]}
        isLoading={false}
        error={null}
        onRetry={vi.fn()}
      />
    );

    expect(screen.getByText("#4")).toBeInTheDocument();
    expect(screen.getByText("Test Customer")).toBeInTheDocument();
    expect(screen.getByText(/Wedding Package/)).toBeInTheDocument();

    expect(
      screen.getByLabelText(
        "Confirmed: The booking is approved and scheduled."
      )
    ).toBeInTheDocument();
  });

  it("blocks unauthenticated users from protected content", () => {
  authState.isAuthenticated = false;
  authState.user = null;

  render(
    <ProtectedRoute allowedRoles={["studio"]}>
      <div>Protected Studio Content</div>
    </ProtectedRoute>
  );

  expect(
    screen.queryByText("Protected Studio Content")
  ).not.toBeInTheDocument();
  });
});