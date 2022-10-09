defmodule Ingestor do
  @moduledoc """
  Documentation for Ingestor:

  Build the script

  mix escript.build

  Run the script

  ./ingestor [--help|-h] [--targer|-t training|testing] [--freq|-z 16000] [--crop_start|-s 1 --crop_end|-e 6] [--crop_length|-l 2] [--volume_min|-v 8]

  """

  @data_dir "data"
  @training_dir "training"
  @testing_dir "testing"

  @crop_start 0
  @crop_length 1
  # @crops [
  #   {3, @crop_length}, # start from 3rd second for 2 seconds
  #   {6, @crop_length} # start from 6th second for 2 seconds
  # ]

  @volume_max 10

  @training_volumes ["0.8", "0.85", "0.9", "0.95", "1"]

  @testing_volumes ["0.8", "0.9", "1"]

  def main(argv) do
    {opts, parsed, errors} =
      argv
      |> IO.inspect(label: "argv")
      |> OptionParser.parse(
        strict: [
          help: :boolean,
          target: :string,
          freq: :integer,
          crop_start: :integer,
          crop_end: :integer,
          crop_length: :integer,
          volume_min: :integer
        ],
        aliases: [
          h: :help,
          t: :target,
          z: :freq,
          s: :crop_start,
          e: :crop_end,
          l: :crop_length,
          v: :volume_min
        ]
      )

    # IO.puts("parsed errors: #{inspect(errors)}")

    if errors |> Enum.empty?() do
      run(opts)
    else
      IO.puts("Invalid options: #{inspect(errors)}")
      IO.puts("options: #{inspect(opts)}")
      IO.puts("parsed: #{inspect(parsed)}")
      run(help: true)
      System.halt(1)
    end
  end

  defp run(help: true) do
    IO.puts @moduledoc
  end

  defp run(opts) do
    ProgressBar.render_spinner( [text: "Converting...", done: "Done."],fn ->
      target = (opts[:target] || "training") |> String.to_atom()

      with {:ok, _} <- remove_dir(target),
          :ok <- create_dir(target),
          {:ok, audio_files} <- list_audio_files() do

        audio_files
        |> ingest(target, opts)

        {:ok, :done}
      else
        {:error, reason} ->
          IO.puts("Unexpected exception: #{reason}")
        {:error, reason, file} ->
          IO.puts("Unexpected exception: #{reason} for file #{file}")
      end
    end)
  end

  defp create_dir(:training), do: File.mkdir_p(@training_dir)
  defp create_dir(:testing), do: File.mkdir_p(@testing_dir)

  defp remove_dir(:training), do: File.rm_rf(@training_dir)
  defp remove_dir(:testing), do: File.rm_rf(@testing_dir)

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
    {:ok, ffmpeg_options} = extract_ffmpeg_options(opts)

    for file <- files, volume <- volumes(target, opts), crop <- window_crops(file, target, opts) do
      #IO.puts("Starting training task for file #{file} volume #{volume} and crop #{inspect(crop)}")
      # Task.start(fn ->
        ffmpeg_cmd(file, volume, crop, target, ffmpeg_options)
      # end)
    end

    files
  end

  defp ingest(files, :testing = target, opts) do
    {:ok, ffmpeg_options} = extract_ffmpeg_options(opts)

    for file <- files, volume <- volumes(target, opts), crop <- window_crops(file, target, opts) do
      #IO.puts("Starting testing task for file #{file} volume #{volume} and crop #{inspect(crop)}")
      # Task.start(fn ->
        ffmpeg_cmd(file, volume, crop, target, ffmpeg_options)
      # end)
    end

    files
  end

  @doc ~S"""
  compose a list of string volumes
  - 0.05 step for training
  - 0.1 step for testing

  ## Examples

      iex> Ingestor.volumes(:training, %{volume_min: 8})
      ["0.8", "0.85", "0.9", "0.95", "1.0"]
      iex> Ingestor.volumes(:testing, %{volume_min: 8})
      ["0.8", "0.9", "1.0"]

  """
  def volumes(:training, opts) do
    case opts[:volume_min] do
      nil ->
        @training_volumes
      volume_min ->
        Enum.reduce_while(volume_min..@volume_max, [], fn x, acc ->
          case x do
            @volume_max ->
              {:cont, [(x * 0.1) |> Float.round(2) |> Float.to_string() | acc]}
            x ->
              {:cont,
                [
                  (x * 0.1 + 0.05) |> Float.round(2) |> Float.to_string() | [
                    (x * 0.1) |> Float.round(2) |> Float.to_string() | acc
                  ]
                ]
              }
          end
        end) #|> Enum.reverse()
    end
  end

  def volumes(:testing, opts) do
    case opts[:volume_min] do
      nil ->
        @testing_volumes
      volume_min ->
        Enum.map(volume_min..@volume_max, fn x ->
          (x * 0.1) |> Float.round(1) |> Float.to_string()
        end)
    end
  end

  defp window_crops(file, target, opts) do
    file
    |> audio_length()
    |> build_crops(target, opts)
    # |> IO.inspect(label: "Crops")
  end

  @doc ~S"""
  Build an array of tuple in the form [{start, length}, {start, length}, {start, length}, ...]

  ## Examples

      iex> Ingestor.build_crops(%Porcelain.Result{out: "8.321\n"}, :training, %{crop_length: 2})
      [{0, 2}, {3, 2}, {4, 2}, {5, 2}, {6, 2}]
      iex> Ingestor.build_crops(%Porcelain.Result{out: "8.321\n"}, :training, %{crop_start: 1, crop_end: 8, crop_length: 1})
      [{1, 1}, {3, 1}, {4, 1}, {5, 1}, {6, 1}, {7, 1}]
      iex> Ingestor.build_crops(%Porcelain.Result{out: "8.321\n"}, :testing, %{crop_length: 2})
      [{0, 2}, {3, 2}, {4, 2}, {5, 2}, {6, 2}]
      iex> Ingestor.build_crops(%Porcelain.Result{out: "8.321\n"}, :testing, %{crop_start: 1, crop_end: 8, crop_length: 1})
      [{1, 1}, {3, 1}, {4, 1}, {5, 1}, {6, 1}, {7, 1}]

  """
  def build_crops(%Porcelain.Result{out: length_in_seconds}, :training, opts) do
    crop_length = opts[:crop_length] || @crop_length
    crop_start = opts[:crop_start] || @crop_start

    length_in_seconds =
      length_in_seconds
      |> String.trim()
      |> String.to_float()
      |> floor()

    audio_length = (opts[:crop_end] || length_in_seconds)
    slices =  audio_length |> Integer.floor_div(crop_length)

    cond do
      slices > 0 ->
        Enum.reduce_while(crop_start..slices, [], fn x, acc ->
          case x do
            ^crop_start ->
              {:cont, [{x, crop_length} | acc]}
            x when (x + crop_length) < audio_length ->
              {:cont, [{x + crop_length, crop_length} | acc]}
            _ ->
              {:halt, acc}
          end
        end) |> Enum.reverse()
      true ->
        [{0, crop_length}]
    end
  end

  def build_crops(%Porcelain.Result{out: length_in_seconds}, :testing, opts) do
    crop_length = opts[:crop_length] || @crop_length
    crop_start = opts[:crop_start] || @crop_start

    length_in_seconds =
      length_in_seconds
      |> String.trim()
      |> String.to_float()
      |> floor()

    audio_length = (opts[:crop_end] || length_in_seconds)
    slices =  audio_length |> Integer.floor_div(crop_length)

    cond do
      slices > 0 ->
        Enum.reduce_while(Range.new(crop_start, slices, 5), [], fn x, acc ->
          case x do
            ^crop_start ->
              {:cont, [{x, crop_length} | acc]}
            x when (x + crop_length) < audio_length ->
              {:cont, [{x + crop_length, crop_length} | acc]}
            _ ->
              {:halt, acc}
          end
        end) |> Enum.reverse()
      true ->
        [{0, crop_length}]
    end
  end

  @doc ~S"""
  extract argv options into a string options.

  ## Examples

      iex> Ingestor.extract_options([{:freq, 16000}])
      {:ok, " -ar 16000 "}
      iex> Ingestor.extract_options([{:freq, 16000}, {:crop_length, 2}])
      {:ok, " -ar 16000 "}
      iex> Ingestor.extract_options([{:crop_length, 2}])
      {:ok, ""}
      iex> Ingestor.extract_options([{:crop_start, 1}])
      {:ok, ""}
      iex> Ingestor.extract_options([{:crop_end, 5}])
      {:ok, ""}

  """
  def extract_ffmpeg_options(opts) do
    options =
      opts |> Enum.reduce("", fn
        {:freq, value}, acc ->
          acc <> " -ar #{value} "
        {:target, _}, acc -> # ignore option
          acc
        {:crop_start, _}, acc -> # ignore option
          acc
        {:crop_end, _}, acc -> # ignore option
          acc
        {:crop_length, _}, acc -> # ignore option
          acc
        {:volume_min, _}, acc -> # ignore option
          acc
        {key, value}, acc ->
          acc <> " #{key} #{value} "
      end)

    {:ok, options}
  end

  defp ffmpeg_cmd(file, volume, {start, length}, target, options) do
    ext = String.split(file, ".") |> List.last()
    name = Path.basename(file, "." <> ext)

    _result = Porcelain.shell("ffmpeg -hide_banner -loglevel error -ss #{start} -i #{@data_dir}/#{file} -t #{length} #{options} -af volume=#{volume} #{target}/#{name}.#{target}-#{volume}-#{start}-#{length}.wav")
    #IO.inspect result.out
  end

  defp audio_length(file) do
    Porcelain.shell("ffprobe -i #{@data_dir}/#{file} -v quiet -show_entries format=duration -hide_banner -of default=noprint_wrappers=1:nokey=1")
  end
end
