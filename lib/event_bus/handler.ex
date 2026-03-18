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

        # Optional: skip events that don't need processing
        @impl EventBus.Handler
        def interested?(%MyApp.Orders.Events.OrderCreated{total: total}) do
          total > 0
        end

        # Optional: customize Oban options
        @impl EventBus.Handler
        def oban_options do
          [priority: 0, max_attempts: 10]
        end
      end

  ## Event Filtering

  Handlers can optionally implement `interested?/1` to reject events before an
  Oban job is created. This is a performance optimization that avoids unnecessary
  database writes when the event data alone is sufficient to determine that
  the handler has nothing to do.

  **This must be a pure function** — it receives only the event struct and must
  return a boolean based solely on the event's fields. It must not perform
  database queries, API calls, or any side effects, because it runs synchronously
  in the publishing process (which may be inside an Ecto transaction).

  When not implemented, defaults to `true` (all events are processed).

  ## Oban Options

  Handlers can optionally customize their Oban worker behavior via `oban_options/0`:

  - `:priority` - Job priority, 0-9 where 0 is highest (default: 0)
  - `:max_attempts` - Maximum retry attempts (default: 5)

  Note: `:queue` is determined automatically based on event's partition key.

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
  Returns whether this handler is interested in processing the given event.

  Called before creating an Oban job. If it returns `false`, no job is enqueued
  for this handler, avoiding the database write entirely.

  This is useful when the event struct contains enough information to determine
  that the handler has nothing to do — for example, filtering by a status field
  or a source identifier.

  **Must be a pure function.** It runs synchronously in the publishing process
  and must not perform database queries, API calls, or any side effects.

  Optional callback. Defaults to `true` when not implemented.
  """
  @callback interested?(event :: struct()) :: boolean()

  @doc """
  Returns Oban worker options for this handler.

  Used by `EventBus.Backend.Oban`. Ignored by other backends (e.g., Inline).

  Optional callback. If not implemented, defaults from `EventBus.Worker` are used.
  """
  @callback oban_options() :: keyword()

  @optional_callbacks interested?: 1, oban_options: 0

  @doc """
  Returns whether the handler is interested in the given event.

  Checks if the handler implements `interested?/1` and calls it.
  Returns `true` if the callback is not implemented.
  """
  @spec interested?(module(), struct()) :: boolean()
  def interested?(handler_module, event) do
    if Code.ensure_loaded?(handler_module) and
         function_exported?(handler_module, :interested?, 1) do
      handler_module.interested?(event)
    else
      true
    end
  end
end
