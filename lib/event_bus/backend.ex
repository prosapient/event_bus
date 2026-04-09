defmodule EventBus.Backend do
  @moduledoc """
  Behaviour for event bus backend.

  ## Implementations

  - `EventBus.Backend.Oban` - Default production backend. Dispatches events to handlers
    via Oban jobs for reliable async processing with retries.

  - `EventBus.Backend.Inline` - Executes handlers synchronously. Useful for development
    and seed scripts where you want immediate execution without Oban.

  - `EventBus.Backend.ProcessMailbox` - Sends events to test process mailbox. Used with
    `EventBus.Testing` helpers for testing event publishing.

  ## Configuration

      # config/runtime.exs (production)
      config :event_bus, :backend, EventBus.Backend.Oban

      # config/dev.exs
      config :event_bus, :backend, EventBus.Backend.Inline

      # config/test.exs
      config :event_bus, :backend, EventBus.Backend.ProcessMailbox
  """

  @callback publish(event :: struct() | [struct()]) :: :ok
end
