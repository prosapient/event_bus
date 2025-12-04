defmodule EventBusTest do
  use ExUnit.Case, async: false

  alias EventBus.TestSupport.AnotherHandler
  alias EventBus.TestSupport.TestEvent
  alias EventBus.TestSupport.TestHandler

  setup do
    original_handlers = Application.get_env(:event_bus, :handlers)
    original_defaults = Application.get_env(:event_bus, :default_oban_options)

    on_exit(fn ->
      if original_handlers do
        Application.put_env(:event_bus, :handlers, original_handlers)
      else
        Application.delete_env(:event_bus, :handlers)
      end

      if original_defaults do
        Application.put_env(:event_bus, :default_oban_options, original_defaults)
      else
        Application.delete_env(:event_bus, :default_oban_options)
      end
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

  describe "EventBus.Handler" do
    test "handler returns oban_options" do
      opts = TestHandler.oban_options()

      assert Keyword.get(opts, :queue) == :test_events
      assert Keyword.get(opts, :priority) == 1
      assert Keyword.get(opts, :max_attempts) == 3
    end

    test "different handlers can have different options" do
      test_opts = TestHandler.oban_options()
      another_opts = AnotherHandler.oban_options()

      assert Keyword.get(test_opts, :priority) == 1
      assert Keyword.get(another_opts, :priority) == 2
    end
  end
end
