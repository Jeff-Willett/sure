require "test_helper"

class MyfinTransactionSemanticsTest < ActiveSupport::TestCase
  test "labels credit card purchases and merchant credits by direction" do
    purchase = build_entry(accounts(:credit_card), 123.85, "standard")
    credit = build_entry(accounts(:credit_card), -49.21, "standard")

    assert_equal "purchase", Myfin::TransactionSemantics.label(purchase)
    assert_equal "refund_or_credit", Myfin::TransactionSemantics.label(credit)
  end

  test "labels depository activity and transfers" do
    expense = build_entry(accounts(:depository), 25, "standard")
    income = build_entry(accounts(:depository), -100, "standard")
    payment = build_entry(accounts(:depository), 500, "cc_payment")

    assert_equal "expense", Myfin::TransactionSemantics.label(expense)
    assert_equal "income", Myfin::TransactionSemantics.label(income)
    assert_equal "payment", Myfin::TransactionSemantics.label(payment)
  end

  private
    def build_entry(account, amount, kind)
      Account::ProviderImportAdapter.new(account).import_transaction(
        external_id: "semantics_#{SecureRandom.hex(6)}",
        amount: amount,
        currency: "USD",
        date: Date.current,
        name: "Test transaction",
        source: "simplefin",
        kind: kind
      ).tap { |entry| entry.transaction.update!(kind: kind) }
    end
end
