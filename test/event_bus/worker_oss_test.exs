defmodule EventBus.WorkerOssTest do
  use ExUnit.Case, async: true

  @moduletag :oss

  alias EventBus.TestSupport.PartitionedEvent
  alias EventBus.TestSupport.TestEvent
  alias EventBus.TestSupport.TestHandler
  alias EventBus.Worker

  describe "args encoding (OSS)" do
    test "event field is base64-encoded binary term" do
      event = %TestEvent{id: "abc", data: "payload"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      encoded = job.args["event"]
      assert is_binary(encoded)

      decoded =
        encoded
        |> Base.decode64!()
        |> :erlang.binary_to_term([:safe])

      assert decoded == event
    end

    test "args use string keys" do
      event = %PartitionedEvent{entity_id: "id-1", data: "x"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert Map.has_key?(job.args, "event")
      assert Map.has_key?(job.args, "handler")
      assert Map.has_key?(job.args, "partition_key")

      refute Map.has_key?(job.args, :event)
      refute Map.has_key?(job.args, :handler)
      refute Map.has_key?(job.args, :partition_key)
    end

    test "preserves atoms, structs and other Elixir types in event" do
      datetime = ~U[2026-05-08 12:00:00Z]
      decimal = Decimal.new("99.50")

      event = %TestEvent{
        id: "rich",
        data: %{status: :pending, total: decimal, placed_at: datetime}
      }

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      decoded =
        job.args["event"]
        |> Base.decode64!()
        |> :erlang.binary_to_term([:safe])

      assert %TestEvent{} = decoded
      assert decoded.data.status == :pending
      assert decoded.data.total == decimal
      assert decoded.data.placed_at == datetime
    end
  end

  describe "perform/1 (OSS)" do
    test "decodes event and dispatches to handler" do
      event = %TestEvent{id: "perform-1", data: "ok"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert :ok = Worker.perform(job)

      assert_received {:handled, TestHandler, ^event}
    end

    test "round-trips structs preserving identity" do
      event = %TestEvent{id: "rt", data: %{nested: :atom}}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      Worker.perform(job)

      assert_received {:handled, TestHandler, ^event}
      assert Process.get(:last_handled_event) == event
    end
  end
end
