defmodule Caretaker.ACS.DeviceDetectionTest do
  use ExUnit.Case, async: true

  alias Caretaker.ACS.DeviceDetection
  alias Caretaker.TR069.RPC.Inform

  describe "detect/1" do
    test "detects Mikrotik RouterOS device" do
      inform = %Inform{
        device_id: %{
          oui: "D4CA6D",
          manufacturer: "MikroTik",
          product_class: "RouterOS",
          serial_number: "1234567890"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0,
        parameter_list: [
          {"Device.DeviceInfo.ModelName", "RB4011iGS+"},
          {"Device.DeviceInfo.SoftwareVersion", "7.12.1"}
        ]
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:mikrotik, :routeros}
      assert info.oui == "D4CA6D"
      assert info.manufacturer == "MikroTik"
      assert info.product_class == "RouterOS"
      assert info.model == "RB4011iGS+"
      assert info.software_version == "7.12.1"
    end

    test "detects Huawei GPON ONT" do
      inform = %Inform{
        device_id: %{
          oui: "00E0FC",
          manufacturer: "Huawei",
          product_class: "GPON_ONT",
          serial_number: "ABC1234567"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0,
        parameter_list: [
          {"Device.DeviceInfo.ModelName", "HG8245H"}
        ]
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:gpon_ont, :huawei}
      assert info.oui == "00E0FC"
      assert info.model == "HG8245H"
    end

    test "detects ZTE GPON ONT" do
      inform = %Inform{
        device_id: %{
          oui: "001E58",
          manufacturer: "ZTE",
          product_class: "ONT",
          serial_number: "XYZ1234567"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:gpon_ont, :zte}
      assert info.oui == "001E58"
    end

    test "detects XGS-PON ONT" do
      inform = %Inform{
        device_id: %{
          oui: "00E0FC",
          manufacturer: "Huawei",
          product_class: "XGSPON_ONT",
          serial_number: "ABC1234567"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:xgspon_ont, :huawei}
    end

    test "detects Arris cable modem" do
      inform = %Inform{
        device_id: %{
          oui: "0015A4",
          manufacturer: "Arris",
          product_class: "Cable_Modem",
          serial_number: "CM1234567"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:cable_modem, :arris}
      assert info.oui == "0015A4"
    end

    test "detects generic router" do
      inform = %Inform{
        device_id: %{
          oui: "AABBCC",
          manufacturer: "Generic Manufacturer",
          product_class: "Router",
          serial_number: "123456"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:router, :generic}
    end

    test "detects unknown device" do
      inform = %Inform{
        device_id: %{
          oui: "FFFFFF",
          manufacturer: "Unknown",
          product_class: "Something",
          serial_number: "123"
        },
        events: ["1 BOOT"],
        max_envelopes: 1,
        current_time: DateTime.utc_now(),
        retry_count: 0
      }

      info = DeviceDetection.detect(inform)

      assert info.type == {:generic, :unknown}
    end
  end

  describe "normalize_oui/1" do
    test "normalizes OUI with colons" do
      assert DeviceDetection.normalize_oui("D4:CA:6D") == "D4CA6D"
      assert DeviceDetection.normalize_oui("00:E0:FC") == "00E0FC"
    end

    test "normalizes OUI with dashes" do
      assert DeviceDetection.normalize_oui("D4-CA-6D") == "D4CA6D"
    end

    test "uppercases lowercase OUI" do
      assert DeviceDetection.normalize_oui("d4ca6d") == "D4CA6D"
    end

    test "handles already normalized OUI" do
      assert DeviceDetection.normalize_oui("D4CA6D") == "D4CA6D"
    end
  end

  describe "is_mikrotik?/2" do
    test "recognizes Mikrotik OUI" do
      assert DeviceDetection.is_mikrotik?("D4CA6D", "Some Manufacturer")
      assert DeviceDetection.is_mikrotik?("2CC81B", "")
    end

    test "recognizes Mikrotik manufacturer string" do
      assert DeviceDetection.is_mikrotik?("AABBCC", "MikroTik")
      assert DeviceDetection.is_mikrotik?("AABBCC", "RouterOS")
    end

    test "returns false for non-Mikrotik" do
      refute DeviceDetection.is_mikrotik?("00E0FC", "Huawei")
    end
  end

  describe "ONT vendor detection" do
    test "detects Huawei ONT" do
      assert DeviceDetection.detect_ont_vendor("00E0FC", "Huawei") == :huawei
    end

    test "detects ZTE ONT" do
      assert DeviceDetection.detect_ont_vendor("001E58", "ZTE") == :zte
    end

    test "detects Nokia ONT" do
      assert DeviceDetection.detect_ont_vendor("0004ED", "Nokia") == :nokia
    end

    test "returns unknown for unrecognized vendor" do
      assert DeviceDetection.detect_ont_vendor("FFFFFF", "Unknown") == :unknown
    end
  end

  describe "cable modem vendor detection" do
    test "detects Arris modem" do
      assert DeviceDetection.detect_cm_vendor("0015A4", "Arris") == :arris
    end

    test "detects Technicolor modem" do
      assert DeviceDetection.detect_cm_vendor("00195E", "Technicolor") == :technicolor
    end

    test "returns unknown for unrecognized vendor" do
      assert DeviceDetection.detect_cm_vendor("FFFFFF", "Unknown") == :unknown
    end
  end
end
