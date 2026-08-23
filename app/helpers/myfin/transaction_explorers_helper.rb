module Myfin::TransactionExplorersHelper
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
