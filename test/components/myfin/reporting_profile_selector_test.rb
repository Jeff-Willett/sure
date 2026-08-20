require "test_helper"

class Myfin::ReportingProfileSelectorTest < ViewComponent::TestCase
  setup do
    @family = families(:dylan_family)
    Myfin::BootstrapFamily.call(family: @family)
    @profiles = @family.myfin_reporting_profiles.order(:name).to_a
    @current = @profiles.find { |profile| profile.name == "Green Capital Investing" }
  end

  test "shows the selected profile and current family options in a menu" do
    render_inline(Myfin::ReportingProfileSelector.new(current_profile: @current, profiles: @profiles))

    assert_selector "button[aria-label='Reporting profile: Green Capital Investing']"
    assert_selector "[role='menu']"
    assert_equal @profiles.length, page.all("form button[role='menuitemradio']").length
    assert_selector "button[role='menuitemradio'][aria-checked='true']", text: "Green Capital Investing"
  end

  test "does not render a profile from another family" do
    other = Myfin::ReportingProfile.create!(family: families(:empty), name: "Other family")

    render_inline(Myfin::ReportingProfileSelector.new(current_profile: @current, profiles: @profiles))

    assert_no_text other.name
  end
end
