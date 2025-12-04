defmodule EventBus.Backend.ProcessMailbox do
  @moduledoc """
  Backend that sends events to the root caller's mailbox.

  Useful for testing - use `EventBus.Testing` helpers to verify events.

  Uses `$callers` to find the root process when called from spawned processes
  (Task, GenServer, etc.), so assertions work even with nested async code.

  ## Modes

  Reads mode from `EventBus.Testing.get_event_bus_mode/0`:

  - `:default` - sends event with `strict: false`
  - `:strict` - sends event with `strict: true` (checked in on_exit)
  - `:inline` - executes handlers synchronously, nothing sent to mailbox

  ## Example

      import EventBus.Testing

      test "publishes event", ctx do
        %{call: call} = produce(ctx, [:call])  # default mode, not checked

        set_event_bus_mode(:strict)

        Engagements.complete_call(call, %{duration: 60})

        assert_event_published %CallCompleted{call_id: id}
      end
  """

  @behaviour EventBus.Backend

  @impl EventBus.Backend
  def publish(event) do
    mode = EventBus.Testing.get_event_bus_mode()

    case mode do
      :inline ->
        EventBus.Backend.Inline.publish(event)

      mode when mode in [:default, :strict] ->
        meta = %{strict: mode == :strict, stacktrace: get_stacktrace()}
        send(root_caller(), {:event_published, event, meta})
    end

    :ok
  end

  defp root_caller do
    case Process.get(:"$callers", []) do
      [] -> self()
      callers -> List.last(callers)
    end
  end

  defp get_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    # Drop internal frames: Process.info/2, get_stacktrace/0, publish/1
    Enum.drop(stacktrace, 3)
  end
end
