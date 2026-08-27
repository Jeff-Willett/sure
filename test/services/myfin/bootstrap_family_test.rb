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
    assert_equal [ "DIS", "GCI", "JPW", "Source Provider", "WDG" ],
      family.myfin_category_schemes.order(:name).pluck(:name)
    assert_equal({
      "DIS" => "Donna",
      "GCI" => "Green Capital Investing",
      "JPW" => "JPW Personal",
      "Source Provider" => nil,
      "WDG" => nil
    }, family.myfin_category_schemes.includes(:entity).order(:name).to_h { |scheme| [ scheme.name, scheme.entity&.name ] })
    assert_equal %w[DIS GCI JPW],
      family.myfin_category_schemes.where(is_default: true).order(:name).pluck(:name)
    assert_equal [
      "Donna",
      "Everything",
      "Green Capital Investing",
      "JPW Personal",
      "WDG Report"
    ], family.myfin_reporting_profiles.order(:name).pluck(:name)
    assert_equal 1, family.myfin_reporting_profiles.where(is_default: true).count
  end

  test "assigns the expected entities to every reporting profile" do
    family = families(:dylan_family)

    Myfin::BootstrapFamily.call(family: family)

    expected = {
      "JPW Personal" => [ "JPW Personal" ],
      "WDG Report" => [ "JPW Personal" ],
      "Green Capital Investing" => [ "Green Capital Investing" ],
      "Donna" => [ "Donna" ],
      "Everything" => [ "Danielle", "Donna", "Green Capital Investing", "JPW Personal" ]
    }

    expected.each do |profile_name, entity_names|
      profile = family.myfin_reporting_profiles.find_by!(name: profile_name)
      assert_equal entity_names, profile.entities.order(:name).pluck(:name)
    end

    assert_equal({
      "Donna" => "DIS",
      "Everything" => nil,
      "Green Capital Investing" => "GCI",
      "JPW Personal" => "JPW",
      "WDG Report" => "WDG"
    }, family.myfin_reporting_profiles.includes(:preferred_category_scheme).order(:name).to_h do |profile|
      [ profile.name, profile.preferred_category_scheme&.name ]
    end)
  end

  test "renames the legacy personal profile instead of duplicating it" do
    family = families(:dylan_family)
    legacy = family.myfin_reporting_profiles.create!(name: "My Personal Finances", is_default: true)

    Myfin::BootstrapFamily.call(family: family)

    assert_nil family.myfin_reporting_profiles.find_by(name: "My Personal Finances")
    assert_equal legacy.id, family.myfin_reporting_profiles.find_by!(name: "JPW Personal").id
  end
end
