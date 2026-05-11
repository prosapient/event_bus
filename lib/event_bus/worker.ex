defmodule EventBus.Worker.Helpers do
  @moduledoc false

  @spec build_opts(module(), String.t() | nil, struct()) :: keyword()
  def build_opts(handler_module, partition_key, event) do
    handler_module
    |> handler_opts()
    |> Keyword.put(:meta, %{event_module: inspect(event.__struct__)})
    |> Keyword.put(:queue, queue_for_partition(partition_key))
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

if Code.ensure_loaded?(Oban.Pro.Worker) do
  defmodule EventBus.Worker do
    @moduledoc """
    Oban worker that dispatches events to handlers (Oban Pro path).

    Used by `EventBus.Backend.Oban`.

    One job is created per handler per event. This allows handlers
    to process independently with their own retry logic and priority.

    Events are serialized using `Oban.Pro.Worker`'s `:term` type, which preserves
    Elixir types like atoms, structs, `Money.t()`, etc.

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
    - With partition key: `:events_partitioned` (sequential per key, cluster-wide)
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

      opts = EventBus.Worker.Helpers.build_opts(handler_module, partition_key, event)

      new(args, opts)
    end
  end
else
  defmodule EventBus.Worker do
    @moduledoc """
    Oban worker that dispatches events to handlers (Oban OSS path).

    Used by `EventBus.Backend.Oban`.

    One job is created per handler per event. This allows handlers
    to process independently with their own retry logic and priority.

    Since Oban OSS only supports JSON-serializable args, events are encoded
    using `:erlang.term_to_binary/1` + `Base.encode64/1` and stored as a string
    under the `"event"` key. This preserves all Elixir types (atoms, structs,
    tuples, custom types) at the cost of being opaque in the Oban UI.

    Decoding uses `:erlang.binary_to_term/2` with the `:safe` flag, which
    refuses to create new atoms at runtime.

    ## Queue Selection

    Queue is determined automatically based on event's partition key:

    - Events with partition key go to `:events_partitioned` queue (sequential per key
      within a single node — Oban OSS cannot enforce cluster-wide ordering)
    - Events without partition key go to `:events` queue (parallel)
    """

    use Oban.Worker, max_attempts: 5

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"event" => encoded, "handler" => handler}}) do
      event =
        encoded
        |> Base.decode64!()
        |> :erlang.binary_to_term([:safe])

      handler_module = Module.safe_concat([handler])

      handler_module.handle_event(event)
    end

    @doc """
    Creates a new worker job for dispatching an event to a handler.

    Queue is determined by event's partition key:
    - With partition key: `:events_partitioned` (sequential per key, single-node only)
    - Without partition key: `:events` (parallel)

    Handler can customize priority/max_attempts via `oban_options/0`.
    """
    @spec new_for_handler(struct(), module()) :: Oban.Job.changeset()
    def new_for_handler(event, handler_module) do
      partition_key = EventBus.Partitioned.partition_key(event)

      base_args = %{
        "event" => event |> :erlang.term_to_binary() |> Base.encode64(),
        "handler" => inspect(handler_module)
      }

      args =
        case partition_key do
          nil -> base_args
          key -> Map.put(base_args, "partition_key", key)
        end

      opts = EventBus.Worker.Helpers.build_opts(handler_module, partition_key, event)

      new(args, opts)
    end
  end
end
