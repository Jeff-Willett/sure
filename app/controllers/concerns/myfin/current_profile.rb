module Myfin
  module CurrentProfile
    extend ActiveSupport::Concern

    included do
      helper_method :current_myfin_profile
    end

    private
      def current_myfin_profile
        return if Current.family.nil?

        @current_myfin_profile ||= begin
          profiles = Current.family.myfin_reporting_profiles
          profiles.find_by(id: session[:myfin_reporting_profile_id]) ||
            profiles.find_by(is_default: true) ||
            profiles.order(:name).first
        end
      end
  end
end
