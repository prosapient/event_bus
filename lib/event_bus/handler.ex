defmodule EventBus.Handler do
  @moduledoc """
  Behaviour for event handlers.

  Handlers react to domain events independently. Each handler processes events
  in its own Oban worker, allowing for parallel processing and independent retries.

  ## Usage

      defmodule MyApp.Finances.EventHandler do
        @behaviour EventBus.Handler

        @impl EventBus.Handler
        def handle_event(%MyApp.Orders.Events.OrderCreated{} = event) do
          MyApp.Finances.create_invoice(event.order_id, event.total)
          :ok
        end

        # Optional: customize Oban options
        @impl EventBus.Handler
        def oban_options do
          [queue: :critical_events, priority: 0, max_attempts: 10]
        end
      end

  ## Oban Options

  Handlers can optionally customize their Oban worker behavior via `oban_options/0`:

  - `:queue` - The Oban queue to use (default: `:events`)
  - `:priority` - Job priority, 0-9 where 0 is highest
  - `:max_attempts` - Maximum retry attempts (default: 5)

  ## Idempotency

  Handlers may be executed multiple times (retries, crashes). Design them to be
  safe to run repeatedly.

  ## Error Handling

  - Return `:ok` or `{:ok, result}` on success
  - Return `{:error, reason}` to trigger Oban retry
  - Raise exceptions for unexpected errors (Oban will catch and retry)
  """

  @doc """
  Handles a domain event.

  Called by `EventBus.Worker` when processing an event for this handler.

  Returns `:ok` or `{:ok, result}` on success, `{:error, reason}` to trigger retry.
  `{:ok, result}` is useful for unit testing handlers directly.
  """
  @callback handle_event(event :: struct()) :: :ok | {:ok, term()} | {:error, term()}

  @doc """
  Returns Oban worker options for this handler.

  Used by `EventBus.Backend.Oban`. Ignored by other backends (e.g., Inline).

  Optional callback. If not implemented, defaults from `EventBus.Worker` are used.
  """
  @callback oban_options() :: keyword()

  @optional_callbacks oban_options: 0
end
