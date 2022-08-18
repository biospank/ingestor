defmodule IngestorTest do
  use ExUnit.Case
  doctest Ingestor

  setup_all %{} do
    result = Ingestor.main(["--freq", "16000"])

    Process.sleep(1000)
    {:ok, result: result}
  end

  describe "Ingestor.main/1 arguments" do
    test "returns {:error, 'Invalid options'} on Invalid options", %{result: result} do
      assert result == {:error, "Invalid options"}
    end
  end

  describe "Ingestor.main/1" do
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

    test "creates 30 training files" do
      {:ok, files} = File.ls("training")

      assert Enum.count(files) == 30
    end

    test "creates 18 testing files" do
      {:ok, files} = File.ls("testing")

      assert Enum.count(files) == 18
    end
  end
end
