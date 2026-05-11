exclude_tags =
  if Code.ensure_loaded?(Oban.Pro.Worker) do
    [:oss]
  else
    [:pro]
  end

EventBus.Testing.start_link()
ExUnit.start(exclude: exclude_tags)
