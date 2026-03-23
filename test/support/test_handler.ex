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
end

defmodule EventBus.TestSupport.SelectiveHandler do
  @moduledoc """
  A handler that only processes events with specific data.
  Used for testing the `interested?/1` callback.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def interested?(%TestEvent{data: "relevant"}), do: true
  def interested?(%TestEvent{}), do: false

  @impl true
  def handle_event(%TestEvent{} = event) do
    send(self(), {:handled, __MODULE__, event})
    :ok
  end
end

defmodule EventBus.TestSupport.ResultHandler do
  @moduledoc """
  A handler that returns {:ok, result} for testing run_event result forwarding.
  """
  @behaviour EventBus.Handler

  alias EventBus.TestSupport.TestEvent

  @impl true
  def handle_event(%TestEvent{} = event) do
    {:ok, event.data}
  end
end
