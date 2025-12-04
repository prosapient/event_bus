defmodule EventBus.Testing do
  @moduledoc """
  Testing utilities for EventBus.

  Import in your test modules or DataCase:

      import EventBus.Testing

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
  """

  import ExUnit.Assertions, only: [assert_received: 1]

  @type mode :: :default | :strict | :inline

  @doc """
  Sets the event bus mode for the current test process.

  - `:default` - events sent to mailbox with `strict: false`, not checked in on_exit
  - `:strict` - events sent to mailbox with `strict: true`, on_exit fails if unasserted
  - `:inline` - handlers execute synchronously, nothing sent to mailbox

  When switching from `:strict` to another mode, verifies no unasserted strict events.
  """
  def set_event_bus_mode(mode) when mode in [:default, :strict, :inline] do
    previous_mode = Process.get(:event_bus_mode, :default)

    # When leaving strict mode, verify no unasserted events
    if previous_mode == :strict and mode != :strict do
      assert_no_pending_strict_events!()
    end

    Process.put(:event_bus_mode, mode)
    :ok
  end

  @doc """
  Returns current event bus mode. Walks up $callers chain to find mode set by test process.
  """
  def get_event_bus_mode do
    case Process.get(:event_bus_mode) do
      nil -> get_mode_from_callers()
      mode -> mode
    end
  end

  defp get_mode_from_callers do
    case Process.get(:"$callers") do
      [_ | _] = callers ->
        Enum.find_value(callers, :default, fn pid ->
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} -> Keyword.get(dict, :event_bus_mode)
            nil -> nil
          end
        end)

      _ ->
        :default
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
  def setup_event_bus_testing(_context \\ %{}) do
    ExUnit.Callbacks.on_exit(fn ->
      if Process.get(:event_bus_mode) == :strict do
        assert_no_pending_strict_events!()
      end
    end)

    :ok
  end
end
