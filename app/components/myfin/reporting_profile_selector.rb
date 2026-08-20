module Myfin
  class ReportingProfileSelector < ApplicationComponent
    attr_reader :current_profile, :profiles

    def initialize(current_profile:, profiles:)
      @current_profile = current_profile
      @profiles = profiles
    end

    def selected?(profile)
      profile.id == current_profile.id
    end

    def update_path(profile)
      helpers.myfin_reporting_profile_path(profile_id: profile.id)
    end
  end
end
