require "test_helper"

class MyfinClassificationSheetProposalEngineTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:credit_card)
    Myfin::BootstrapFamily.call(family: @family)
  end

  test "three unanimous merchant examples produce high confidence" do
    3.times { |index| create_example("Walmart - WALMART.COM #{index}", "Shopping", "Shopping") }

    proposal = propose("Walmart - WM SUPERCENTER #528")

    assert_equal "Shopping", proposal.wdg
    assert_equal "Shopping", proposal.jpw
    assert_equal "high", proposal.confidence
    assert_equal "High confidence", proposal.status
  end

  test "conflicting examples remain suggestions" do
    create_example("Amazon - Amazon.com 1", "Shopping", "Shopping")
    create_example("Amazon - Amazon.com 2", "Shopping", "Donna")

    proposal = propose("Amazon - Amazon.com")

    assert_equal "Suggested", proposal.status
    assert_match(/2 examples/, proposal.evidence)
  end

  test "payments use the established payment categories" do
    proposal = propose("Automatic Credit Card Payment", amount: -500, kind: "cc_payment")

    assert_equal "Transfer", proposal.wdg
    assert_equal "Credit Card Payment", proposal.jpw
    assert_equal "high", proposal.confidence
  end

  private
    def create_example(name, wdg, jpw)
      entry = create_entry(name)
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "WDG" => wdg, "JPW" => jpw }
      )
    end

    def propose(name, amount: 25, kind: "standard")
      entry = create_entry(name, amount:, kind:)
      index = Myfin::ClassificationSheet::TrainingIndex.build(family: @family, ignore_entry_ids: [ entry.id ])
      Myfin::ClassificationSheet::ProposalEngine.call(entry:, index:)
    end

    def create_entry(name, amount: 25, kind: "standard")
      Account::ProviderImportAdapter.new(@account).import_transaction(
        external_id: "proposal_#{SecureRandom.hex(8)}",
        amount: amount,
        currency: "USD",
        date: Date.current,
        name: name,
        source: "simplefin",
        kind: kind
      ).tap { |entry| entry.transaction.update!(kind: kind) }
    end
end
