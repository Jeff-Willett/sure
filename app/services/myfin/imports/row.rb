module Myfin
  module Imports
    class Row < Data.define(
      :source_key,
      :source_locator,
      :account_alias,
      :transaction_date,
      :posted_at,
      :reporting_date,
      :name,
      :merchant,
      :amount,
      :currency,
      :pending,
      :source_categories,
      :provider_transaction_id,
      :provider_account_id,
      :raw_payload
    )
      class << self
        def from_2025_wdg(sheet_row:, date:, description:, jpw_category:, wdg_category:,
                          transaction_type:, amount:, account:)
          validate_account!(account)

          transaction_date = parse_date!(date)
          parsed_amount = -parse_amount!(amount)

          new(
            source_key: "2025_full_Table:#{Integer(sheet_row)}",
            source_locator: "1XqeIbwQrr95oPO3Auo1BGG-nkYznhGJq1eESk9oPfpM/2025_full_Table",
            account_alias: account.to_s.strip,
            transaction_date: transaction_date,
            posted_at: nil,
            reporting_date: transaction_date,
            name: required_string!(description, "description"),
            merchant: nil,
            amount: parsed_amount,
            currency: "USD",
            pending: false,
            source_categories: {
              "JPW" => required_string!(jpw_category, "JPW category"),
              "WDG" => required_string!(wdg_category, "WDG category")
            }.freeze,
            provider_transaction_id: nil,
            provider_account_id: nil,
            raw_payload: {
              "date" => date.to_s,
              "description" => description.to_s,
              "jpw_category" => jpw_category.to_s,
              "wdg_category" => wdg_category.to_s,
              "transaction_type" => transaction_type.to_s,
              "amount" => amount.to_s,
              "account" => account.to_s
            }.freeze
          )
        rescue ArgumentError => error
          raise InvalidRow, error.message
        end

        def from_2026_consolidated(sheet:, sheet_row:, date:, posted_at:, name:, merchant:,
                                   amount:, currency:, pending:, channel: nil, primary_category:,
                                   detailed_category:, transaction_id:, account_id:, account_name:)
          validate_account!(sheet)
          validate_currency!(currency)

          transaction_date = parse_date!(date)
          parsed_posted_at = parse_time(posted_at)

          new(
            source_key: "#{sheet}:#{Integer(sheet_row)}:#{required_string!(transaction_id, "transaction ID")}",
            source_locator: "1Vxfpo9Kt0dj_yLX7xOxb6BiAxPRN2y5aPWyTSDddZLA/#{sheet}",
            account_alias: sheet.to_s.strip,
            transaction_date: transaction_date,
            posted_at: parsed_posted_at,
            reporting_date: parsed_posted_at&.to_date || transaction_date,
            name: required_string!(name, "name"),
            merchant: merchant.to_s.strip.presence,
            amount: parse_amount!(amount),
            currency: currency.to_s.upcase,
            pending: parse_boolean(pending),
            source_categories: {
              "Source Provider" => detailed_category.to_s.strip.presence || primary_category.to_s.strip.presence
            }.compact.freeze,
            provider_transaction_id: transaction_id.to_s,
            provider_account_id: required_string!(account_id, "account ID"),
            raw_payload: {
              "date" => date.to_s,
              "posted_at" => posted_at.to_s,
              "name" => name.to_s,
              "merchant" => merchant.to_s,
              "amount" => amount.to_s,
              "currency" => currency.to_s,
              "pending" => pending.to_s,
              "channel" => channel.to_s,
              "primary_category" => primary_category.to_s,
              "detailed_category" => detailed_category.to_s,
              "transaction_id" => transaction_id.to_s,
              "account_id" => account_id.to_s,
              "account_name" => account_name.to_s
            }.freeze
          )
        rescue ArgumentError => error
          raise InvalidRow, error.message
        end

        private
          def parse_amount!(value)
            text = value.to_s.strip
            negative_parentheses = text.start_with?("(") && text.end_with?(")")
            normalized = text.delete("$,").delete_prefix("(").delete_suffix(")")
            amount = BigDecimal(normalized)
            negative_parentheses ? -amount.abs : amount
          rescue ArgumentError
            raise InvalidRow, "invalid amount"
          end

          def parse_date!(value)
            return value if value.instance_of?(Date)
            return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

            text = required_string!(value, "date")
            format = text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z}) ? "%m/%d/%Y" : "%Y-%m-%d"
            Date.strptime(text, format)
          rescue Date::Error
            raise InvalidRow, "invalid date"
          end

          def parse_time(value)
            return if value.blank?
            return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

            Time.iso8601(value.to_s)
          rescue ArgumentError
            begin
              parse_date!(value).in_time_zone
            rescue InvalidRow
              raise InvalidRow, "invalid posted date"
            end
          end

          def parse_boolean(value)
            ActiveModel::Type::Boolean.new.cast(value)
          end

          def required_string!(value, label)
            value.to_s.strip.presence || raise(InvalidRow, "missing #{label}")
          end

          def validate_account!(value)
            required_string!(value, "account")
          end

          def validate_currency!(value)
            currency = required_string!(value, "currency").upcase
            raise InvalidRow, "unsupported currency #{currency}" unless currency == "USD"
          end
      end
    end
  end
end
