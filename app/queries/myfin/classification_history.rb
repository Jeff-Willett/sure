module Myfin
  class ClassificationHistory
    DEFAULT_LIMIT = 50

    def self.for_entry(user:, entry:)
      accessible_changes(user)
        .where(transaction_id: entry.transaction_id)
        .order(created_at: :desc, id: :desc)
    end

    def self.recent(user:, cursor: nil, limit: DEFAULT_LIMIT)
      scope = accessible_changes(user).order(created_at: :desc, id: :desc)
      scope = before(scope, cursor) if cursor.present?
      scope.limit(limit)
    end

    def self.accessible_changes(user)
      ClassificationChange
        .where(family: user.family)
        .joins(sure_transaction: :entry)
        .where(entries: { account_id: user.accessible_accounts.select(:id) })
        .includes(:actor, :category_scheme, :previous_category, :new_category, :reverted_change)
    end
    private_class_method :accessible_changes

    def self.before(scope, cursor)
      created_at, id = cursor
      scope.where(
        "myfin_classification_changes.created_at < :created_at OR " \
        "(myfin_classification_changes.created_at = :created_at AND myfin_classification_changes.id < :id)",
        created_at: created_at,
        id: id
      )
    end
    private_class_method :before
  end
end
