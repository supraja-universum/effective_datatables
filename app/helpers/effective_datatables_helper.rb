module EffectiveDatatablesHelper
  def render_datatable(datatable, input_js_options = nil)
    return unless datatable.present?
    datatable.view ||= self

    render partial: 'effective/datatables/datatable',
      locals: { datatable: datatable, input_js_options: input_js_options.try(:to_json) }
  end

  def render_datatable_scopes(datatable)
    return unless datatable.scopes.present?
    datatable.view ||= self

    render partial: 'effective/datatables/scopes', locals: { datatable: datatable }
  end

  def render_datatable_charts(datatable)
    return unless datatable.charts.present?
    datatable.view ||= self

    datatable.charts.map { |name, _| render_datatable_chart(datatable, name) }.join.html_safe
  end

  def render_datatable_chart(datatable, name)
    return unless datatable.charts.present?
    return unless datatable.charts[name].present?
    datatable.view ||= self

    unless @effective_datatables_chart_javascript_rendered
      concat javascript_include_tag('https://www.google.com/jsapi')
      concat javascript_tag("if(google && google.visualization === undefined) { google.load('visualization', '1', {packages:#{EffectiveDatatables.google_chart_packages}}); }")

      @effective_datatables_chart_javascript_rendered = true
    end

    options = datatable.charts[name]
    chart = datatable.to_json[:charts][name]

    render partial: (options[:partial] || 'effective/datatables/chart'),
      locals: { datatable: datatable, chart: chart }
  end

  def render_simple_datatable(datatable, input_js_options = nil)
    return unless datatable.present?
    datatable.view ||= self
    datatable.simple = true

    render partial: 'effective/datatables/datatable',
      locals: {datatable: datatable, input_js_options: input_js_options.try(:to_json) }
  end

  def datatable_default_order(datatable)
    [datatable.order_index, datatable.order_direction.downcase].to_json()
  end

  # https://datatables.net/reference/option/columns
  def datatable_columns(datatable)
    form = nil
    simple_form_for(:datatable_filter, url: '#', html: {id: "#{datatable.to_param}-form"}) { |f| form = f }

    datatable.table_columns.map do |name, options|
      {
        name: options[:name],
        title: content_tag(:span, options[:label], class: 'filter-label'),
        className: options[:class],
        width: options[:width],
        responsivePriority: (options[:responsivePriority] || 10000),  # 10,000 is datatables default
        sortable: (options[:sortable] && !datatable.simple?),
        visible: (options[:visible].respond_to?(:call) ? datatable.instance_exec(&options[:visible]) : options[:visible]),
        filterHtml: (datatable_header_filter(form, name, datatable.search_terms[name], options) unless datatable.simple?),
        filterSelectedValue: options[:filter][:selected]
      }
    end.to_json()
  end

  def datatable_bulk_actions(datatable)
    bulk_actions_column = datatable.table_columns.find { |_, options| options[:bulk_actions_column] }.try(:second)
    return false unless bulk_actions_column

    {
      dropdownHtml: render(
        partial: bulk_actions_column[:dropdown_partial],
        locals: { datatable: datatable, dropdown_block: bulk_actions_column[:dropdown_block] }.merge(bulk_actions_column[:partial_locals])
      )
    }.to_json()
  end

  def datatable_header_filter(form, name, value, opts)
    return render(partial: opts[:header_partial], locals: {form: form, name: (opts[:label] || name), column: opts}) if opts[:header_partial].present?

    include_blank = opts[:filter].key?(:include_blank) ? opts[:filter][:include_blank] : (opts[:label] || name.titleize)
    placeholder = opts[:filter].key?(:placeholder) ? opts[:filter][:placeholder] : (opts[:label] || name.titleize)

    case opts[:filter][:as]
    when :string, :text, :number
      form.input name, label: false, required: false, value: value,
        as: :string,
        placeholder: placeholder,
        input_html: { name: nil, value: value, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index]} }
    when :date
      form.input name, label: false, required: false, value: value,
        as: (ActionView::Helpers::FormBuilder.instance_methods.include?(:effective_date_picker) ? :effective_date_picker : :string),
        placeholder: placeholder,
        input_group: false,
        input_html: { name: nil, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index]} },
        input_js: { useStrict: true, keepInvalid: true }
    when :datetime
      form.input name, label: false, required: false, value: value,
        as: (ActionView::Helpers::FormBuilder.instance_methods.include?(:effective_date_time_picker) ? :effective_date_time_picker : :string),
        placeholder: placeholder,
        input_group: false,
        input_html: { name: nil, value: value, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index]} },
        input_js: { useStrict: true, keepInvalid: true } # Keep invalid format like "2015-11" so we can still filter by year, month or day
    when :select, :boolean
      form.input name, label: false, required: false, value: value,
        as: (ActionView::Helpers::FormBuilder.instance_methods.include?(:effective_select) ? :effective_select : :select),
        collection: opts[:filter][:collection],
        selected: opts[:filter][:selected],
        multiple: opts[:filter][:multiple] == true,
        include_blank: include_blank,
        input_html: { name: nil, value: value, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index]} },
        input_js: { placeholder: placeholder }
    when :grouped_select
      form.input name, label: false, required: false, value: value,
        as: (ActionView::Helpers::FormBuilder.instance_methods.include?(:effective_select) ? :effective_select : :grouped_select),
        collection: opts[:filter][:collection],
        selected: opts[:filter][:selected],
        multiple: opts[:filter][:multiple] == true,
        include_blank: include_blank,
        grouped: true,
        polymorphic: opts[:filter][:polymorphic] == true,
        group_label_method: opts[:filter][:group_label_method] || :first,
        group_method: opts[:filter][:group_method] || :last,
        input_html: { name: nil, value: value, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index]} },
        input_js: { placeholder: placeholder }
    when :bulk_actions_column
      form.input name, label: false, required: false, value: nil,
        as: :boolean,
        input_html: { name: nil, value: nil, autocomplete: 'off', data: {'column-name' => opts[:name], 'column-index' => opts[:index], 'role' => 'bulk-actions-all'} }
    end
  end

  def datatables_admin_path?
    @datatables_admin_path ||= (
      path = request.path.to_s.downcase.chomp('/') + '/'
      referer = request.referer.to_s.downcase.chomp('/') + '/'
      (attributes[:admin_path] || referer.include?('/admin/') || path.include?('/admin/')) rescue false
    )
  end

  # TODO: Improve on this
  def datatables_active_admin_path?
    attributes[:active_admin_path] rescue false
  end

end
