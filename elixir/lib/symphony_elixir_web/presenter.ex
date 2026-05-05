defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{Config, Linear.Issue, Orchestrator, StatusDashboard, Tracker}

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        %{
          generated_at: generated_at,
          counts: %{
            running: length(snapshot.running),
            retrying: length(snapshot.retrying)
          },
          running: Enum.map(snapshot.running, &running_entry_payload/1),
          retrying: Enum.map(snapshot.retrying, &retry_entry_payload/1),
          codex_totals: snapshot.codex_totals,
          rate_limits: snapshot.rate_limits
        }

      :timeout ->
        %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}

      :unavailable ->
        %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Snapshot unavailable"}}
    end
  end

  @spec board_payload(GenServer.name(), timeout()) :: map()
  def board_payload(orchestrator, snapshot_timeout_ms) do
    snapshot_payload = state_payload(orchestrator, snapshot_timeout_ms)
    tracker_settings = Config.settings!().tracker
    column_states = tracker_settings.active_states ++ tracker_settings.terminal_states

    {tracker_issues, tracker_error} =
      case Tracker.fetch_issues_by_states(column_states) do
        {:ok, issues} -> {issues, nil}
        {:error, reason} -> {[], format_tracker_error(reason)}
      end

    running_by_id = index_by_identifier(Map.get(snapshot_payload, :running, []))
    retrying_by_id = index_by_identifier(Map.get(snapshot_payload, :retrying, []))
    seen_identifiers = MapSet.new(tracker_issues, & &1.identifier)

    tracker_cards =
      Enum.map(tracker_issues, fn %Issue{} = issue ->
        running = Map.get(running_by_id, issue.identifier)
        retry = Map.get(retrying_by_id, issue.identifier)
        card_for_issue(issue, running, retry)
      end)

    runtime_cards =
      Enum.flat_map(Map.merge(running_by_id, retrying_by_id), fn {identifier, _} ->
        if MapSet.member?(seen_identifiers, identifier) do
          []
        else
          [
            card_from_runtime_only(
              identifier,
              Map.get(running_by_id, identifier),
              Map.get(retrying_by_id, identifier)
            )
          ]
        end
      end)

    cards = tracker_cards ++ runtime_cards

    column_states_unique = Enum.uniq(column_states)
    known_normalized = MapSet.new(column_states_unique, &normalize_state/1)

    columns =
      Enum.map(column_states_unique, fn state_name ->
        normalized = normalize_state(state_name)

        column_cards =
          cards
          |> Enum.filter(&(&1.state_normalized == normalized))
          |> Enum.sort_by(&card_sort_key/1, :asc)

        %{
          name: state_name,
          slug: state_slug(state_name),
          kind: column_kind(state_name, tracker_settings),
          cards: column_cards
        }
      end)

    other_cards =
      cards
      |> Enum.reject(&MapSet.member?(known_normalized, &1.state_normalized))
      |> Enum.sort_by(&card_sort_key/1, :asc)

    columns =
      if other_cards == [] do
        columns
      else
        columns ++
          [
            %{
              name: "Other",
              slug: "other",
              kind: "other",
              cards: other_cards
            }
          ]
      end

    Map.merge(snapshot_payload, %{
      board: %{
        columns: columns,
        tracker_error: tracker_error
      }
    })
  end

  @spec issue_payload(String.t(), GenServer.name(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_payload(issue_identifier, orchestrator, snapshot_timeout_ms) when is_binary(issue_identifier) do
    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        running = Enum.find(snapshot.running, &(&1.identifier == issue_identifier))
        retry = Enum.find(snapshot.retrying, &(&1.identifier == issue_identifier))

        if is_nil(running) and is_nil(retry) do
          {:error, :issue_not_found}
        else
          {:ok, issue_payload_body(issue_identifier, running, retry)}
        end

      _ ->
        {:error, :issue_not_found}
    end
  end

  @spec refresh_payload(GenServer.name()) :: {:ok, map()} | {:error, :unavailable}
  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      :unavailable ->
        {:error, :unavailable}

      payload ->
        {:ok, Map.update!(payload, :requested_at, &DateTime.to_iso8601/1)}
    end
  end

  defp index_by_identifier(entries) when is_list(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      case Map.get(entry, :issue_identifier) do
        nil -> acc
        identifier -> Map.put(acc, identifier, entry)
      end
    end)
  end

  defp card_for_issue(%Issue{} = issue, running, retry) do
    state_name = issue.state || ""

    %{
      issue_id: issue.id,
      issue_identifier: issue.identifier,
      title: issue.title,
      url: issue.url,
      state: state_name,
      state_normalized: normalize_state(state_name),
      labels: issue.labels,
      updated_at: iso8601(issue.updated_at),
      created_at: iso8601(issue.created_at),
      running: running,
      retry: retry,
      status: card_status(running, retry)
    }
  end

  defp card_from_runtime_only(identifier, running, retry) do
    state_name = (running && running.state) || ""

    %{
      issue_id: (running && running.issue_id) || (retry && retry.issue_id),
      issue_identifier: identifier,
      title: nil,
      url: nil,
      state: state_name,
      state_normalized: normalize_state(state_name),
      labels: [],
      updated_at: nil,
      created_at: nil,
      running: running,
      retry: retry,
      status: card_status(running, retry)
    }
  end

  defp card_status(nil, nil), do: "idle"
  defp card_status(_running, nil), do: "running"
  defp card_status(nil, _retry), do: "retrying"
  defp card_status(_running, _retry), do: "running"

  defp card_sort_key(card) do
    # Active sessions first, then by recency.
    priority =
      case card.status do
        "running" -> 0
        "retrying" -> 1
        _ -> 2
      end

    {priority, -recency_score(card.updated_at)}
  end

  defp recency_score(nil), do: 0

  defp recency_score(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  defp normalize_state(state) when is_binary(state),
    do: state |> String.trim() |> String.downcase()

  defp normalize_state(_), do: ""

  defp state_slug(state_name) when is_binary(state_name) do
    state_name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp state_slug(_), do: ""

  defp column_kind(state_name, tracker_settings) do
    normalized = normalize_state(state_name)
    active = MapSet.new(Enum.map(tracker_settings.active_states, &normalize_state/1))
    terminal = MapSet.new(Enum.map(tracker_settings.terminal_states, &normalize_state/1))

    cond do
      MapSet.member?(active, normalized) -> "active"
      MapSet.member?(terminal, normalized) -> "terminal"
      true -> "other"
    end
  end

  defp format_tracker_error(reason) do
    %{code: "tracker_unavailable", message: inspect(reason)}
  end

  defp issue_payload_body(issue_identifier, running, retry) do
    %{
      issue_identifier: issue_identifier,
      issue_id: issue_id_from_entries(running, retry),
      status: issue_status(running, retry),
      workspace: %{
        path: workspace_path(issue_identifier, running, retry),
        host: workspace_host(running, retry)
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      logs: %{
        codex_session_logs: []
      },
      recent_events: (running && recent_events_payload(running)) || [],
      last_error: retry && retry.error,
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry),
    do: (running && running.issue_id) || (retry && retry.issue_id)

  defp restart_count(retry), do: max(retry_attempt(retry) - 1, 0)
  defp retry_attempt(nil), do: 0
  defp retry_attempt(retry), do: retry.attempt || 0

  defp issue_status(_running, nil), do: "running"
  defp issue_status(nil, _retry), do: "retrying"
  defp issue_status(_running, _retry), do: "running"

  defp running_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      state: entry.state,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(entry.last_codex_timestamp),
      tokens: %{
        input_tokens: entry.codex_input_tokens,
        output_tokens: entry.codex_output_tokens,
        total_tokens: entry.codex_total_tokens
      }
    }
  end

  defp retry_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      attempt: entry.attempt,
      due_at: due_at_iso8601(entry.due_in_ms),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path)
    }
  end

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      started_at: iso8601(running.started_at),
      last_event: running.last_codex_event,
      last_message: summarize_message(running.last_codex_message),
      last_event_at: iso8601(running.last_codex_timestamp),
      tokens: %{
        input_tokens: running.codex_input_tokens,
        output_tokens: running.codex_output_tokens,
        total_tokens: running.codex_total_tokens
      }
    }
  end

  defp retry_issue_payload(retry) do
    %{
      attempt: retry.attempt,
      due_at: due_at_iso8601(retry.due_in_ms),
      error: retry.error,
      worker_host: Map.get(retry, :worker_host),
      workspace_path: Map.get(retry, :workspace_path)
    }
  end

  defp workspace_path(issue_identifier, running, retry) do
    (running && Map.get(running, :workspace_path)) ||
      (retry && Map.get(retry, :workspace_path)) ||
      Path.join(Config.settings!().workspace.root, issue_identifier)
  end

  defp workspace_host(running, retry) do
    (running && Map.get(running, :worker_host)) || (retry && Map.get(retry, :worker_host))
  end

  defp recent_events_payload(running) do
    [
      %{
        at: iso8601(running.last_codex_timestamp),
        event: running.last_codex_event,
        message: summarize_message(running.last_codex_message)
      }
    ]
    |> Enum.reject(&is_nil(&1.at))
  end

  defp summarize_message(nil), do: nil
  defp summarize_message(message), do: StatusDashboard.humanize_codex_message(message)

  defp due_at_iso8601(due_in_ms) when is_integer(due_in_ms) do
    DateTime.utc_now()
    |> DateTime.add(div(due_in_ms, 1_000), :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp due_at_iso8601(_due_in_ms), do: nil

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(_datetime), do: nil
end
