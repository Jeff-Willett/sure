module Myfin
  class ClassificationEditor
    Result = Data.define(:classification, :change)

    class StaleClassification < StandardError; end
    class InvalidCategory < StandardError; end
    class InvalidRevert < StandardError; end
    class NotAuthorized < StandardError; end

    def self.call(entry:, scheme:, target_category:, expected_category:, actor:, source:, revert_of: nil)
      new(
        entry: entry,
        scheme: scheme,
        target_category: target_category,
        expected_category: expected_category,
        actor: actor,
        source: source,
        revert_of: revert_of
      ).call
    end

    def initialize(entry:, scheme:, target_category:, expected_category:, actor:, source:, revert_of:)
      @entry = entry
      @scheme = scheme
      @target_category = target_category
      @expected_category = expected_category
      @actor = actor
      @source = source
      @revert_of = revert_of
    end

    def call
      raise NotAuthorized unless entry.account.permission_for(actor).in?([ :owner, :full_control, :read_write ])

      TransactionClassification.transaction do
        sure_transaction.lock!
        validate_scheme!
        validate_category!(target_category)
        validate_category!(expected_category)

        classification = sure_transaction.myfin_classifications.lock.find_by(category_scheme: scheme)
        current_category = classification&.scheme_category
        target, expected, action = edit_attributes(current_category)

        raise StaleClassification unless current_category&.id == expected&.id

        change = ClassificationChange.create!(
          family: family,
          sure_transaction: sure_transaction,
          category_scheme: scheme,
          actor: actor,
          previous_category: current_category,
          previous_category_name: current_category&.name,
          new_category: target,
          new_category_name: target&.name,
          reverted_change: revert_of,
          action: action,
          source: source
        )

        classification = replace_classification!(classification, target)
        mirror_wdg_to_sure!(target) if wdg_scheme?

        Result.new(classification: classification, change: change)
      end
    end

    private
      attr_reader :entry, :scheme, :target_category, :expected_category, :actor, :source, :revert_of

      def sure_transaction
        @sure_transaction ||= entry.transaction
      end

      def family
        entry.account.family
      end

      def validate_scheme!
        raise InvalidCategory unless scheme&.family_id == family.id
      end

      def validate_category!(category)
        return if category.nil?

        raise InvalidCategory unless category.category_scheme_id == scheme.id
      end

      def edit_attributes(current_category)
        return [ target_category, expected_category, "edit" ] if revert_of.nil?

        validate_revert!
        [ revert_of.previous_category, current_category, "revert" ]
      end

      def validate_revert!
        latest_change = sure_transaction.myfin_classification_changes
          .where(category_scheme: scheme)
          .order(created_at: :desc, id: :desc)
          .first

        valid_revert = revert_of.persisted? &&
          revert_of.transaction_id == sure_transaction.id &&
          revert_of.category_scheme_id == scheme.id &&
          latest_change&.id == revert_of.id
        raise InvalidRevert unless valid_revert
      end

      def replace_classification!(classification, category)
        if category.nil?
          classification&.destroy!
          return nil
        end

        classification ||= sure_transaction.myfin_classifications.build(category_scheme: scheme)
        classification.update!(
          scheme_category: category,
          classification_source: "manual",
          confidence: 1,
          reviewed_at: Time.current,
          reviewed_by: actor
        )
        classification
      end

      def wdg_scheme?
        scheme.name == "WDG"
      end

      def mirror_wdg_to_sure!(category)
        native_category = if category
          family.categories.find_or_create_by!(name: category.name)
        end

        sure_transaction.update!(category: native_category)
      end
  end
end
