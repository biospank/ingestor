defmodule Ingestor do
  @training_dir "training"
  @testing_dir "testing"
  @data_dir "data"

  @crops [
    {3, 2}, # start from 3rd second for 2 seconds
    {6, 2} # start from 6rd second for 2 seconds
  ]

  @training_volumes [
    "0.1", "0.15", "0.2",
    "0.25", "0.3", "0.35",
    "0.4", "0.45", "0.5",
    "0.55", "0.6", "0.65",
    "0.7", "0.75", "0.8",
    "0.85", "0.9", "0.95", "1"
  ]

  @testing_volumes [
    "0.2", "0.4", "0.6", "0.8", "1"
  ]

  @moduledoc """
  Documentation for `Ingestor`.
  """

  def run do
    with {:ok, _} <- remove_dir(@training_dir),
         {:ok, _} <- remove_dir(@testing_dir),
         :ok <- create_dir(@training_dir),
         :ok <- create_dir(@testing_dir),
         {:ok, audio_files} <- list_audio_files() do

      audio_files
      |> ingest(:training)
      |> ingest(:testing)

      {:ok, :done}
    else
      {:error, reason} ->
        IO.puts("Unexpected exception: #{reason}")
      {:error, reason, file} ->
        IO.puts("Unexpected exception: #{reason} for file #{file}")
    end
  end

  defp create_dir(dir) do
    File.mkdir_p(dir)
  end

  defp remove_dir(dir) do
    File.rm_rf(dir)
  end

  @doc """
  list_audio_files.

  ## Examples

      iex> Ingestor.list_audio_files()
      {:ok, ["test.ogg"]}

  """
  def list_audio_files() do
    #Path.wildcard("data/*")
    File.ls(@data_dir)
  end

  defp ingest(files, :training = target) do
    for file <- files, volume <- @training_volumes, crop <- @crops do
      ffmpeg_cmd(file, volume, crop, target)
    end

    files
  end

  defp ingest(files, :testing = target) do
    for file <- files, volume <- @testing_volumes, crop <- @crops do
      ffmpeg_cmd(file, volume, crop, target)
    end

    files
  end

  defp ffmpeg_cmd(file, volume, {start, length}, target) do
    [name, _ext] = String.split(file, ".")
    _result = Porcelain.shell("ffmpeg -hide_banner -loglevel error -ss #{start} -i #{@data_dir}/#{file} -t #{length} -ar 16000  -af volume=#{volume} #{target}/#{name}-#{volume}-#{start}-#{length}.wav")
    #IO.inspect result.out
  end

end
