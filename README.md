# EventBus

Internal event bus for decoupling domain logic across contexts.

Uses Oban for reliable, async event processing. Each event is dispatched to all registered handlers via separate Oban jobs, allowing independent processing, retries, and prioritization.

Works with both **Oban (OSS)** and **[Oban Pro](https://getoban.pro/)**. Pro is
detected automatically at compile time — if your project depends on `oban_pro`,
the Pro-flavored worker is used; otherwise, the OSS-flavored worker is used. See
[Oban Pro vs Oban (OSS)](#oban-pro-vs-oban-oss) for the trade-offs of each mode.

## Installation

Add `event_bus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:event_bus, github: "prosapient/event_bus", tag: "v0.1.0"}
  ]
end
```

If you want to use Oban Pro, add it to your own deps as well. You'll need an
active Oban license and the `oban` Hex repo authenticated locally:

```bash
mix hex.repo add oban https://getoban.pro/repo \
  --fetch-public-key SHA256:4/OSKi0NRF91QVVXlGAhb/BIMLnK8NHcx/EWs+aIWPc \
  --auth-key YOUR_OBAN_LICENSE_KEY
```

```elixir
def deps do
  [
    {:event_bus, github: "prosapient/event_bus", tag: "v0.1.0"},
    {:oban_pro, "~> 1.5", repo: "oban"}
  ]
end
```

## Usage

### 1. Define an event

Events are structs defined in the context that publishes them:

```elixir
defmodule MyApp.Orders.Events.OrderCreated do
  defstruct [:order_id, :customer_id, :total]
end
```

### 2. Define a handler

```elixir
defmodule MyApp.Finances.EventHandler do
  @behaviour EventBus.Handler

  @impl EventBus.Handler
  def handle_event(%MyApp.Orders.Events.OrderCreated{} = event) do
    MyApp.Finances.create_invoice(event.order_id)
    :ok
  end
end
```

### 3. Register handlers

```elixir
# config/event_handlers.exs
%{
  MyApp.Orders.Events.OrderCreated => [MyApp.Finances.EventHandler]
}

# config/runtime.exs
{handlers, _} = Code.eval_file("config/event_handlers.exs")
config :event_bus, :handlers, handlers
```

### 4. Configure Oban queues

With **Oban Pro** (cluster-wide ordering per partition key via Smart Engine):

```elixir
# config/config.exs
config :my_app, Oban,
  queues: [
    # ... other queues ...
    events: 20,
    events_partitioned: [
      local_limit: 20,
      global_limit: [allowed: 1, partition: [fields: [:args], keys: [:partition_key]]]
    ]
  ]
```

With **Oban (OSS)** — ordering only guaranteed within a single node:

```elixir
# config/config.exs
config :my_app, Oban,
  queues: [
    # ... other queues ...
    events: 20,
    events_partitioned: [local_limit: 1]
  ]
```

### 5. Publish events

```elixir
EventBus.publish(%MyApp.Orders.Events.OrderCreated{order_id: "123", customer_id: "456", total: 100})
```

## Handler options

### Event filtering

Handlers can implement `interested?/1` to skip events before an Oban job is created.
This avoids the database write entirely when the event data is sufficient to determine
that the handler has nothing to do.

```elixir
defmodule MyApp.Finances.EventHandler do
  @behaviour EventBus.Handler

  # Only handle orders above zero total
  @impl EventBus.Handler
  def interested?(%MyApp.Orders.Events.OrderCreated{total: total}), do: total > 0

  @impl EventBus.Handler
  def handle_event(%MyApp.Orders.Events.OrderCreated{} = event) do
    MyApp.Finances.create_invoice(event.order_id)
    :ok
  end
end
```

`interested?/1` **must be a pure function** — no database queries, API calls, or side effects.
It runs synchronously in the publishing process (which may be inside an Ecto transaction).

When not implemented, defaults to `true` (all events are processed).

### Oban options

Handlers can customize Oban worker options:

```elixir
defmodule MyApp.Finances.EventHandler do
  @behaviour EventBus.Handler

  @impl EventBus.Handler
  def handle_event(%MyApp.Orders.Events.OrderCreated{} = event) do
    # ...
    :ok
  end

  @impl EventBus.Handler
  def oban_options do
    [priority: 3, max_attempts: 10]
  end
end
```

Available options: `:priority` (0-9, lower is higher, default: 0), `:max_attempts` (default: 5).

## Partitioning

Events for the same entity can be processed sequentially by implementing `EventBus.Partitioned`:

```elixir
defmodule MyApp.Orders.Events.OrderCreated do
  defstruct [:order_id, :customer_id, :total]

  defimpl EventBus.Partitioned do
    def partition_key(%{order_id: id}), do: id
  end
end
```

- Events with partition key go to `:events_partitioned` queue (sequential per key)
- Events without partition key go to `:events` queue (parallel)

## Return values

- `:ok` or `{:ok, result}` - success
- `{:error, reason}` - triggers Oban retry
- raising an exception - triggers Oban retry

## Oban Pro vs Oban (OSS)

`EventBus` detects Oban Pro at compile time. If your project depends on
`oban_pro`, the Pro-flavored worker is compiled; otherwise the OSS-flavored
worker is. The detection uses `Code.ensure_loaded?(Oban.Pro.Worker)`, evaluated
once when `event_bus` is compiled.

The public API (`EventBus.publish/1`, handler behaviour, partition protocol,
testing helpers) is identical in both modes. The differences are internal:

| Feature | Oban Pro | Oban (OSS) |
|---|---|---|
| Worker | `Oban.Pro.Worker` with `args_schema` and `:term` field | `Oban.Worker` |
| Event serialization | Native Elixir term via `:term` schema field | `:erlang.term_to_binary/1` + Base64 |
| Job UI readability | Event readable in the Oban dashboard | Event displayed as opaque base64 blob |
| Per-partition ordering | Cluster-wide (Smart Engine `global_limit` with partition) | Single-node only (`local_limit: 1`) |

Both modes preserve all Elixir types — atoms, structs, tuples,
`Decimal`/`DateTime`/custom types — so handlers receive the original event
struct exactly as published, regardless of which mode is active. Migrating
between modes does not require any handler changes.

### Per-partition ordering caveat in OSS

In Pro mode, the `:events_partitioned` queue uses Smart Engine's partitioned
`global_limit` to guarantee that events with the same `partition_key` are
processed strictly sequentially across the entire cluster. Oban OSS does not
have an equivalent feature.

In OSS mode, configuring `events_partitioned` with `local_limit: 1` only
guarantees ordering **within a single node**. If you run multiple Oban nodes,
two events with the same `partition_key` may be picked up concurrently by
different nodes. Consider this when designing handlers — make them idempotent
and tolerant of out-of-order delivery, or use Oban Pro if strict cluster-wide
ordering is required.

## Testing

### Setup

```elixir
# config/test.exs
config :event_bus, :backend, EventBus.Backend.ProcessMailbox

# test/test_helper.exs
EventBus.Testing.start_link()
ExUnit.start()

# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import EventBus.Testing
      setup :setup_event_bus_testing
    end
  end
end
```

### Test handlers with `run_event!/2`

`run_event!/2` runs an event through a specific handler, checking `interested?/1` first.
It executes synchronously and returns the result directly.

```elixir
# Handler processes the event
event = %OrderCreated{order_id: "123", customer_id: "456", total: 100}
assert :processed = run_event!(event, MyApp.Finances.EventHandler)

# Handler returns a value
assert {:processed, invoice} = run_event!(event, MyApp.Finances.EventHandler)
assert invoice.order_id == "123"

# Handler is not interested (interested?/1 returned false)
event = %OrderCreated{order_id: "123", customer_id: "456", total: 0}
assert :not_interested = run_event!(event, MyApp.Finances.EventHandler)
```

The non-bang version `run_event/2` returns `{:ok, result}` or `{:error, reason}` instead of raising:

```elixir
assert {:ok, :processed} = run_event(event, MyApp.Finances.EventHandler)
assert {:error, :insufficient_funds} = run_event(event, MyApp.Finances.EventHandler)
```

### Test event publishing with strict mode

Use `set_event_bus_mode(:strict)` to enable assertion checking. Events published in strict mode must be asserted, otherwise the test fails in `on_exit`.

```elixir
test "completing call publishes event", ctx do
  %{call: call} = produce(ctx, [:call])  # default mode, not checked

  set_event_bus_mode(:strict)

  Engagements.complete_call(call, %{duration: 60})

  assert_event_published %CallCompleted{call_id: id}
  assert id == call.id
  # on_exit fails if any strict events left unasserted
end
```

### Modes

- `:default` - events sent to mailbox but not checked (for seed factory noise)
- `:strict` - events must be asserted, on_exit fails if any left unasserted
- `:inline` - handlers execute synchronously (for integration tests)

### Integration test with inline mode

When you need handlers to actually execute:

```elixir
test "completing call creates invoice via handler", ctx do
  %{call: call} = produce(ctx, [:call])

  set_event_bus_mode(:inline)

  Engagements.complete_call(call, %{duration: 60})

  # handler already executed, check side effects
  assert Finances.invoice_line_item_exists_for_call?(call.id)
end
```

### Switching modes mid-test

```elixir
test "complex scenario", ctx do
  %{expert: expert, project: project} = produce(ctx, [:expert, :project])

  set_event_bus_mode(:strict)
  {:ok, call} = Engagements.schedule_call(expert, project, params)
  assert_event_published %CallScheduled{}

  set_event_bus_mode(:default)  # verifies no unasserted strict events, then switches

  # these events not checked
  Engagements.add_participants(call, participants)

  set_event_bus_mode(:strict)
  Engagements.complete_call(call, %{duration: 60})
  assert_event_published %CallCompleted{}
end
```

### Cross-process support

Events published from Task-based processes automatically route to the test process.
For other process types (GenServer, Agent, spawn), use `allow_event_bus/1` before the process publishes:

```elixir
test "genserver publishes events" do
  set_event_bus_mode(:strict)

  {:ok, pid} = MyGenServer.start_link()
  allow_event_bus(pid)

  MyGenServer.do_something(pid)

  assert_event_published %SomethingHappened{}
end
```

### Inline backend for dev/seeds

`EventBus.Backend.Inline` executes handlers synchronously - useful for development and seed scripts:

```elixir
# config/dev.exs
config :event_bus, :backend, EventBus.Backend.Inline
```
