class PreviewSessionsController < ApplicationController
  skip_authentication only: :create

  def create
    return head :not_found unless preview_login_enabled?

    user = User.find_by(email: ENV["TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL"].to_s)
    return head :not_found unless user

    create_session_for(user)
    redirect_to myfin_transaction_explorer_path
  end

  private
    def preview_login_enabled?
      Rails.env.test? &&
        ActiveModel::Type::Boolean.new.cast(ENV["TRANSACTION_EXPLORER_PREVIEW_LOGIN"]) &&
        ENV["TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL"].present?
    end
end
