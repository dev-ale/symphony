defmodule SymphonyElixirWeb.DashboardLiveTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixirWeb.DashboardLive

  describe "next_refresh_seconds/3" do
    test "returns ceiling of remaining seconds until next refresh" do
      last = ~U[2025-01-01 00:00:00.000Z]
      now = ~U[2025-01-01 00:00:00.500Z]

      assert DashboardLive.next_refresh_seconds(last, 5_000, now) == 5
    end

    test "clamps to zero once the refresh window has elapsed" do
      last = ~U[2025-01-01 00:00:00.000Z]
      now = ~U[2025-01-01 00:00:10.000Z]

      assert DashboardLive.next_refresh_seconds(last, 5_000, now) == 0
    end

    test "returns full window immediately after a refresh" do
      now = ~U[2025-01-01 00:00:00.000Z]

      assert DashboardLive.next_refresh_seconds(now, 1_000, now) == 1
    end
  end
end
