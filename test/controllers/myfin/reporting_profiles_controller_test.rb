require "test_helper"

class Myfin::ReportingProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    Myfin::BootstrapFamily.call(family: @user.family)
  end

  test "selects a profile from the current family" do
    profile = @user.family.myfin_reporting_profiles.find_by!(name: "Green Capital Investing")

    patch myfin_reporting_profile_path, params: { profile_id: profile.id }

    assert_redirected_to root_path
  end

  test "does not select a profile from another family" do
    profile = Myfin::ReportingProfile.create!(
      family: families(:empty),
      name: "Other family",
      is_default: true
    )

    patch myfin_reporting_profile_path, params: { profile_id: profile.id }

    assert_response :not_found
  end
end
