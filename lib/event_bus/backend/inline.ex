defmodule EventBus.Backend.Inline do
  @moduledoc """
  Inline backend - executes handlers synchronously.

  Useful for development and seed scripts where you want immediate execution.

  Note: unlike the Oban backend, there are no retries. Errors in handlers
  will propagate to the caller.
  """

  @behaviour EventBus.Backend

  @impl EventBus.Backend
  def publish(event) do
    handlers = EventBus.Registry.handlers_for_event(event)
    Enum.each(handlers, & &1.handle_event(event))
    :ok
  end
end
