defmodule EventBus.HandlerTest do
  use ExUnit.Case, async: true

  alias EventBus.Handler
  alias EventBus.TestSupport.SelectiveHandler
  alias EventBus.TestSupport.TestEvent
  alias EventBus.TestSupport.TestHandler

  describe "interested?/2" do
    test "returns true when handler does not implement interested?/1" do
      event = %TestEvent{id: "1", data: "anything"}

      assert Handler.interested?(TestHandler, event) == true
    end

    test "delegates to handler's interested?/1 when implemented" do
      assert Handler.interested?(SelectiveHandler, %TestEvent{data: "relevant"}) == true
      assert Handler.interested?(SelectiveHandler, %TestEvent{data: "irrelevant"}) == false
    end
  end
end
