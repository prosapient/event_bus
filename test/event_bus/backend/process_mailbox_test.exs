defmodule EventBus.Backend.ProcessMailboxTest do
  use ExUnit.Case, async: true

  alias EventBus.Backend.ProcessMailbox
  alias EventBus.TestSupport.TestEvent

  describe "publish/1" do
    test "sends event to current process mailbox" do
      event = %TestEvent{id: "123", data: "test"}

      assert ProcessMailbox.publish(event) == :ok

      assert_received {:event_published, ^event, _meta}
    end

    test "can receive multiple events" do
      event1 = %TestEvent{id: "1", data: "first"}
      event2 = %TestEvent{id: "2", data: "second"}

      ProcessMailbox.publish(event1)
      ProcessMailbox.publish(event2)

      assert_received {:event_published, ^event1, _}
      assert_received {:event_published, ^event2, _}
    end

    test "can pattern match on event fields" do
      event = %TestEvent{id: "abc", data: "some data"}

      ProcessMailbox.publish(event)

      assert_received {:event_published, %TestEvent{id: id}, _meta}
      assert id == "abc"
    end

    test "sends event to test process when called from Task" do
      event = %TestEvent{id: "from-task", data: "async"}

      Task.async(fn ->
        ProcessMailbox.publish(event)
      end)
      |> Task.await()

      assert_received {:event_published, ^event, _meta}
    end

    test "sends event to test process when called from nested Task" do
      event = %TestEvent{id: "nested", data: "deep"}

      Task.async(fn ->
        Task.async(fn ->
          ProcessMailbox.publish(event)
        end)
        |> Task.await()
      end)
      |> Task.await()

      assert_received {:event_published, ^event, _meta}
    end

    test "stacktrace starts from caller, excluding ProcessMailbox internals" do
      event = %TestEvent{id: "stacktrace-test", data: "test"}

      ProcessMailbox.publish(event)

      assert_received {:event_published, ^event, %{stacktrace: stacktrace}}

      # First frame should be the test function that called publish
      # We verify module, function name pattern, and file location
      [{module, function, arity, location} | _] = stacktrace

      assert module == __MODULE__
      assert arity == 1
      assert Atom.to_string(function) =~ "stacktrace starts from caller"
      assert location |> Keyword.fetch!(:file) |> to_string() =~ "process_mailbox_test.exs"
      assert Keyword.fetch!(location, :line) == 64

      # Internal frames should be excluded
      stacktrace_modules = Enum.map(stacktrace, &elem(&1, 0))
      refute EventBus.Backend.ProcessMailbox in stacktrace_modules
      refute Process in stacktrace_modules
    end
  end
end
