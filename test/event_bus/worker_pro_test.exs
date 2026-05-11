if Code.ensure_loaded?(Oban.Pro.Worker) do
  defmodule EventBus.WorkerProTest do
    use ExUnit.Case, async: true

    @moduletag :pro

    alias EventBus.TestSupport.PartitionedEvent
    alias EventBus.TestSupport.TestEvent
    alias EventBus.TestSupport.TestHandler
    alias EventBus.Worker

    describe "args encoding (Pro)" do
      test "args use atom keys (args_schema)" do
        event = %PartitionedEvent{entity_id: "id-1", data: "x"}

        changeset = Worker.new_for_handler(event, TestHandler)
        job = Ecto.Changeset.apply_changes(changeset)

        assert Map.has_key?(job.args, :event)
        assert Map.has_key?(job.args, :handler)
        assert Map.has_key?(job.args, :partition_key)
      end
    end

    describe "process/1 (Pro)" do
      test "dispatches event to handler" do
        event = %TestEvent{id: "process-1", data: "ok"}

        args = %Worker{
          event: event,
          handler: "EventBus.TestSupport.TestHandler",
          partition_key: nil
        }

        job = %Oban.Job{args: args}

        assert :ok = Worker.process(job)

        assert_received {:handled, TestHandler, ^event}
      end

      test "preserves atoms, structs and other Elixir types in dispatched event" do
        datetime = ~U[2026-05-08 12:00:00Z]
        decimal = Decimal.new("99.50")

        event = %TestEvent{
          id: "rich",
          data: %{status: :pending, total: decimal, placed_at: datetime}
        }

        args = %Worker{
          event: event,
          handler: "EventBus.TestSupport.TestHandler",
          partition_key: nil
        }

        job = %Oban.Job{args: args}

        Worker.process(job)

        assert_received {:handled, TestHandler, dispatched}
        assert dispatched == event
        assert dispatched.data.status == :pending
        assert dispatched.data.total == decimal
        assert dispatched.data.placed_at == datetime
      end
    end
  end
end
