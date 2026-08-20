require "json"

module MyfinImportTasks
  SOURCE_READERS = {
    "2025_wdg" => "Myfin::Imports::Workbook2025Reader",
    "2026_consolidated" => "Myfin::Imports::Workbook2026Reader"
  }.freeze

  module_function

  def inputs
    family_id = required_env!("FAMILY_ID")
    source_kind = required_env!("SOURCE_KIND")
    file = required_env!("FILE")
    reader_name = SOURCE_READERS.fetch(source_kind) do
      raise ArgumentError, "SOURCE_KIND must be 2025_wdg or 2026_consolidated"
    end
    raise ArgumentError, "FILE does not exist" unless File.file?(file)

    {
      family: Family.find(family_id),
      file: file,
      rows: reader_name.constantize.call(file: file)
    }
  end

  def dry_run(input)
    counts = Hash.new(0)
    reasons = Hash.new(0)

    input.fetch(:rows).each do |row|
      account = Myfin::Imports::AccountResolver.call(family: input.fetch(:family), row: row)
      result = Myfin::Imports::Reconciler.call(account: account, row: row)
      counts[result.decision] += 1
      reasons[result.match_method] += 1 if result.decision == "review"
    rescue Myfin::Imports::UnknownAccount
      counts["review"] += 1
      reasons["unknown_account"] += 1
    rescue Myfin::Imports::AmbiguousAccount
      counts["review"] += 1
      reasons["ambiguous_account"] += 1
    end

    { total: input.fetch(:rows).length, counts: counts, review_reasons: reasons }
  end

  def apply(input)
    source = Myfin::Imports::BatchRunner::Source.new(
      kind: "google_sheet",
      locator: input.fetch(:rows).first&.source_locator || "empty_workbook",
      fingerprint: Digest::SHA256.file(input.fetch(:file)).hexdigest
    )
    batch = Myfin::Imports::BatchRunner.call(
      family: input.fetch(:family),
      source: source,
      rows: input.fetch(:rows)
    )

    { batch_id: batch.id, status: batch.status, counts: batch.counts }
  end

  def required_env!(name)
    ENV.fetch(name).presence || raise(ArgumentError, "#{name} is required")
  end
end

namespace :myfin do
  namespace :imports do
    desc "Read and reconcile a MyFIN workbook without writing"
    task dry_run: :environment do
      puts JSON.generate(MyfinImportTasks.dry_run(MyfinImportTasks.inputs))
    end

    desc "Import a validated MyFIN workbook"
    task apply: :environment do
      abort "APPLY=1 is required" unless ENV["APPLY"] == "1"

      puts JSON.generate(MyfinImportTasks.apply(MyfinImportTasks.inputs))
    end
  end
end
