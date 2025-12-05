defmodule EventBus do
  @moduledoc """
  Internal event bus for decoupling domain logic across contexts.

  Uses Oban for reliable, async event processing. Each event is dispatched
  to all registered handlers via separate Oban jobs, allowing independent
  processing, retries, and prioritization.

  ## Usage

      # Define an event in the context that publishes it
      defmodule MyApp.Orders.Events.OrderCreated do
        defstruct [:order_id, :customer_id, :total]
      end

      # Define a handler in the context that reacts to the event
      defmodule MyApp.Finances.EventHandler do
        @behaviour EventBus.Handler

        @impl EventBus.Handler
        def handle_event(%MyApp.Orders.Events.OrderCreated{} = event) do
          MyApp.Finances.create_invoice(event.order_id)
          :ok
        end
      end

      # Register handlers in config
      config :event_bus, :handlers, %{
        MyApp.Orders.Events.OrderCreated => [MyApp.Finances.EventHandler]
      }

      # Publish events
      EventBus.publish(%MyApp.Orders.Events.OrderCreated{order_id: "123", customer_id: "456", total: 100})
  """

  require Logger

  @doc """
  Publishes a domain event to all registered handlers.

  Events are processed asynchronously via Oban workers. Each registered
  handler receives its own Oban job, allowing independent processing and retries.

  Returns `:ok` immediately after enqueueing all handler jobs.

  ## Examples

      EventBus.publish(%OrderCreated{order_id: "123"})
  """

  @spec publish(event :: struct()) :: :ok
  def publish(event) do
    Logger.debug("EventBus publishing #{inspect(event.__struct__)}")
    backend().publish(event)
  end

  @doc """
  Returns the currently configured backend module.
  """
  @spec backend() :: module()
  def backend do
    Application.get_env(:event_bus, :backend, EventBus.Backend.Oban)
  end
end
