defmodule EventBus.WorkerTest do
  use ExUnit.Case, async: true

  alias EventBus.TestSupport.PartitionedEvent
  alias EventBus.TestSupport.TestHandler
  alias EventBus.TestSupport.UnpartitionedEvent
  alias EventBus.TestSupport.WorkerHelpers
  alias EventBus.Worker

  describe "new_for_handler/2" do
    test "uses :events_partitioned queue for events with partition key" do
      event = %PartitionedEvent{entity_id: "123", data: "test"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert job.queue == "events_partitioned"
      assert WorkerHelpers.arg(job, :partition_key) == "123"
    end

    test "uses :events queue for events without partition key" do
      event = %UnpartitionedEvent{data: "test"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert job.queue == "events"
      refute WorkerHelpers.has_arg?(job, :partition_key)
    end

    test "stores handler in args" do
      event = %PartitionedEvent{entity_id: "abc", data: "payload"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert WorkerHelpers.arg(job, :handler) == "EventBus.TestSupport.TestHandler"
    end

    test "stores event module in meta" do
      event = %PartitionedEvent{entity_id: "123", data: "test"}

      changeset = Worker.new_for_handler(event, TestHandler)
      job = Ecto.Changeset.apply_changes(changeset)

      assert job.meta.event_module == "EventBus.TestSupport.PartitionedEvent"
    end
  end
end
