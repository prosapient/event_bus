defmodule EventBus.Backend.ProcessMailbox do
  @moduledoc """
  Backend that sends events to the owner test process via NimbleOwnership.

  Works with any process type (Task, GenServer, Agent, spawn, etc.)

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

  ## Cross-process support

  Events from Task-based processes automatically route to the test process.
  For GenServer/Agent/spawn, use `allow_event_bus/1`:

      {:ok, pid} = MyGenServer.start_link()
      allow_event_bus(pid)
  """

  @behaviour EventBus.Backend

  @impl EventBus.Backend
  def publish(event) do
    mode = EventBus.Testing.get_event_bus_mode()

    case mode do
      :inline ->
        EventBus.Backend.Inline.publish(event)

      mode when mode in [:default, :strict] ->
        owner = EventBus.Testing.get_owner()
        meta = %{strict: mode == :strict, stacktrace: get_stacktrace()}
        send(owner, {:event_published, event, meta})
    end

    :ok
  end

  defp get_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    # Drop internal frames: Process.info/2, get_stacktrace/0, publish/1
    Enum.drop(stacktrace, 3)
  end
end
