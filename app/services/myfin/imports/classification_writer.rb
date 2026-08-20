module Myfin
  module Imports
    class ClassificationWriter
      def self.call(sure_transaction:, classifications:)
        new(sure_transaction, classifications).call
      end

      def initialize(sure_transaction, classifications)
        @sure_transaction = sure_transaction
        @classifications = classifications
      end

      def call
        sure_transaction.with_lock do
          classifications.each do |scheme_name, category_name|
            next if category_name.blank?

            write_classification!(scheme_name, category_name)
          end
        end

        sure_transaction.myfin_classifications.reload
      end

      private
        attr_reader :sure_transaction, :classifications

        def family
          sure_transaction.entry.account.family
        end

        def write_classification!(scheme_name, category_name)
          scheme = family.myfin_category_schemes.find_by!(name: scheme_name)
          scheme_category = scheme.scheme_categories.find_or_create_by!(
            name: category_name.to_s.strip,
            parent: nil
          )
          classification = sure_transaction.myfin_classifications
            .find_or_initialize_by(category_scheme: scheme)
          classification.assign_attributes(
            scheme_category: scheme_category,
            classification_source: "imported",
            confidence: 1
          )
          classification.save!

          mirror_wdg_to_sure!(category_name) if scheme_name == "WDG"
        end

        def mirror_wdg_to_sure!(category_name)
          native_category = family.categories.find_or_create_by!(name: category_name.to_s.strip)
          sure_transaction.update!(category: native_category)
        end
    end
  end
end
