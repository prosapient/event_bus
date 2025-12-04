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
