defmodule EventBus.Backend.Oban do
  @moduledoc """
  Oban backend - dispatches events to handlers via Oban jobs.
  """

  @behaviour EventBus.Backend

  @impl EventBus.Backend
  def publish(event) do
    event
    |> EventBus.Registry.handlers_for_event()
    |> Enum.map(&EventBus.Worker.new_for_handler(event, &1))
    |> Oban.insert_all()

    :ok
  end
end
