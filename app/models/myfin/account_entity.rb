module Myfin
  class AccountEntity < ApplicationRecord
    self.table_name = "myfin_account_entities"

    ROLES = %w[owner joint_owner custodian reporting_only].freeze

    belongs_to :account
    belongs_to :entity, class_name: "Myfin::Entity", inverse_of: :account_entities

    validates :role, inclusion: { in: ROLES }
    validates :ownership_percent,
      numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validate :entity_belongs_to_account_family
    validate :period_is_ordered

    private
      def entity_belongs_to_account_family
        return if account.nil? || entity.nil? || account.family_id == entity.family_id

        errors.add(:entity, "must belong to the account family")
      end

      def period_is_ordered
        return if starts_on.nil? || ends_on.nil? || ends_on >= starts_on

        errors.add(:ends_on, "must be on or after the start date")
      end
  end
end
