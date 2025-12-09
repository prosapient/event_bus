defprotocol EventBus.Partitioned do
  @moduledoc """
  Protocol for events that need sequential processing per entity.

  Events with the same partition key are processed in order.
  Events without partition key (nil) are processed in parallel.

  ## Usage

  Implement inside the event module:

      defmodule Events.ExpertProfiles.ComplianceTrainingCompleted do
        use TypedStruct

        typedstruct enforce: true do
          field :expert_profile_id, String.t()
          field :source, :platform | :expert_portal
        end

        defimpl EventBus.Partitioned do
          def partition_key(%{expert_profile_id: id}), do: id
        end
      end

  Events without implementation will default to `nil` (parallel processing).
  """

  @fallback_to_any true

  @doc """
  Returns partition key for sequential processing.

  Events with the same partition key are processed in order.
  Return `nil` for parallel processing.
  """
  @spec partition_key(t) :: String.t() | nil
  def partition_key(event)
end

defimpl EventBus.Partitioned, for: Any do
  def partition_key(_event), do: nil
end
