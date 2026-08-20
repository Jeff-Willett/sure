require "test_helper"

class MyfinImportsAccountResolverTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @item = SimplefinItem.create!(
      family: @family,
      name: "Test SimpleFIN Connection",
      access_url: "https://example.com/access"
    )
  end

  test "resolves every approved alias to its linked account suffix" do
    expected = {
      "Freedom" => "2788",
      "Checking Account" => "6626",
      "Marriott" => "8188",
      "Amazon" => "8748",
      "Chase Business Chk •2286" => "2286",
      "Chase Ultimate •2788" => "2788",
      "Chase Savings •5387" => "5387",
      "Chase Total Chk •6626" => "6626",
      "Chase Marriott •8188" => "8188",
      "Chase Ultimate •8501" => "8501",
      "Chase Prime Visa •8748" => "8748"
    }
    accounts_by_suffix = expected.values.uniq.index_with { |suffix| create_linked_account(suffix) }

    expected.each do |alias_name, suffix|
      row = Struct.new(:account_alias, :provider_account_id).new(alias_name, nil)
      resolved = Myfin::Imports::AccountResolver.call(family: @family, row: row)

      assert_equal accounts_by_suffix.fetch(suffix), resolved, alias_name
    end
  end

  test "unknown aliases fail without creating an account" do
    row = Struct.new(:account_alias, :provider_account_id).new("Unknown Card", nil)

    assert_no_difference("Account.count") do
      assert_raises(Myfin::Imports::UnknownAccount) do
        Myfin::Imports::AccountResolver.call(family: @family, row: row)
      end
    end
  end

  private
    def create_linked_account(suffix)
      simplefin_account = SimplefinAccount.create!(
        simplefin_item: @item,
        name: "Chase Account (#{suffix})",
        account_id: "simplefin-account-#{suffix}",
        currency: "USD",
        account_type: "checking",
        current_balance: 100
      )
      Account.create_from_simplefin_account(simplefin_account, "Depository")
    end
end
