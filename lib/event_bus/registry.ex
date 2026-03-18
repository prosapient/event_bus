defmodule EventBus.Registry do
  @moduledoc """
  Registry for event handlers.

  Maintains a mapping of event types to their handlers. Handlers are registered
  via application configuration.

  ## Configuration

      config :event_bus, :handlers, %{
        MyApp.Orders.Events.OrderCreated => [
          MyApp.Finances.EventHandler,
          MyApp.Email.EventHandler
        ],
        MyApp.Payments.Events.PaymentReceived => [
          MyApp.Accounting.EventHandler
        ]
      }
  """

  require Logger

  @doc """
  Returns the list of handlers registered for the given event type.

  Returns an empty list if no handlers are registered for the event type.
  """
  @spec handlers_for(event_module :: module()) :: [module()]
  def handlers_for(event_module) do
    :event_bus
    |> Application.fetch_env!(:handlers)
    |> Map.get(event_module, [])
  end

  @doc """
  Returns handlers for an event struct that are interested in processing it.

  Filters out handlers whose `interested?/1` callback returns `false`.
  Logs a warning if no handlers are registered for the event type.
  """
  @spec handlers_for_event(event :: struct()) :: [module()]
  def handlers_for_event(event) do
    event_module = event.__struct__
    handlers = handlers_for(event_module)

    if handlers == [] do
      Logger.warning("No handlers registered for event: #{inspect(event_module)}")
    end

    Enum.filter(handlers, &EventBus.Handler.interested?(&1, event))
  end
end
