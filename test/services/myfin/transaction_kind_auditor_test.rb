require "test_helper"

class MyfinTransactionKindAuditorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @credit_card = accounts(:credit_card)
    @checking = accounts(:depository)
  end

  test "dry run identifies only unsupported credit card payments" do
    refund = import(@credit_card, amount: -49.21, name: "Walmart refund", kind: "cc_payment")
    payment = import(@checking, amount: 500, name: "Card autopay", kind: "cc_payment")

    result = Myfin::TransactionKindAuditor.call(family: @family)

    assert_equal [ refund.id ], result.entry_ids
    assert_equal 1, result.candidate_count
    assert_equal 0, result.repaired_count
    assert_equal "cc_payment", refund.transaction.reload.kind
    assert_equal "cc_payment", payment.transaction.reload.kind
  end

  test "apply changes unsupported credit card payments to standard" do
    refund = import(@credit_card, amount: -74.64, name: "Merchant credit", kind: "cc_payment")

    result = Myfin::TransactionKindAuditor.call(family: @family, apply: true)

    assert_equal 1, result.repaired_count
    assert_equal "standard", refund.transaction.reload.kind
  end

  private
    def import(account, amount:, name:, kind:)
      entry = Account::ProviderImportAdapter.new(account).import_transaction(
        external_id: "audit_#{SecureRandom.hex(6)}",
        amount: amount,
        currency: "USD",
        date: Date.current,
        name: name,
        source: "simplefin",
        kind: kind
      )
      entry.transaction.update!(kind: kind)
      entry
    end
end
