defmodule EventBus.Worker do
  @moduledoc """
  Oban worker that dispatches events to handlers.

  Used by `EventBus.Backend.Oban`.

  One job is created per handler per event. This allows handlers
  to process independently with their own retry logic and priority.

  Events are serialized using Oban.Pro.Worker's `:term` type, which preserves
  Elixir types like atoms, structs, Money.t(), etc.

  ## Queue Selection

  Queue is determined automatically based on event's partition key:

  - Events with partition key go to `:events_partitioned` queue (sequential per key)
  - Events without partition key go to `:events` queue (parallel)
  """

  use Oban.Pro.Worker, max_attempts: 5

  args_schema do
    field(:event, :term, required: true)
    field(:handler, :string, required: true)
    field(:partition_key, :string)
  end

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %__MODULE__{} = args}) do
    handler_module = Module.safe_concat([args.handler])

    handler_module.handle_event(args.event)
  end

  @doc """
  Creates a new worker job for dispatching an event to a handler.

  Queue is determined by event's partition key:
  - With partition key: `:events_partitioned` (sequential per key)
  - Without partition key: `:events` (parallel)

  Handler can customize priority/max_attempts via `oban_options/0`.
  """
  @spec new_for_handler(struct(), module()) :: Oban.Job.changeset()
  def new_for_handler(event, handler_module) do
    partition_key = EventBus.Partitioned.partition_key(event)

    args = %{
      event: event,
      handler: inspect(handler_module),
      partition_key: partition_key
    }

    opts =
      handler_module
      |> handler_opts()
      |> Keyword.put(:meta, %{event_module: inspect(event.__struct__)})
      |> Keyword.put(:queue, queue_for_partition(partition_key))

    new(args, opts)
  end

  defp handler_opts(handler_module) do
    if function_exported?(handler_module, :oban_options, 0) do
      handler_module.oban_options()
    else
      []
    end
  end

  defp queue_for_partition(nil), do: :events
  defp queue_for_partition(_), do: :events_partitioned
end
