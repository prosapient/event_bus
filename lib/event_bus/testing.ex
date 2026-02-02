defmodule EventBus.Testing do
  @moduledoc """
  Testing utilities for EventBus.

  Uses NimbleOwnership for reliable cross-process event tracking.
  Works with any process type (Task, GenServer, Agent, spawn, etc.)

  Import in your test modules or DataCase:

      import EventBus.Testing

  ## Setup

  Add to your test_helper.exs:

      EventBus.Testing.start_link()

  ## Usage

      test "completing call publishes event", ctx do
        %{call: call} = produce(ctx, [:call])  # default mode, not checked

        set_event_bus_mode(:strict)

        Engagements.complete_call(call, %{duration: 60})

        assert_event_published %CallCompleted{call_id: id}
        assert id == call.id
        # on_exit fails if any strict events left unasserted
      end

  ## Modes

  - `:default` - events sent to mailbox with `strict: false`, not checked in on_exit
  - `:strict` - events sent to mailbox with `strict: true`, on_exit fails if unasserted
  - `:inline` - handlers execute synchronously, nothing sent to mailbox

  ## Cross-process support

  Events published from Task-based processes automatically route to the test process
  (Task sets `$callers` in process dictionary).

  For other process types (GenServer, Agent, spawn), use `allow_event_bus/1`
  before the process publishes:

      test "genserver publishes events" do
        set_event_bus_mode(:strict)

        {:ok, pid} = MyGenServer.start_link()
        allow_event_bus(pid)

        MyGenServer.do_something(pid)

        assert_event_published %SomethingHappened{}
      end
  """

  import ExUnit.Assertions, only: [assert_received: 1]

  @ownership_server __MODULE__
  @ownership_key :event_bus_mode

  @type mode :: :default | :strict | :inline

  @doc """
  Starts the NimbleOwnership server for EventBus testing.

  Add to your test_helper.exs:

      EventBus.Testing.start_link()
  """
  @spec start_link() :: GenServer.on_start()
  def start_link do
    NimbleOwnership.start_link(name: @ownership_server)
  end

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker
    }
  end

  @doc """
  Sets the event bus mode for the current test process.

  - `:default` - events sent to mailbox with `strict: false`, not checked in on_exit
  - `:strict` - events sent to mailbox with `strict: true`, on_exit fails if unasserted
  - `:inline` - handlers execute synchronously, nothing sent to mailbox

  When switching from `:strict` to another mode, verifies no unasserted strict events.
  """
  @spec set_event_bus_mode(mode()) :: :ok
  def set_event_bus_mode(mode) when mode in [:default, :strict, :inline] do
    previous_mode = get_event_bus_mode()

    # When leaving strict mode, verify no unasserted events
    if previous_mode == :strict and mode != :strict do
      assert_no_pending_strict_events!()
    end

    # Set ownership of mode for this process
    NimbleOwnership.get_and_update(
      @ownership_server,
      self(),
      @ownership_key,
      fn _ -> {:ok, mode} end
    )

    :ok
  end

  @doc """
  Returns current event bus mode. Checks ownership chain via NimbleOwnership.

  Walks up $callers chain to find mode set by test process, falling back to :default.
  """
  @spec get_event_bus_mode() :: mode()
  def get_event_bus_mode do
    case fetch_owned_mode_for_caller() do
      {:ok, mode} -> mode
      :error -> :default
    end
  end

  @doc false
  @spec get_owner() :: pid()
  def get_owner do
    case NimbleOwnership.fetch_owner(@ownership_server, callers(), @ownership_key) do
      {:ok, owner_pid} -> owner_pid
      _ -> root_caller()
    end
  end

  defp fetch_owned_mode_for_caller do
    case NimbleOwnership.fetch_owner(@ownership_server, callers(), @ownership_key) do
      {:ok, owner_pid} -> fetch_owned_mode(owner_pid)
      _ -> :error
    end
  end

  defp fetch_owned_mode(owner_pid) do
    case NimbleOwnership.get_owned(@ownership_server, owner_pid, %{}) do
      %{@ownership_key => mode} when mode in [:default, :strict, :inline] -> {:ok, mode}
      _ -> :error
    end
  end

  defp callers do
    [self() | Process.get(:"$callers", [])]
  end

  defp root_caller do
    case Process.get(:"$callers", []) do
      [] -> self()
      callers -> List.last(callers)
    end
  end

  @doc """
  Allows a process to inherit event bus mode from the current test.

  Use this for processes not started via Task (GenServer, Agent, spawn, etc.)

  ## Example

      {:ok, pid} = MyGenServer.start_link()
      allow_event_bus(pid)
  """
  @spec allow_event_bus(pid()) :: :ok | {:error, term()}
  def allow_event_bus(pid) when is_pid(pid) do
    allow_event_bus(pid, self())
  end

  @doc """
  Allows a process with an explicit owner.

  Useful when setting up allowances from a setup block for a process
  that will be started later.

  ## Example

      # In setup
      test_pid = self()

      {:ok, pid} = MyGenServer.start_link()
      allow_event_bus(pid, test_pid)
  """
  @spec allow_event_bus(pid(), pid()) :: :ok | {:error, term()}
  def allow_event_bus(pid, owner_pid) when is_pid(pid) and is_pid(owner_pid) do
    case NimbleOwnership.allow(@ownership_server, owner_pid, pid, @ownership_key) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Asserts that a strict event matching the pattern was published.

  Only matches events published while in `:strict` mode.

  ## Example

      set_event_bus_mode(:strict)
      Engagements.complete_call(call, %{duration: 60})
      assert_event_published %CallCompleted{call_id: id}
  """
  defmacro assert_event_published(pattern) do
    quote do
      assert_received {:event_published, unquote(pattern), %{strict: true}}
    end
  end

  @doc """
  Verifies no unasserted strict events remain in mailbox.

  Called automatically when switching from `:strict` mode and in on_exit.
  """
  @spec assert_no_pending_strict_events!() :: :ok
  def assert_no_pending_strict_events! do
    strict_events = flush_strict_events()

    if strict_events != [] do
      formatted = format_pending_events(strict_events)
      raise "Unasserted events published in strict mode:\n\n#{formatted}"
    end

    :ok
  end

  defp flush_strict_events do
    receive do
      {:event_published, event, %{strict: true} = meta} ->
        [{event, meta} | flush_strict_events()]
    after
      0 -> []
    end
  end

  defp format_pending_events(events) do
    Enum.map_join(events, "\n", fn {event, meta} ->
      stacktrace = Map.get(meta, :stacktrace, [])
      formatted_stacktrace = Exception.format_stacktrace(stacktrace)

      """
        #{inspect(event)}
        Published at:
      #{formatted_stacktrace}
      """
    end)
  end

  @doc """
  Setup function to add on_exit hook. Call from your DataCase setup.

      setup :setup_event_bus_testing

  Or:

      setup do
        setup_event_bus_testing()
      end
  """
  @spec setup_event_bus_testing(map()) :: :ok
  def setup_event_bus_testing(_context \\ %{}) do
    ExUnit.Callbacks.on_exit(fn ->
      case fetch_owned_mode(self()) do
        {:ok, :strict} ->
          assert_no_pending_strict_events!()
          NimbleOwnership.cleanup_owner(@ownership_server, self())

        {:ok, _mode} ->
          NimbleOwnership.cleanup_owner(@ownership_server, self())

        :error ->
          :ok
      end
    end)

    :ok
  end
end
