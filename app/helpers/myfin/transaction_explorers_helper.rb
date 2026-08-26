module Myfin::TransactionExplorersHelper
  def transaction_explorer_tabulator_rows(rows)
    rows.map do |row|
      {
        id: row.entry_id,
        workflow_status: row.classification_status.to_s.humanize,
        open_url: myfin_entry_classification_changes_path(row.entry_id),
        type: row.type,
        date: row.date.iso8601,
        entity: row.entity_names.join(", "),
        wdg_rollup: row.wdg_rollup || t("myfin.transaction_explorer.not_applicable"),
        detail_category: row.detail_category,
        tags: row.tag_names.join(", "),
        description: row.description,
        account: row.account_name,
        amount: row.amount.to_f,
        amount_display: format_money(Money.new(row.amount, Current.family.currency)),
        editable: row.editable
      }
    end
  end

  TransactionExplorerColumn = Data.define(:key, :default_width, :min_width)
  TRANSACTION_EXPLORER_COLUMNS = {
    "date" => TransactionExplorerColumn.new(key: "date", default_width: 140, min_width: 96),
    "entity" => TransactionExplorerColumn.new(key: "entity", default_width: 84, min_width: 64),
    "wdg_rollup" => TransactionExplorerColumn.new(key: "wdg_rollup", default_width: 180, min_width: 140),
    "detail_category" => TransactionExplorerColumn.new(key: "detail_category", default_width: 180, min_width: 140),
    "tags" => TransactionExplorerColumn.new(key: "tags", default_width: 240, min_width: 180),
    "description" => TransactionExplorerColumn.new(key: "description", default_width: 360, min_width: 220),
    "account" => TransactionExplorerColumn.new(key: "account", default_width: 220, min_width: 160),
    "amount" => TransactionExplorerColumn.new(key: "amount", default_width: 150, min_width: 120)
  }.freeze

  def transaction_explorer_columns(report = @report)
    keys = case report&.profile_name
    when "Donna", "Green Capital Investing"
      %w[date entity detail_category tags description account amount]
    when "Everything"
      %w[date entity wdg_rollup detail_category tags description account amount]
    else
      %w[date entity wdg_rollup detail_category tags description account amount]
    end

    keys.map { |key| TRANSACTION_EXPLORER_COLUMNS.fetch(key) }
  end

  def transaction_explorer_scheme_ids
    @transaction_explorer_scheme_ids ||= Current.family.myfin_category_schemes
      .where(name: %w[JPW DIS GCI])
      .pluck(:name, :id)
      .to_h
  end

  ROLLUP_EMOJI_RULES = [
    [ /camp/, "🏕️" ],
    [ /\brv\b/, "🚐" ],
    [ /grocer/, "🛒" ],
    [ /shopping/, "🛍️" ],
    [ /restaurant|dining|food/, "🍽️" ],
    [ /rent|home living|housing|storage/, "🏠" ],
    [ /health|medical|dental/, "🩺" ],
    [ /auto|vehicle|transport/, "🚗" ],
    [ /cellphone|mobile|phone/, "📱" ],
    [ /internet|broadband/, "🌐" ],
    [ /software|digital/, "💻" ],
    [ /professional|bookkeep|accounting/, "🧾" ],
    [ /pml|investment|portfolio/, "📈" ],
    [ /line of credit|\bloc\b|loan|debt|interest/, "🏦" ],
    [ /contribution/, "💰" ],
    [ /transfer/, "🔄" ],
    [ /income|deposit|payroll/, "💵" ],
    [ /exclude/, "🚫" ],
    [ /office|business/, "💼" ],
    [ /utility|electric|water|gas/, "💡" ],
    [ /travel|flight|hotel/, "✈️" ],
    [ /entertainment|activity|event/, "🎟️" ],
    [ /gift|donation/, "🎁" ],
    [ /subscription/, "🔁" ],
    [ /fuel/, "⛽" ],
    [ /education|school/, "🎓" ],
    [ /pet/, "🐾" ],
    [ /child|kid/, "🧸" ],
    [ /insurance/, "🛡️" ],
    [ /fee|tax/, "🧾" ]
  ].freeze

  def transaction_explorer_rollup_emoji(label)
    normalized_label = label.to_s.downcase
    ROLLUP_EMOJI_RULES.find { |pattern, _emoji| pattern.match?(normalized_label) }&.last || "🏷️"
  end
end
