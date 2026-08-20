module Myfin
  module ClassificationSheet
    class ProposalEngine
      def self.call(entry:, index:)
        new(entry:, index:).call
      end

      def initialize(entry:, index:)
        @entry = entry
        @index = index
      end

      def call
        return payment_proposal if entry.transaction.kind == "cc_payment"
        return transfer_proposal if entry.transaction.kind == "funds_movement"

        examples = index.examples_for(entry)
        return Proposal.new(wdg: nil, jpw: nil, confidence: "none", status: "Needs input", evidence: "No historical match") if examples.empty?

        pair_counts = examples.tally
        pair, count = pair_counts.max_by { |candidate, candidate_count| [ candidate_count, candidate.wdg, candidate.jpw ] }
        agreement = count.fdiv(examples.length)
        high = examples.length >= 3 && agreement == 1.0

        Proposal.new(
          wdg: pair.wdg,
          jpw: pair.jpw,
          confidence: high ? "high" : "suggested",
          status: high ? "High confidence" : "Suggested",
          evidence: "#{examples.length} examples, #{(agreement * 100).round}% agreement"
        )
      end

      private
        attr_reader :entry, :index

        def payment_proposal
          Proposal.new(wdg: "Transfer", jpw: "Credit Card Payment", confidence: "high", status: "High confidence", evidence: "Transaction kind is credit-card payment")
        end

        def transfer_proposal
          Proposal.new(wdg: "Transfer", jpw: "Credit Card Payment", confidence: "high", status: "High confidence", evidence: "Transaction kind is transfer")
        end
    end
  end
end
