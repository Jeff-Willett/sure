class DS::TagSelect < DesignSystemComponent
  attr_reader :form, :tags, :selected_ids, :disabled, :auto_submit, :update_url,
              :menu_placement, :offset, :spreadsheet_input

  MENU_PLACEMENTS = %w[auto down up].freeze

  def initialize(form:, tags:, selected_ids:, disabled: false, auto_submit: false,
                 update_url: nil, menu_placement: :auto, offset: 6, spreadsheet_input: false)
    @form = form
    @tags = tags
    @selected_ids = selected_ids.map(&:to_s)
    @disabled = disabled
    @auto_submit = auto_submit
    @update_url = update_url
    @menu_placement = normalize_menu_placement(menu_placement)
    @offset = offset
    @spreadsheet_input = spreadsheet_input
  end

  def field_name
    "#{form.object_name}[tag_ids][]"
  end

  def menu_id
    @menu_id ||= "tag_select_#{field_name.gsub(/\W+/, "_")}_#{object_id}"
  end

  def selected_tag_names
    tags.select { |tag| selected_ids.include?(tag.id.to_s) }.map(&:name)
  end

  private

    def normalize_menu_placement(value)
      normalized = value.to_s.downcase
      MENU_PLACEMENTS.include?(normalized) ? normalized : "auto"
    end
end
