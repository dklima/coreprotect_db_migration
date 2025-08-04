# frozen_string_literal: true

require "rspec"
require_relative "../../lib/formatters/value_formatter"

RSpec.describe ValueFormatter, :aggregate_failures do
  describe ".format_for_mysql" do
    context "when value is a string" do
      it "returns base64 encoded format for simple string" do
        result = ValueFormatter.format_for_mysql('test string')
        expect(result).to match(/FROM_BASE64\('.*'\)/)
        # Verify it contains base64 encoded content
        expect(result).to include('FROM_BASE64(')
      end

      it "handles empty string" do
        result = ValueFormatter.format_for_mysql('')
        expect(result).to eq("FROM_BASE64('')")
      end

      it "handles string with special characters" do
        special_string = "Hello\nWorld\t💻"
        result = ValueFormatter.format_for_mysql(special_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
      end

      it "handles string with single quotes" do
        quoted_string = "It's a test with 'quotes'"
        result = ValueFormatter.format_for_mysql(quoted_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
      end

      it "handles string with double quotes" do
        quoted_string = 'This has "double quotes" in it'
        result = ValueFormatter.format_for_mysql(quoted_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
      end

      it "handles string with SQL injection attempts" do
        malicious_string = "'; DROP TABLE users; --"
        result = ValueFormatter.format_for_mysql(malicious_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
        expect(result).not_to include('DROP TABLE')
      end

      it "handles unicode characters" do
        unicode_string = "🚀 Testing émojis and spéciàl chârs ñ"
        result = ValueFormatter.format_for_mysql(unicode_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
      end

      it "handles very long strings" do
        long_string = "a" * 10000
        result = ValueFormatter.format_for_mysql(long_string)
        expect(result).to match(/FROM_BASE64\('.*'\)/)
      end
    end

    context "when value is not a string" do
      it "returns JSON format for integers" do
        expect(ValueFormatter.format_for_mysql(123)).to eq('123')
      end

      it "returns JSON format for negative integers" do
        expect(ValueFormatter.format_for_mysql(-456)).to eq('-456')
      end

      it "returns JSON format for zero" do
        expect(ValueFormatter.format_for_mysql(0)).to eq('0')
      end

      it "returns JSON format for floats" do
        expect(ValueFormatter.format_for_mysql(123.45)).to eq('123.45')
      end

      it "returns JSON format for negative floats" do
        expect(ValueFormatter.format_for_mysql(-67.89)).to eq('-67.89')
      end

      it "returns JSON format for true boolean" do
        expect(ValueFormatter.format_for_mysql(true)).to eq('true')
      end

      it "returns JSON format for false boolean" do
        expect(ValueFormatter.format_for_mysql(false)).to eq('false')
      end

      it "returns JSON format for nil" do
        expect(ValueFormatter.format_for_mysql(nil)).to eq('null')
      end

      it "returns JSON format for arrays" do
        array = [ 1, 2, 3 ]
        expect(ValueFormatter.format_for_mysql(array)).to eq('[1,2,3]')
      end

      it "returns JSON format for hashes" do
        hash = { "key" => "value", "number" => 42 }
        result = ValueFormatter.format_for_mysql(hash)
        expect(result).to be_a(String)
        expect(JSON.parse(result)).to eq(hash)
      end

      it "returns JSON format for complex nested structures" do
        complex = {
          "users" => [
            { "name" => "John", "age" => 30 },
            { "name" => "Jane", "age" => 25 }
          ],
          "metadata" => { "created_at" => "2023-01-01" }
        }
        result = ValueFormatter.format_for_mysql(complex)
        expect(result).to be_a(String)
        expect(JSON.parse(result)).to eq(complex)
      end
    end

    context "edge cases and boundary conditions" do
      it "handles extremely large numbers" do
        large_number = 999999999999999999999999999999
        result = ValueFormatter.format_for_mysql(large_number)
        expect(result).to eq(large_number.to_json)
      end

      it "handles very small decimal numbers" do
        small_decimal = 0.000000000001
        result = ValueFormatter.format_for_mysql(small_decimal)
        expect(result).to eq(small_decimal.to_json)
      end

      it "handles symbols" do
        symbol = :test_symbol
        result = ValueFormatter.format_for_mysql(symbol)
        expect(result).to eq('"test_symbol"')
      end

      it "handles time objects" do
        time = Time.new(2023, 1, 1, 12, 0, 0)
        result = ValueFormatter.format_for_mysql(time)
        expect(result).to be_a(String)
      end

      it "handles date objects" do
        date = Date.new(2023, 1, 1)
        result = ValueFormatter.format_for_mysql(date)
        expect(result).to be_a(String)
      end
    end

    context "base64 encoding validation" do
      it "produces valid base64 that can be decoded" do
        original_string = "Test string with special chars: àáâãäåæç"
        result = ValueFormatter.format_for_mysql(original_string)

        # Extract base64 content from FROM_BASE64('content')
        base64_content = result.match(/FROM_BASE64\('(.*)'\)/)[1]

        # Decode and verify it matches original
        decoded = Base64.decode64(base64_content).force_encoding('UTF-8')
        expect(decoded).to eq(original_string)
      end

      it "strips newlines from base64 output" do
        long_string = "a" * 100
        result = ValueFormatter.format_for_mysql(long_string)

        # Base64 encoding of long strings can include newlines, ensure they're stripped
        expect(result).not_to include("\n")
        expect(result).not_to include("\r")
      end
    end
  end
end
