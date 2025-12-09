defmodule EventBus.PartitionedTest do
  use ExUnit.Case, async: true

  alias EventBus.Partitioned
  alias EventBus.TestSupport.PartitionedEvent
  alias EventBus.TestSupport.UnpartitionedEvent

  describe "partition_key/1" do
    test "returns partition key for events with implementation" do
      event = %PartitionedEvent{entity_id: "123", data: "test"}
      assert Partitioned.partition_key(event) == "123"
    end

    test "returns nil for events without implementation (fallback to Any)" do
      event = %UnpartitionedEvent{data: "test"}
      assert Partitioned.partition_key(event) == nil
    end
  end
end
