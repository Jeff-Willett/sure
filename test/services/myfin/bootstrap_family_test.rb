require "test_helper"

class MyfinBootstrapFamilyTest < ActiveSupport::TestCase
  test "creates the initial entities schemes and profiles once" do
    family = families(:dylan_family)

    first = Myfin::BootstrapFamily.call(family: family)
    second = Myfin::BootstrapFamily.call(family: family)

    assert_equal 4, first.created_entities
    assert_equal 0, second.created_entities
    assert_equal [ "Danielle", "Donna", "Green Capital Investing", "JPW Personal" ],
      family.myfin_entities.order(:name).pluck(:name)
    assert_equal [ "JPW", "Source Provider", "WDG" ],
      family.myfin_category_schemes.order(:name).pluck(:name)
    assert_equal [
      "Combined Household",
      "Danielle",
      "Donna",
      "Everything",
      "Green Capital Investing",
      "My Personal Finances"
    ], family.myfin_reporting_profiles.order(:name).pluck(:name)
    assert_equal 1, family.myfin_reporting_profiles.where(is_default: true).count
  end

  test "assigns the expected entities to every reporting profile" do
    family = families(:dylan_family)

    Myfin::BootstrapFamily.call(family: family)

    expected = {
      "My Personal Finances" => [ "JPW Personal" ],
      "Green Capital Investing" => [ "Green Capital Investing" ],
      "Donna" => [ "Donna" ],
      "Danielle" => [ "Danielle" ],
      "Combined Household" => [ "Danielle", "Donna", "JPW Personal" ],
      "Everything" => [ "Danielle", "Donna", "Green Capital Investing", "JPW Personal" ]
    }

    expected.each do |profile_name, entity_names|
      profile = family.myfin_reporting_profiles.find_by!(name: profile_name)
      assert_equal entity_names, profile.entities.order(:name).pluck(:name)
    end
  end
end
