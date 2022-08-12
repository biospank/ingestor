defmodule Ingestor do
  @moduledoc """
  Documentation for Ingestor:

  Build the script

  mix escript.build

  Run the script

  ./ingestor [--help] [--freq 16000] [--length 2]

  """

  @training_dir "training"
  @testing_dir "testing"
  @data_dir "data"

  @crop_length 2
  @crops [
    {3, @crop_length}, # start from 3rd second for 2 seconds
    {6, @crop_length} # start from 6th second for 2 seconds
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

  def main(argv) do
    {opts, _parsed, errors} =
      argv
      |> OptionParser.parse(
        strict: [
          help: :boolean,
          freq: :integer,
          length: :integer
        ],
        aliases: [
          h: :help,
          z: :freq,
          l: :length
        ]
      )

    # IO.puts("parsed errors: #{inspect(errors)}")

    if errors |> Enum.empty?() do
      run(opts)
    else
      IO.puts("Invalid options")
      run(help: true)
      System.halt(1)
    end
  end

  def run(help: true) do
    IO.puts @moduledoc
    System.halt(0)
  end

  def run(opts) do
    with {:ok, _} <- remove_dir(@training_dir),
         {:ok, _} <- remove_dir(@testing_dir),
         :ok <- create_dir(@training_dir),
         :ok <- create_dir(@testing_dir),
         {:ok, audio_files} <- list_audio_files() do

      audio_files
      |> ingest(:training, opts)
      |> ingest(:testing, opts)

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

  @doc ~S"""
  list_audio_files.

  ## Examples

      iex> Ingestor.list_audio_files()
      {:ok, ["test.ogg"]}

  """
  def list_audio_files() do
    #Path.wildcard("data/*")
    File.ls(@data_dir)
  end

  defp ingest(files, :training = target, opts) do
    {:ok, options} = extract_options(opts)
    crop_length = opts[:length] || @crop_length

    for file <- files, volume <- @training_volumes, crop <- window_crops(file, crop_length) do
      ffmpeg_cmd(file, volume, crop, target, options)
    end

    files
  end

  defp ingest(files, :testing = target, opts) do
    {:ok, options} = extract_options(opts)
    crop_length = opts[:length] || @crop_length

    for file <- files, volume <- @testing_volumes, crop <- window_crops(file, crop_length) do
      ffmpeg_cmd(file, volume, crop, target, options)
    end

    files
  end

  defp window_crops(file, crop_length) do
    file
    |> audio_length()
    |> build_crops(crop_length)
    |> IO.inspect(label: "Crops")
  end

  @doc ~S"""
  Build an array of tuple in the form [{start, length}, {start, length}, {start, length}, ...]

  ## Examples

      iex> Ingestor.build_crops(%Porcelain.Result{err: nil, out: "8.321\n", status: :ok}, 2)
      [{0, 2}, {3, 2}, {4, 2}, {5, 2}, {6, 2}]

  """
  def build_crops(%Porcelain.Result{err: _, out: length_in_seconds, status: _}, crop_length) do
    length_in_seconds =
      length_in_seconds
      |> String.trim()
      |> String.to_float()
      |> floor()

    slices = length_in_seconds |> Integer.floor_div(crop_length)

    cond do
      slices > 0 ->
        Enum.reduce_while(0..slices, [], fn x, acc ->
          case x do
            0 ->
              {:cont, [{x, crop_length} | acc]}
            x when (x + crop_length) < length_in_seconds ->
              {:cont, [{x + crop_length, crop_length} | acc]}
            _ ->
              {:halt, acc}
          end
        end) |> Enum.reverse()
      true ->
        @crops
    end
  end

  @doc ~S"""
  extract argv options into a string options.

  ## Examples

      iex> Ingestor.extract_options([{:freq, 16000}])
      {:ok, " -ar 16000 "}
      iex> Ingestor.extract_options([{:freq, 16000}, {:length, 2}])
      {:ok, " -ar 16000 "}
      iex> Ingestor.extract_options([{:length, 2}])
      {:ok, ""}

  """
  def extract_options(opts) do
    options =
      opts |> Enum.reduce("", fn
        {:freq, value}, acc ->
          acc <> " -ar #{value} "
        {:length, _}, acc ->
          acc
        {key, value}, acc ->
          acc <> " #{key} #{value} "
      end)

    {:ok, options}
  end

  defp ffmpeg_cmd(file, volume, {start, length}, target, options) do
    [name, _ext] = String.split(file, ".")

    _result = Porcelain.shell("ffmpeg -hide_banner -loglevel error -ss #{start} -i #{@data_dir}/#{file} -t #{length} #{options} -af volume=#{volume} #{target}/#{name}-#{volume}-#{start}-#{length}.wav")
    #IO.inspect result.out
  end

  defp audio_length(file) do
    Porcelain.shell("ffprobe -i #{@data_dir}/#{file} -v quiet -show_entries format=duration -hide_banner -of default=noprint_wrappers=1:nokey=1")
  end
end
