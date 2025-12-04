defmodule EventBus.TestSupport.TestHandler do
  @moduledoc """
  A test handler that tracks received events.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def handle_event(%TestEvent{} = event) do
    # Store in process dictionary for inline mode testing
    Process.put(:last_handled_event, event)
    send(self(), {:handled, __MODULE__, event})
    :ok
  end

  @impl true
  def oban_options do
    [queue: :test_events, priority: 1, max_attempts: 3]
  end
end

defmodule EventBus.TestSupport.AnotherHandler do
  @moduledoc """
  Another test handler for testing multiple handlers.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def handle_event(%TestEvent{} = event) do
    send(self(), {:handled, __MODULE__, event})
    :ok
  end

  @impl true
  def oban_options do
    [queue: :test_events, priority: 2, max_attempts: 5]
  end
end

defmodule EventBus.TestSupport.FailingHandler do
  @moduledoc """
  A handler that always fails for testing error handling.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def handle_event(%TestEvent{}) do
    {:error, :intentional_failure}
  end

  @impl true
  def oban_options do
    [queue: :test_events, max_attempts: 1]
  end
end

defmodule EventBus.TestSupport.CrashingHandler do
  @moduledoc """
  A handler that raises an exception for testing error handling.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def handle_event(%TestEvent{}) do
    raise "Intentional crash"
  end

  @impl true
  def oban_options do
    [queue: :test_events, max_attempts: 1]
  end
end
