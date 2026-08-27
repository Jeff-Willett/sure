require "benchmark"

runs = Integer(ENV.fetch("EXPLORER_BENCHMARK_RUNS", "10"))
user = User.find_by!(email: ENV.fetch("TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL"))
params = ActionController::Parameters.new({})
samples = []
query_counts = []

runs.times do
  query_count = 0
  callback = lambda do |_name, _started, _finished, _unique_id, payload|
    next if payload[:cached]
    next if payload[:name] == "SCHEMA"

    query_count += 1
  end
  elapsed = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
    Benchmark.realtime do
      Myfin::TransactionExplorersController.report_for(user: user, params: params)
    end
  end
  samples << elapsed
  query_counts << query_count
end

sorted = samples.sort
middle = sorted.size / 2
median = sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
puts JSON.generate(
  runs: runs,
  median_ms: (median * 1000).round(1),
  min_ms: (samples.min * 1000).round(1),
  max_ms: (samples.max * 1000).round(1),
  query_counts: query_counts
)
