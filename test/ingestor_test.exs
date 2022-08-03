defmodule IngestorTest do
  use ExUnit.Case
  doctest Ingestor

  setup_all %{} do
    result = Ingestor.run()

    {:ok, result: result}
  end

  test "returns {:ok, :done} tuple", %{result: result} do
    assert result == {:ok, :done}
  end

  test "creates training dir" do
    {:ok, dirs} = File.ls()

    assert "training" in dirs
  end

  test "creates testing dir" do
    {:ok, dirs} = File.ls()

    assert "testing" in dirs
  end

  test "creates 38 training files" do
    {:ok, files} = File.ls("training")

    assert Enum.count(files) == 19
  end

  test "creates 10 testing files" do
    {:ok, files} = File.ls("testing")

    assert Enum.count(files) == 5
  end
end
