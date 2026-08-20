module Myfin
  module Imports
    class NameNormalizer
      TRAILING_REFERENCE = /(?:\s|\*)+#?\d{3,}\z/

      def self.call(value)
        value.to_s
          .unicode_normalize(:nfkc)
          .downcase
          .gsub(TRAILING_REFERENCE, "")
          .gsub(/[^\p{Alnum}]+/, " ")
          .squish
      end
    end
  end
end
