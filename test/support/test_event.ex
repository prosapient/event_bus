defmodule EventBus.TestSupport.TestEvent do
  @moduledoc """
  A test event for use in EventBus tests.
  """
  defstruct [:id, :data]
end

defmodule EventBus.TestSupport.AnotherEvent do
  @moduledoc """
  Another test event for use in EventBus tests.
  """
  defstruct [:id]
end

defmodule EventBus.TestSupport.PartitionedEvent do
  @moduledoc """
  A test event with partition key implementation.
  """
  defstruct [:entity_id, :data]

  defimpl EventBus.Partitioned do
    def partition_key(%{entity_id: id}), do: id
  end
end

defmodule EventBus.TestSupport.UnpartitionedEvent do
  @moduledoc """
  A test event without partition key (uses fallback to Any).
  """
  defstruct [:data]
end
