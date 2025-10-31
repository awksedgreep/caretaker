defmodule Caretaker.TR181.ModelCastTest do
  use ExUnit.Case, async: true
  alias Caretaker.TR181.Model

  describe "type_for_xsd/1" do
    test "maps common XSD types" do
      assert :string == Model.type_for_xsd("xsd:string")
      assert :int == Model.type_for_xsd("xsd:int")
      assert :uint == Model.type_for_xsd("xsd:unsignedInt")
      assert :bool == Model.type_for_xsd("xsd:boolean")
      assert :datetime == Model.type_for_xsd("xsd:dateTime")
      assert :long == Model.type_for_xsd("xsd:long")
      assert :ulong == Model.type_for_xsd("xsd:unsignedLong")
      assert :float == Model.type_for_xsd("xsd:float")
      assert :double == Model.type_for_xsd("xsd:double")
      assert :decimal == Model.type_for_xsd("xsd:decimal")
      assert :base64 == Model.type_for_xsd("xsd:base64Binary")
      assert :unknown == Model.type_for_xsd("xsd:unknown")
    end
  end

  describe "cast/2" do
    test "string passthrough" do
      assert {:ok, "abc"} == Model.cast("abc", "xsd:string")
    end

    test "int and unsignedInt" do
      assert {:ok, 42} == Model.cast("42", "xsd:int")
      assert {:ok, 0} == Model.cast("0", "xsd:unsignedInt")
      assert {:ok, 123} == Model.cast("123", "xsd:unsignedInt")
      assert {:error, :negative} == Model.cast("-1", "xsd:unsignedInt")
      assert {:error, :invalid_int} == Model.cast("abc", "xsd:int")
    end

    test "boolean variants" do
      assert {:ok, true} == Model.cast("1", "xsd:boolean")
      assert {:ok, false} == Model.cast("0", "xsd:boolean")
      assert {:ok, true} == Model.cast("true", "xsd:boolean")
      assert {:ok, false} == Model.cast("false", "xsd:boolean")
      assert {:error, :invalid_boolean} == Model.cast("maybe", "xsd:boolean")
    end

    test "dateTime and numeric floats" do
      assert {:ok, %DateTime{}} = Model.cast("2020-01-02T03:04:05Z", "xsd:dateTime")
      assert {:error, :invalid_datetime} == Model.cast("bad", "xsd:dateTime")
      assert {:ok, 1.23} == Model.cast("1.23", "xsd:float")
      assert {:ok, 1.23} == Model.cast("1.23", "xsd:double")
      assert {:ok, 1.23} == Model.cast("1.23", "xsd:decimal")
    end

    test "base64Binary" do
      assert {:ok, "Hello"} == Model.cast("SGVsbG8=", "xsd:base64Binary")
      assert {:error, :invalid_base64} == Model.cast("!!!", "xsd:base64Binary")
    end

    test "unknown type -> string" do
      assert {:ok, "xyz"} == Model.cast("xyz", "xsd:weird")
    end
  end

  describe "cast_param/1" do
    test "success and error include name" do
      assert {:ok, %{name: "Device.X", value: 5, type: "xsd:int"}} ==
               Model.cast_param(%{name: "Device.X", value: "5", type: "xsd:int"})

      assert {:error, {"Device.X", :invalid_int}} ==
               Model.cast_param(%{name: "Device.X", value: "abc", type: "xsd:int"})
    end
  end
end
