defmodule EventBusTest do
  use ExUnit.Case, async: false

  alias EventBus.TestSupport.AnotherHandler
  alias EventBus.TestSupport.TestEvent
  alias EventBus.TestSupport.TestHandler

  setup do
    original_handlers = Application.get_env(:event_bus, :handlers, %{})

    on_exit(fn ->
      Application.put_env(:event_bus, :handlers, original_handlers)
    end)

    :ok
  end

  describe "publish/1" do
    test "returns :ok" do
      Application.put_env(:event_bus, :handlers, %{
        TestEvent => [TestHandler, AnotherHandler]
      })

      event = %TestEvent{id: "123", data: "test"}

      # publish returns :ok immediately
      # Actual job insertion is tested via integration tests with Oban.Testing
      assert EventBus.publish(event) == :ok
    end

    test "returns :ok even when no handlers registered" do
      Application.put_env(:event_bus, :handlers, %{})

      event = %TestEvent{id: "123", data: "test"}

      # Should log warning but still return :ok
      assert EventBus.publish(event) == :ok
    end
  end
end
