defmodule EventBus.TestSupport.WorkerHelpers do
  @moduledoc """
  Helpers for asserting on `EventBus.Worker` jobs in a way that works
  in both Oban Pro mode (atom keys in args) and Oban OSS mode (string keys).
  """

  @doc """
  Reads a field from a job's args, regardless of whether the args use
  atom or string keys.
  """
  @spec arg(Oban.Job.t(), atom()) :: term()
  def arg(job, key) when is_atom(key) do
    case job.args do
      %{^key => value} -> value
      args when is_map(args) -> Map.get(args, Atom.to_string(key))
    end
  end

  @doc """
  Returns whether a job's args contain the given key.
  """
  @spec has_arg?(Oban.Job.t(), atom()) :: boolean()
  def has_arg?(job, key) when is_atom(key) do
    Map.has_key?(job.args, key) or Map.has_key?(job.args, Atom.to_string(key))
  end
end
