defmodule EventBus.TestingTest do
  use ExUnit.Case, async: true

  import EventBus.Testing

  alias EventBus.Backend.ProcessMailbox
  alias EventBus.TestSupport.TestEvent
  alias EventBus.TestSupport.TestHandler

  setup do
    original_handlers = Application.get_env(:event_bus, :handlers, %{})

    # Setup handlers for inline mode tests
    Application.put_env(:event_bus, :handlers, %{
      TestEvent => [TestHandler]
    })

    on_exit(fn ->
      Application.put_env(:event_bus, :handlers, original_handlers)
    end)

    setup_event_bus_testing()
  end

  describe "set_event_bus_mode/1" do
    test "sets mode to :default" do
      set_event_bus_mode(:default)
      assert get_event_bus_mode() == :default
    end

    test "sets mode to :strict" do
      set_event_bus_mode(:strict)
      assert get_event_bus_mode() == :strict
    end

    test "sets mode to :inline" do
      set_event_bus_mode(:inline)
      assert get_event_bus_mode() == :inline
    end

    test "switching from :strict to :default verifies no pending events" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert_raise RuntimeError, ~r/Unasserted events published in strict mode/, fn ->
        set_event_bus_mode(:default)
      end
    end

    test "switching from :strict to :default passes when all events asserted" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})
      assert_event_published %TestEvent{id: "123"}

      # Should not raise
      set_event_bus_mode(:default)
    end
  end

  describe "get_event_bus_mode/0" do
    test "returns :default when not set" do
      assert get_event_bus_mode() == :default
    end

    test "returns mode from current process" do
      set_event_bus_mode(:strict)
      assert get_event_bus_mode() == :strict
    end

    test "returns mode from parent process via $callers" do
      set_event_bus_mode(:strict)

      Task.async(fn ->
        assert get_event_bus_mode() == :strict
      end)
      |> Task.await()
    end

    test "returns mode from root caller in nested tasks" do
      set_event_bus_mode(:strict)

      Task.async(fn ->
        Task.async(fn ->
          assert get_event_bus_mode() == :strict
        end)
        |> Task.await()
      end)
      |> Task.await()
    end
  end

  describe "assert_event_published/1" do
    test "matches strict events" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "abc", data: "test"})

      assert_event_published %TestEvent{id: "abc"}
    end

    test "can pattern match on fields" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "xyz", data: "some data"})

      assert_event_published %TestEvent{id: id, data: data}
      assert id == "xyz"
      assert data == "some data"
    end

    test "does not match default mode events" do
      set_event_bus_mode(:default)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      refute_received {:event_published, %TestEvent{}, %{strict: true}}
    end
  end

  describe "ProcessMailbox with modes" do
    test "default mode sends event with strict: false" do
      set_event_bus_mode(:default)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert_received {:event_published, %TestEvent{id: "123"}, %{strict: false}}
    end

    test "strict mode sends event with strict: true" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert_received {:event_published, %TestEvent{id: "123"}, %{strict: true}}
    end

    test "strict mode includes stacktrace" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert_received {:event_published, _, %{stacktrace: stacktrace}}
      assert is_list(stacktrace)
      assert length(stacktrace) > 0
    end

    test "inline mode executes handlers synchronously" do
      set_event_bus_mode(:inline)

      # TestHandler stores handled events in process dictionary
      ProcessMailbox.publish(%TestEvent{id: "inline-test", data: "test"})

      # Verify handler was called (TestHandler puts result in process dict)
      assert Process.get(:last_handled_event) == %TestEvent{id: "inline-test", data: "test"}
    end

    test "inline mode does not send to mailbox" do
      set_event_bus_mode(:inline)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      refute_received {:event_published, _, _}
    end

    test "events from Task are sent to test process" do
      set_event_bus_mode(:strict)

      Task.async(fn ->
        ProcessMailbox.publish(%TestEvent{id: "from-task", data: "test"})
      end)
      |> Task.await()

      assert_event_published %TestEvent{id: "from-task"}
    end
  end

  describe "allow_event_bus/1 for non-Task processes" do
    test "events from spawned process reach test when allowed" do
      set_event_bus_mode(:strict)
      test_pid = self()

      pid =
        spawn(fn ->
          receive do
            :publish ->
              ProcessMailbox.publish(%TestEvent{id: "from-spawn", data: "test"})
              send(test_pid, :done)
          end
        end)

      allow_event_bus(pid)
      send(pid, :publish)
      assert_receive :done

      assert_event_published %TestEvent{id: "from-spawn"}
    end

    test "events from GenServer-like process reach test when allowed" do
      set_event_bus_mode(:strict)
      test_pid = self()

      # Simulate GenServer without $callers
      {:ok, agent} =
        Agent.start(fn ->
          %{test_pid: test_pid}
        end)

      allow_event_bus(agent)

      Agent.update(agent, fn state ->
        ProcessMailbox.publish(%TestEvent{id: "from-agent", data: "test"})
        state
      end)

      Agent.stop(agent)

      assert_event_published %TestEvent{id: "from-agent"}
    end

    test "allow_event_bus/2 allows specifying explicit owner" do
      set_event_bus_mode(:strict)
      owner = self()
      test_pid = self()

      pid =
        spawn(fn ->
          receive do
            :publish ->
              ProcessMailbox.publish(%TestEvent{id: "explicit-owner", data: "test"})
              send(test_pid, :done)
          end
        end)

      allow_event_bus(pid, owner)
      send(pid, :publish)
      assert_receive :done

      assert_event_published %TestEvent{id: "explicit-owner"}
    end
  end

  describe "assert_no_pending_strict_events!/0" do
    test "passes when no strict events" do
      assert assert_no_pending_strict_events!() == :ok
    end

    test "passes when only default events" do
      set_event_bus_mode(:default)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert assert_no_pending_strict_events!() == :ok
    end

    test "raises when strict events remain" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      assert_raise RuntimeError, ~r/Unasserted events published in strict mode/, fn ->
        assert_no_pending_strict_events!()
      end
    end

    test "error message includes event details" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "error-test", data: "details"})

      error =
        assert_raise RuntimeError, fn ->
          assert_no_pending_strict_events!()
        end

      assert error.message =~ "error-test"
      assert error.message =~ "TestEvent"
    end

    test "error message includes stacktrace" do
      set_event_bus_mode(:strict)
      ProcessMailbox.publish(%TestEvent{id: "123", data: "test"})

      error =
        assert_raise RuntimeError, fn ->
          assert_no_pending_strict_events!()
        end

      assert error.message =~ "Published at:"
    end
  end
end
