module Myfin
  class ReviewItemPolicy < ApplicationPolicy
    def index?
      user.present?
    end

    def show?
      same_family?
    end

    def resolve?
      same_family?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        scope.where(family_id: user.family_id)
      end
    end

    private
      def same_family?
        user.present? && record.family_id == user.family_id
      end
  end
end
