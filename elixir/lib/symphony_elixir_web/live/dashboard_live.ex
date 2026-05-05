defmodule SymphonyElixirWeb.DashboardLive do
  @moduledoc """
  Live observability dashboard for Symphony, including a kanban board grouped
  by tracker state.
  """

  use Phoenix.LiveView, layout: {SymphonyElixirWeb.Layouts, :app}

  alias SymphonyElixir.Config
  alias SymphonyElixirWeb.{Endpoint, ObservabilityPubSub, Presenter}

  @runtime_tick_ms 1_000
  @board_refresh_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    now = DateTime.utc_now()

    socket =
      socket
      |> assign(:payload, load_payload())
      |> assign(:now, now)
      |> assign(:refresh_ms, refresh_ms())
      |> assign(:last_refresh_at, now)

    if connected?(socket) do
      :ok = ObservabilityPubSub.subscribe()
      schedule_runtime_tick()
      schedule_board_refresh()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:runtime_tick, socket) do
    schedule_runtime_tick()

    {:noreply,
     socket
     |> assign(:now, DateTime.utc_now())
     |> assign(:refresh_ms, refresh_ms())}
  end

  @impl true
  def handle_info(:board_refresh, socket) do
    schedule_board_refresh()

    {:noreply,
     socket
     |> assign(:payload, load_payload())
     |> assign(:now, DateTime.utc_now())}
  end

  @impl true
  def handle_info(:observability_updated, socket) do
    now = DateTime.utc_now()

    {:noreply,
     socket
     |> assign(:payload, load_payload())
     |> assign(:now, now)
     |> assign(:last_refresh_at, now)
     |> assign(:refresh_ms, refresh_ms())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="dashboard-shell">
      <header class="hero-card">
        <div class="hero-grid">
          <div>
            <p class="eyebrow">
              Symphony Observability
            </p>
            <h1 class="hero-title">
              Operations Board
            </h1>
            <p class="hero-copy">
              Issues across tracker states, with live agent activity, retries, and token usage.
            </p>
          </div>

          <div class="status-stack">
            <span class="status-badge status-badge-live">
              <span class="status-badge-dot"></span>
              Live
            </span>
            <span class="status-badge status-badge-offline">
              <span class="status-badge-dot"></span>
              Offline
            </span>
            <span class="status-badge status-badge-countdown numeric" title="Time until the next data refresh pull.">
              Next refresh in <%= format_countdown(next_refresh_seconds(@last_refresh_at, @refresh_ms, @now)) %>
            </span>
          </div>
        </div>
      </header>

      <%= if @payload[:error] do %>
        <section class="error-card">
          <h2 class="error-title">
            Snapshot unavailable
          </h2>
          <p class="error-copy">
            <strong><%= @payload.error.code %>:</strong> <%= @payload.error.message %>
          </p>
        </section>
      <% else %>
        <section class="metric-grid">
          <article class="metric-card">
            <p class="metric-label">Running</p>
            <p class="metric-value numeric"><%= @payload.counts.running %></p>
            <p class="metric-detail">Active issue sessions in the current runtime.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Retrying</p>
            <p class="metric-value numeric"><%= @payload.counts.retrying %></p>
            <p class="metric-detail">Issues waiting for the next retry window.</p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Total tokens</p>
            <p class="metric-value numeric"><%= format_int(@payload.codex_totals.total_tokens) %></p>
            <p class="metric-detail numeric">
              In <%= format_int(@payload.codex_totals.input_tokens) %> / Out <%= format_int(@payload.codex_totals.output_tokens) %>
            </p>
          </article>

          <article class="metric-card">
            <p class="metric-label">Runtime</p>
            <p class="metric-value numeric"><%= format_runtime_seconds(total_runtime_seconds(@payload, @now)) %></p>
            <p class="metric-detail">Total Codex runtime across completed and active sessions.</p>
          </article>
        </section>

        <%= if board = @payload[:board] do %>
          <%= if board.tracker_error do %>
            <section class="error-card">
              <h2 class="error-title">Tracker unavailable</h2>
              <p class="error-copy">
                <strong><%= board.tracker_error.code %>:</strong> <%= board.tracker_error.message %>
              </p>
            </section>
          <% end %>

          <section class="board-shell">
            <div class="board-grid">
              <article :for={column <- board.columns} class={"board-column board-column-" <> column.kind}>
                <header class="board-column-header">
                  <h2 class="board-column-title"><%= column.name %></h2>
                  <span class="board-column-count numeric"><%= length(column.cards) %></span>
                </header>

                <%= if column.cards == [] do %>
                  <p class="board-column-empty">No issues.</p>
                <% else %>
                  <ul class="board-card-list">
                    <li :for={card <- column.cards} class={"board-card board-card-" <> card.status}>
                      <header class="board-card-header">
                        <%= if card.url do %>
                          <a class="board-card-id" href={card.url} target="_blank" rel="noopener noreferrer">
                            <%= card.issue_identifier %>
                          </a>
                        <% else %>
                          <span class="board-card-id"><%= card.issue_identifier %></span>
                        <% end %>
                        <span class={"board-card-status board-card-status-" <> card.status}>
                          <%= card.status %>
                        </span>
                      </header>
                      <p class="board-card-title"><%= card.title || "(untitled)" %></p>

                      <%= if card.running do %>
                        <dl class="board-card-stats numeric">
                          <div>
                            <dt>Runtime</dt>
                            <dd><%= format_runtime_and_turns(card.running.started_at, card.running.turn_count, @now) %></dd>
                          </div>
                          <div>
                            <dt>Tokens</dt>
                            <dd><%= format_int(card.running.tokens.total_tokens) %></dd>
                          </div>
                        </dl>
                        <p class="board-card-event" title={card.running.last_message || to_string(card.running.last_event || "")}>
                          <%= card.running.last_message || to_string(card.running.last_event || "") %>
                        </p>
                      <% end %>

                      <%= if card.retry do %>
                        <dl class="board-card-stats numeric">
                          <div>
                            <dt>Attempt</dt>
                            <dd><%= card.retry.attempt %></dd>
                          </div>
                          <div>
                            <dt>Due</dt>
                            <dd class="mono"><%= card.retry.due_at || "n/a" %></dd>
                          </div>
                        </dl>
                        <%= if card.retry.error do %>
                          <p class="board-card-event"><%= card.retry.error %></p>
                        <% end %>
                      <% end %>

                      <footer class="board-card-footer">
                        <span class="muted">Updated <%= format_age(card.updated_at, @now) %></span>
                      </footer>
                    </li>
                  </ul>
                <% end %>
              </article>
            </div>
          </section>
        <% end %>
      <% end %>
    </section>
    """
  end

  defp load_payload do
    Presenter.board_payload(orchestrator(), snapshot_timeout_ms())
  end

  defp orchestrator do
    Endpoint.config(:orchestrator) || SymphonyElixir.Orchestrator
  end

  defp snapshot_timeout_ms do
    Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp completed_runtime_seconds(payload) do
    payload.codex_totals.seconds_running || 0
  end

  defp total_runtime_seconds(payload, now) do
    completed_runtime_seconds(payload) +
      Enum.reduce(payload.running, 0, fn entry, total ->
        total + runtime_seconds_from_started_at(entry.started_at, now)
      end)
  end

  defp format_runtime_and_turns(started_at, turn_count, now) when is_integer(turn_count) and turn_count > 0 do
    "#{format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))} / #{turn_count}"
  end

  defp format_runtime_and_turns(started_at, _turn_count, now),
    do: format_runtime_seconds(runtime_seconds_from_started_at(started_at, now))

  defp format_runtime_seconds(seconds) when is_number(seconds) do
    whole_seconds = max(trunc(seconds), 0)
    mins = div(whole_seconds, 60)
    secs = rem(whole_seconds, 60)
    "#{mins}m #{secs}s"
  end

  defp format_age(nil, _now), do: "n/a"

  defp format_age(iso, %DateTime{} = now) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} ->
        seconds = DateTime.diff(now, dt, :second)
        humanize_age(seconds)

      _ ->
        "n/a"
    end
  end

  defp humanize_age(seconds) when seconds < 60, do: "#{max(seconds, 0)}s ago"
  defp humanize_age(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp humanize_age(seconds) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp humanize_age(seconds), do: "#{div(seconds, 86_400)}d ago"

  defp runtime_seconds_from_started_at(%DateTime{} = started_at, %DateTime{} = now) do
    DateTime.diff(now, started_at, :second)
  end

  defp runtime_seconds_from_started_at(started_at, %DateTime{} = now) when is_binary(started_at) do
    case DateTime.from_iso8601(started_at) do
      {:ok, parsed, _offset} -> runtime_seconds_from_started_at(parsed, now)
      _ -> 0
    end
  end

  defp runtime_seconds_from_started_at(_started_at, _now), do: 0

  defp format_int(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  defp format_int(_value), do: "n/a"

  defp schedule_runtime_tick do
    Process.send_after(self(), :runtime_tick, @runtime_tick_ms)
  end

  defp schedule_board_refresh do
    Process.send_after(self(), :board_refresh, @board_refresh_ms)
  end

  defp refresh_ms do
    Config.settings!().observability.refresh_ms
  rescue
    _ -> 1_000
  end

  @doc false
  @spec next_refresh_seconds(DateTime.t() | term(), pos_integer() | term(), DateTime.t() | term()) ::
          non_neg_integer()
  def next_refresh_seconds(%DateTime{} = last_refresh_at, refresh_ms, %DateTime{} = now)
      when is_integer(refresh_ms) and refresh_ms > 0 do
    elapsed_ms = DateTime.diff(now, last_refresh_at, :millisecond)
    remaining_ms = max(refresh_ms - elapsed_ms, 0)
    div(remaining_ms + 999, 1_000)
  end

  def next_refresh_seconds(_last_refresh_at, _refresh_ms, _now), do: 0

  defp format_countdown(seconds) when is_integer(seconds) and seconds >= 0, do: "#{seconds}s"
  defp format_countdown(_), do: "0s"
end
