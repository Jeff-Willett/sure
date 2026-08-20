module Myfin
  class ReviewItemsController < ApplicationController
    before_action :set_review_item, except: :index

    def index
      authorize Myfin::ReviewItem
      @review_items = policy_scope(Myfin::ReviewItem)
        .where(status: "open")
        .includes(source_record: :import_batch)
        .order(created_at: :desc)
    end

    def show
      authorize @review_item
      @candidates = Current.accessible_entries
        .transactions
        .where(id: @review_item.candidate_entry_ids)
        .includes(:account)
      @accounts = Current.user.accessible_accounts.alphabetically
    end

    def match_existing
      authorize @review_item, :resolve?
      entry = Current.accessible_entries.transactions.find_by(id: params[:candidate_entry_id])
      raise Myfin::Imports::ReviewResolver::InvalidResolution, t("myfin.review_items.invalid_candidate") unless entry
      return unless require_account_permission!(entry.account, :annotate, redirect_path: myfin_review_item_path(@review_item))

      resolve!("match_existing", entry: entry)
    end

    def create_new
      authorize @review_item, :resolve?
      account = Current.user.accessible_accounts.find_by(id: params[:account_id])
      raise Myfin::Imports::ReviewResolver::InvalidResolution, t("myfin.review_items.invalid_account") unless account
      return unless require_account_permission!(account, :write, redirect_path: myfin_review_item_path(@review_item))

      resolve!("create_new", account: account)
    end

    def skip
      authorize @review_item, :resolve?
      resolve!("skip")
    end

    def dismiss_duplicate
      authorize @review_item, :resolve?
      resolve!("dismiss_duplicate")
    end

    private
      def set_review_item
        @review_item = policy_scope(Myfin::ReviewItem).find(params[:id])
      end

      def resolve!(action, **options)
        Myfin::Imports::ReviewResolver.call(
          review_item: @review_item,
          resolver: Current.user,
          action: action,
          **options
        )
        redirect_to myfin_review_item_path(@review_item), notice: t("myfin.review_items.resolved")
      end

      rescue_from Myfin::Imports::ReviewResolver::InvalidResolution do |error|
        render plain: t("myfin.review_items.invalid", message: error.message), status: :unprocessable_entity
      end
  end
end
