defmodule EventBus.RegistryTest do
  # async: false because we modify application environment in tests
  use ExUnit.Case, async: false

  alias EventBus.Registry
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

  describe "handlers_for/1" do
    test "returns handlers for registered event type" do
      Application.put_env(:event_bus, :handlers, %{
        TestEvent => [TestHandler, AnotherHandler]
      })

      assert Registry.handlers_for(TestEvent) == [TestHandler, AnotherHandler]
    end

    test "returns empty list for unregistered event type" do
      Application.put_env(:event_bus, :handlers, %{})

      assert Registry.handlers_for(TestEvent) == []
    end

    test "raises when handlers not configured" do
      Application.delete_env(:event_bus, :handlers)

      assert_raise ArgumentError, fn ->
        Registry.handlers_for(TestEvent)
      end
    end
  end
end
