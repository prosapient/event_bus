defmodule EventBus.Backend.Inline do
  @moduledoc """
  Inline backend - executes handlers synchronously.

  Useful for development and seed scripts where you want immediate execution.

  Note: unlike the Oban backend, there are no retries. Errors in handlers
  will propagate to the caller.
  """

  @behaviour EventBus.Backend

  @impl EventBus.Backend
  def publish(events) when is_list(events) do
    Enum.each(events, fn event ->
      event
      |> EventBus.Registry.handlers_for_event()
      |> Enum.each(& &1.handle_event(event))
    end)

    :ok
  end

  def publish(event) do
    event
    |> EventBus.Registry.handlers_for_event()
    |> Enum.each(& &1.handle_event(event))

    :ok
  end
end
