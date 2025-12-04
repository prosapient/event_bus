defmodule EventBus.Worker do
  @moduledoc """
  Oban worker that dispatches events to handlers.

  Used by `EventBus.Backend.Oban`.

  One job is created per handler per event. This allows handlers
  to process independently with their own retry logic and priority.

  Events are serialized using Oban.Pro.Worker's `:term` type, which preserves
  Elixir types like atoms, structs, Money.t(), etc.
  """

  use Oban.Pro.Worker,
    queue: :events,
    max_attempts: 5

  args_schema do
    field(:event, :term, required: true)
    field(:handler, :string, required: true)
  end

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %__MODULE__{} = args}) do
    handler_module = Module.safe_concat([args.handler])

    handler_module.handle_event(args.event)
  end

  @doc """
  Creates a new worker job for dispatching an event to a handler.

  Handler can override default options by implementing `oban_options/0`.
  """
  @spec new_for_handler(struct(), module()) :: Oban.Job.changeset()
  def new_for_handler(event, handler_module) do
    args = %{
      event: event,
      handler: inspect(handler_module)
    }

    opts =
      handler_module
      |> handler_opts()
      |> Keyword.put(:meta, %{event_module: inspect(event.__struct__)})

    new(args, opts)
  end

  defp handler_opts(handler_module) do
    if function_exported?(handler_module, :oban_options, 0) do
      handler_module.oban_options()
    else
      []
    end
  end
end
