module Myfin
  class ReportingProfilesController < ApplicationController
    def update
      profile = Current.family.myfin_reporting_profiles.find(params.require(:profile_id))
      session[:myfin_reporting_profile_id] = profile.id

      redirect_back fallback_location: root_path
    end
  end
end
