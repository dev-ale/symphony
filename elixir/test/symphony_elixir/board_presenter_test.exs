defmodule SymphonyElixirWeb.BoardPresenterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixirWeb.Presenter

  setup context do
    workflow_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-board-presenter-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workflow_root)
    workflow_file = Path.join(workflow_root, "WORKFLOW.md")

    write_workflow_file!(workflow_file,
      tracker_kind: "memory",
      tracker_api_token: nil,
      tracker_project_slug: nil,
      tracker_active_states: ["Todo", "In Progress", "Human Review", "Merging", "Rework"],
      tracker_terminal_states: ["Done", "Cancelled"]
    )

    Workflow.set_workflow_file_path(workflow_file)

    if Process.whereis(SymphonyElixir.WorkflowStore) do
      SymphonyElixir.WorkflowStore.force_reload()
    end

    on_exit(fn ->
      File.rm_rf(workflow_root)
    end)

    {:ok, context}
  end

  test "board_payload groups tracker issues by configured columns and merges running entries" do
    issues = [
      %Issue{
        id: "id-todo",
        identifier: "MT-100",
        title: "Plan the work",
        state: "Todo",
        url: "https://example.org/MT-100",
        labels: [],
        updated_at: DateTime.utc_now()
      },
      %Issue{
        id: "id-in-progress",
        identifier: "MT-200",
        title: "Implement the feature",
        state: "In Progress",
        url: "https://example.org/MT-200",
        labels: [],
        updated_at: DateTime.utc_now()
      },
      %Issue{
        id: "id-done",
        identifier: "MT-300",
        title: "Ship it",
        state: "Done",
        url: "https://example.org/MT-300",
        labels: [],
        updated_at: DateTime.utc_now()
      }
    ]

    Application.put_env(:symphony_elixir, :memory_tracker_issues, issues)

    orchestrator_name = Module.concat(__MODULE__, :BoardOrchestrator)
    {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    # Inject a running entry for MT-200 directly into orchestrator state.
    issue_id = "id-in-progress"

    in_progress_issue =
      Enum.find(issues, &(&1.id == issue_id))

    initial_state = :sys.get_state(pid)

    running_entry = %{
      pid: self(),
      ref: make_ref(),
      identifier: in_progress_issue.identifier,
      issue: in_progress_issue,
      worker_host: nil,
      workspace_path: nil,
      session_id: "thread-test",
      turn_count: 3,
      last_codex_message: nil,
      last_codex_timestamp: DateTime.utc_now(),
      last_codex_event: :notification,
      codex_app_server_pid: nil,
      codex_input_tokens: 0,
      codex_output_tokens: 0,
      codex_total_tokens: 0,
      codex_last_reported_input_tokens: 0,
      codex_last_reported_output_tokens: 0,
      codex_last_reported_total_tokens: 0,
      retry_attempt: 0,
      started_at: DateTime.utc_now()
    }

    state_with_running =
      initial_state
      |> Map.put(:running, %{issue_id => running_entry})
      |> Map.put(:claimed, MapSet.put(initial_state.claimed, issue_id))

    :sys.replace_state(pid, fn _ -> state_with_running end)

    payload = Presenter.board_payload(orchestrator_name, 5_000)

    assert %{board: %{columns: columns, tracker_error: nil}} = payload

    column_names = Enum.map(columns, & &1.name)
    assert column_names == ["Todo", "In Progress", "Human Review", "Merging", "Rework", "Done", "Cancelled"]

    in_progress_column = Enum.find(columns, &(&1.name == "In Progress"))
    assert [card] = in_progress_column.cards
    assert card.issue_identifier == "MT-200"
    assert card.title == "Implement the feature"
    assert card.url == "https://example.org/MT-200"
    assert card.status == "running"
    assert card.running.turn_count == 3
    assert card.running.session_id == "thread-test"

    todo_column = Enum.find(columns, &(&1.name == "Todo"))
    assert [todo_card] = todo_column.cards
    assert todo_card.issue_identifier == "MT-100"
    assert todo_card.status == "idle"
    assert is_nil(todo_card.running)

    done_column = Enum.find(columns, &(&1.name == "Done"))
    assert [done_card] = done_column.cards
    assert done_card.issue_identifier == "MT-300"
    assert done_column.kind == "terminal"

    human_review_column = Enum.find(columns, &(&1.name == "Human Review"))
    assert human_review_column.cards == []
    assert human_review_column.kind == "active"
  end
end
