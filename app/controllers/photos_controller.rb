require 'digest/sha1'

class PhotosController < ApplicationController
  before_action :authentication

  PICTURE_FLAG_DONE = "完了"
  SUMMARY_CACHE_VERSION = "v3"
  SUMMARY_CACHE_TTL = 10.minutes
  SUMMARY_SYSTEM_FIELDS = %w[$id レコード番号].freeze
  NUMBER_MEMO_TABLE_PATTERNS = [
    /杭長/,
    /杭材検寸.*(下端|頭端|上端)/
  ].freeze

  DETAIL_SECTIONS = [
    {
      title: "☆施工前状況",
      tables: %w[
        テーブル施工前敷地状況
        テーブル施工前_前面道路
        テーブル施工前_養生状況・施工機搬入
        テーブル看板
        テーブル管理装置の確認
        テーブルKY確認
        テーブル異常箇所
        テーブル隣接構造物確認
        テーブル設計GL・仮BM確認
      ]
    },
    {
      title: "☆配置確認",
      tables: %w[
        テーブル配置確認追い出し
        テーブル配置確認平行
        テーブル杭芯割付状況
      ]
    },
    {
      title: "☆杭材搬入",
      tables: %w[
        テーブル材料搬入
        テーブル刷り版
        テーブル杭材検寸全景
        テーブル杭材検寸断面
        テーブル杭材検寸杭下端部
        テーブル杭材検寸杭頭端部
        テーブル施工機全景
      ]
    },
    {
      title: "☆施工開始！",
      tables: %w[
        テーブル掘削長マーキング
        テーブル杭芯オーガーセット
        テーブル杭芯ずれ確認オーガー掘削時
        テーブルオーガー掘削
        テーブル最終掘削状況
        テーブル鉛直確認
        テーブル杭建て込み状況
        テーブル杭押込状況
        テーブル建て込み状況・下杭
        テーブル鉛直確認・下杭
        テーブル杭押し込み状況・下杭
        テーブル継ぎ手状況1
        テーブル建て込み状況・中杭
        テーブル継ぎ手状況2
        テーブル建て込み状況・上杭
        テーブル鉛直確認・上杭
        テーブル杭押し込み状況・上杭
        テーブル最終圧入
        テーブル打設後杭芯確認
        テーブル杭頭レベル確認
      ]
    },
    {
      title: "☆施工終了",
      tables: %w[
        テーブル清掃状況
        テーブル杭天端仕上げ確認
        テーブル完了整地状況
        テーブル施工後完了
        テーブル施工後敷地状況
        テーブル施工後道路状況
        テーブルデータ確認状況
        その他
      ]
    }
  ].freeze

  FIELD_ALIASES = {
    machine: %w[施工機 施工機通称 施工班通称 施工機名 施工班名 施工班 機械名 重機名],
    date: %w[施工予定日 日付 施工日 作業日 撮影日 予定日 開始日 日時 登録日時],
    company: %w[発注会社名 会社名 取引先名 顧客名 運用会社名 施工会社 施工会社名],
    branch: %w[支店 支店名 営業所 営業所名],
    site: %w[物件名 現場名 工事名 案件名],
    detail: %w[打設明細 明細 工事内容],
    address: %w[住所 現場住所 施工場所 場所],
    prefecture: %w[都道府県],
    county: %w[郡],
    city: %w[市町村],
    address_tail: %w[その他住所 以降住所 番地],
    photo_status: %w[写真完了フラグ 写真 写真状況 写真ステータス],
    management_status: %w[管理 管理状況 管理ステータス]
  }.freeze

  def index
    @machine_name = params[:machine].to_s.strip
    @machine_search_values = machine_search_values(@machine_name, params[:machine_model])
    @records = @machine_name.present? ? photo_records_for(@machine_search_values) : []
    @default_records = default_records(@records)
    @incomplete_records = @default_records.select { |record| incomplete?(record) }
    @date_tabs = date_tabs
    @records_by_date = @default_records.group_by { |record| schedule_bucket_date(record) }
    @completed_records = completed_records(@default_records)
    @future_records = future_records(@default_records, @date_tabs)
    @future_incomplete_count = @future_records.count { |record| incomplete?(record) }
    @selected_filter = selected_filter
    @selected_date = selected_date(@date_tabs)
    @selected_records = selected_records
    @field_keys = record_field_keys(@records)
    @field_preview = record_field_preview(@records)
  rescue StandardError => e
    Rails.logger.error("Photos kintone fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @records = []
    @default_records = []
    @incomplete_records = []
    @completed_records = []
    @future_records = []
    @future_incomplete_count = 0
    @records_by_date = {}
    @date_tabs = []
    @selected_records = []
  end

  def show
    @page_title = '施工写真詳細'
    @record = photo_record(params[:id])
    @machine_name = field_value(@record, :machine)
    @detail_sections = visible_detail_sections(@record)
    @field_keys = record_field_keys([@record])
    @field_preview = record_field_preview([@record])
  rescue StandardError => e
    Rails.logger.error("Photo detail fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @record = nil
    @detail_sections = []
  end

  def warm_cache
    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    available_field_codes(record_client)
    head :no_content
  rescue StandardError => e
    Rails.logger.warn("Photo summary cache warm failed: #{e.class}: #{e.message}")
    head :no_content
  end

  def add_table_row
    record = photo_record(params[:id])
    table_code = table_row_params[:table_code]
    rows = detail_table_rows(record, table_code).map { |row| kintone_table_row_payload(row) }
    rows << new_table_row_payload
    update_table_rows(params[:id], table_code, rows)

    redirect_to photo_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row add failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to photo_path(params[:id]), alert: "写真・メモの追加に失敗しました。"
  end

  def update_table_row
    record = photo_record(params[:id])
    table_code = table_row_params[:table_code]
    target_row_id = table_row_params[:row_id].to_s
    rows = detail_table_rows(record, table_code).map do |row|
      payload = kintone_table_row_payload(row)
      apply_table_row_params(payload, source_row: row) if row["id"].to_s == target_row_id
      payload
    end
    update_table_rows(params[:id], table_code, rows)

    redirect_to photo_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row update failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to photo_path(params[:id]), alert: "写真・メモの編集に失敗しました。"
  end

  def update_table_rows_batch
    record = photo_record(params[:id])
    table_code = table_row_params[:table_code]
    submitted_rows = params.fetch(:table_rows, {})
    rows = detail_table_rows(record, table_code).map do |row|
      payload = kintone_table_row_payload(row)
      row_params = submitted_rows[row["id"].to_s] || {}
      apply_table_row_params(payload, row_params, source_row: row)
      payload
    end
    update_table_rows(params[:id], table_code, rows)

    redirect_to photo_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table rows batch update failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to photo_path(params[:id]), alert: "写真・メモの保存に失敗しました。"
  end

  def delete_table_row
    record = photo_record(params[:id])
    table_code = table_row_params[:table_code]
    target_row_id = table_row_params[:row_id].to_s
    rows = detail_table_rows(record, table_code).filter_map do |row|
      next if row["id"].to_s == target_row_id

      kintone_table_row_payload(row)
    end
    update_table_rows(params[:id], table_code, rows)

    redirect_to photo_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row delete failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to photo_path(params[:id]), alert: "写真・メモの削除に失敗しました。"
  end

  private

  def photo_record(id)
    response = photos_record_client.find(id)
    response["record"]
  end

  def photo_records_for(machine_values)
    normalized_values = machine_values.map { |value| normalize(value) }
    fetched_photo_records(machine_values).select do |record|
      normalized_values.include?(normalize(field_value(record, :machine)))
    end
  end

  def fetched_photo_records(_machine_values)
    machine_values = machine_search_values(_machine_values)
    if machine_values.present?
      Rails.cache.fetch(photo_summary_cache_key(machine_values), expires_in: SUMMARY_CACHE_TTL) do
        fetch_photo_summary_records_for_machine(machine_values)
      end
    else
      Rails.cache.fetch(photo_summary_cache_key, expires_in: SUMMARY_CACHE_TTL) do
        fetch_photo_summary_records
      end
    end
  end

  def fetch_photo_summary_records_for_machine(machine_values)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    fields = summary_field_codes(record_client)
    records = fetch_all_photo_records(photo_summary_query(machine_values, record_client), record_client: record_client, fields: fields)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    Rails.logger.info("Photo summary fetch by machine completed: #{records.count} records in #{elapsed_ms}ms")
    records
  rescue StandardError => e
    Rails.logger.warn("Photo summary fetch by machine failed: #{e.class}: #{e.message}")
    Rails.cache.fetch(photo_summary_cache_key, expires_in: SUMMARY_CACHE_TTL) do
      fetch_photo_summary_records
    end
  end

  def fetch_photo_summary_records
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    fields = summary_field_codes(record_client)
    records = fetch_all_photo_records(photo_summary_query, record_client: record_client, fields: fields)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    Rails.logger.info("Photo summary fetch all completed: #{records.count} records in #{elapsed_ms}ms")
    records
  rescue StandardError => e
    Rails.logger.warn("Photo summary fetch with limited fields failed: #{e.class}: #{e.message}")
    fetch_all_photo_records(photo_summary_query)
  end

  def photo_summary_query(machine_values = nil, record_client = nil)
    machine_clause = machine_values.present? && record_client ? machine_query_clause(machine_values, record_client) : nil
    conditions = [
      "施工予定日 > FROM_TODAY(-1, MONTHS)",
      "施工予定日 < FROM_TODAY(6, MONTHS)",
      machine_clause
    ].compact

    <<~QUERY.squish
      #{conditions.join(" and ")}
      order by レコード番号 asc
    QUERY
  end

  def fetch_all_photo_records(base_query, record_client: KintoneSync::Record.new(photos_app_id, photos_guest_space_id), fields: nil)
    records = []
    offset = 0
    limit = 500

    loop do
      response = record_client.find_list(query: "#{base_query} limit #{limit} offset #{offset}", fields: fields)
      page = Array(response["records"])
      records.concat(page)
      break if page.count < limit

      offset += limit
    end

    records
  end

  def default_records(records)
    records.sort_by { |record| [record_date(record) || Date.new(9999, 12, 31), record_id(record).to_i] }
  end

  def completed_records(records)
    records.select { |record| record_date(record).present? && record_date(record) < Date.current && !incomplete?(record) }
           .sort_by { |record| [record_date(record) || Date.new(1, 1, 1), record_id(record).to_i] }
           .reverse
  end

  def future_records(records, visible_dates)
    last_visible_date = visible_dates.last || Date.current
    records.select do |record|
      date = record_date(record)
      date.nil? || date > last_visible_date
    end
  end

  def date_tabs
    (0..7).map { |index| Date.current + index.days }
  end

  def selected_date(date_tabs)
    requested = parse_date(params[:date])
    return requested if requested

    date_tabs.first || Date.current
  end

  def selected_filter
    params[:date].presence
  end

  def selected_records
    case @selected_filter
    when "all"
      @future_records
    when "completed"
      @completed_records
    else
      @records_by_date.fetch(@selected_date, [])
    end
  end

  def schedule_bucket_date(record)
    date = record_date(record)
    return Date.current if date.blank?
    return Date.current if date < Date.current && incomplete?(record)

    date
  end

  def record_date(record)
    value = field_value(record, :date)
    parse_date(value)
  end
  helper_method :record_date

  def parse_date(value)
    return value if value.is_a?(Date)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def field_value(record, key)
    FIELD_ALIASES.fetch(key).each do |field_code|
      value = record&.dig(field_code, "value")
      return value if value.present?
    end
    nil
  end
  helper_method :field_value

  def field_raw_value(record, field_code)
    record&.dig(field_code, "value")
  end
  helper_method :field_raw_value

  def record_title(record)
    [field_value(record, :company), field_value(record, :site), field_value(record, :detail)].compact_blank.join("　")
  end
  helper_method :record_title

  def record_address(record)
    direct_address = field_value(record, :address)
    return direct_address if direct_address.present?

    [field_value(record, :prefecture), field_value(record, :county), field_value(record, :city), field_value(record, :address_tail)].compact_blank.join
  end
  helper_method :record_address

  def record_id(record)
    record&.dig("$id", "value") || record&.dig("レコード番号", "value")
  end
  helper_method :record_id

  def detail_table_label(table_code)
    table_code.to_s.sub(/\Aテーブル/, "")
  end
  helper_method :detail_table_label

  def detail_table_rows(record, table_code)
    Array(record&.dig(table_code, "value"))
  end
  helper_method :detail_table_rows

  def detail_table_columns(rows, table_code = nil)
    columns = rows.flat_map { |row| row.dig("value")&.keys || [] }.uniq
    columns = fallback_table_columns(table_code) if columns.blank? && table_code.present?
    order_detail_table_columns(rows, columns, table_code)
  end
  helper_method :detail_table_columns

  def detail_file_column(rows, columns, _table_code = nil)
    columns.find { |column| rows.any? { |row| detail_file_cell?(row, column) } } ||
      columns.find { |column| !memo_column?(column) }
  end
  helper_method :detail_file_column

  def detail_memo_column(columns, table_code = nil)
    columns.find { |column| memo_column?(column) } || fallback_memo_column(table_code, columns)
  end
  helper_method :detail_memo_column

  def detail_cell(row, column)
    row.dig("value", column)
  end
  helper_method :detail_cell

  def detail_cell_value(row, column)
    cell = detail_cell(row, column)
    return "" unless cell

    cell["value"]
  end
  helper_method :detail_cell_value

  def number_memo_column?(rows, table_code, column)
    return false if column.blank?

    Array(rows).any? { |row| detail_cell(row, column)&.dig("type") == "NUMBER" } ||
      numeric_memo_hint?(table_code, column)
  end
  helper_method :number_memo_column?

  def detail_memo_display(value, rows, table_code, column)
    memo_value = value.is_a?(Array) ? value.join(", ") : value.to_s
    return memo_value.presence || "-" unless number_memo_column?(rows, table_code, column)

    numeric_value = normalize_numeric_memo_value(memo_value)
    numeric_value.present? ? "L=#{numeric_value}m" : "-"
  end
  helper_method :detail_memo_display

  def detail_file_cell?(row, column)
    detail_cell(row, column)&.dig("type") == "FILE"
  end
  helper_method :detail_file_cell?

  def table_row_dom_id(table_code, suffix)
    "table-row-#{Digest::SHA1.hexdigest(table_code.to_s).first(12)}-#{suffix}"
  end
  helper_method :table_row_dom_id

  def photo_status(record)
    field_value(record, :photo_status).presence || "未完了"
  end
  helper_method :photo_status

  def incomplete?(record)
    photo_status(record) != PICTURE_FLAG_DONE
  end
  helper_method :incomplete?

  def normalize(value)
    value.to_s.strip.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9").gsub(/[[:space:]　]+/, "")
  end

  def machine_search_values(*values)
    values.flatten.compact_blank.flat_map do |value|
      raw = value.to_s.strip
      [
        raw,
        raw.tr("　", " "),
        raw.gsub(/[[:space:]　]+/, "")
      ]
    end.compact_blank.uniq
  end

  def machine_query_values(values)
    variants = machine_search_values(values)

    variants.map { |variant| %("#{kintone_query_value(variant)}") }.join(",")
  end

  def kintone_query_value(value)
    value.to_s.gsub(/[\\"]/) { |char| "\\#{char}" }
  end

  def visible_detail_sections(record)
    enabled = Array(record&.dig("報告書フォーマット撮影写真", "value")).map(&:to_s)

    DETAIL_SECTIONS.filter_map do |section|
      tables = section[:tables].select do |table_code|
        label = detail_table_label(table_code)
        rows = detail_table_rows(record, table_code)
        if enabled.present?
          enabled.include?(label) || table_code == "その他"
        else
          table_has_visible_content?(rows) || table_code == "その他"
        end
      end
      next if tables.blank?

      section.merge(tables: tables)
    end
  end

  def table_has_visible_content?(rows)
    Array(rows).any? do |row|
      row.fetch("value", {}).values.any? do |field|
        visible_field_value?(field["value"])
      end
    end
  end

  def visible_field_value?(value)
    case value
    when Array
      value.any? do |item|
        item.is_a?(Hash) ? item["fileKey"].present? || item["name"].present? : item.present?
      end
    else
      value.present?
    end
  end

  def photo_summary_cache_key(machine_values = nil)
    key_parts = [
      "photos-summary",
      SUMMARY_CACHE_VERSION,
      photos_app_id,
      photos_guest_space_id
    ]
    if machine_values.present?
      key_parts << "machine"
      key_parts << Digest::SHA1.hexdigest(machine_values.sort.join("\0"))
    end
    key_parts.join(":")
  end

  def summary_field_codes(record_client)
    available_codes = available_field_codes(record_client)
    (FIELD_ALIASES.values.flatten + SUMMARY_SYSTEM_FIELDS).uniq.select do |field_code|
      field_code.start_with?("$") || available_codes.include?(field_code)
    end
  end

  def machine_query_clause(machine_values, record_client)
    machine_fields = FIELD_ALIASES[:machine].select { |field_code| available_field_codes(record_client).include?(field_code) }
    return nil if machine_fields.blank?

    clauses = machine_fields.product(machine_search_values(machine_values)).map do |field_code, value|
      "#{field_code} = \"#{kintone_query_value(value)}\""
    end
    "(#{clauses.join(' or ')})"
  end

  def available_field_codes(record_client)
    Rails.cache.fetch(photo_fields_cache_key, expires_in: 1.hour) do
      record_client.properties.keys
    end
  end

  def photo_fields_cache_key
    [
      "photos-fields",
      SUMMARY_CACHE_VERSION,
      photos_app_id,
      photos_guest_space_id
    ].join(":")
  end

  def table_row_params
    params.permit(:table_code, :row_id, :file_column, :memo_column, :memo, :photo)
  end

  def update_table_rows(record_id, table_code, rows)
    photos_record_client.update(
      record_id,
      table_code => { value: rows }
    )
  end

  def new_table_row_payload
    payload = { value: {} }
    apply_table_row_params(payload)
    payload
  end

  def apply_table_row_params(payload, row_params = table_row_params, source_row: nil)
    file_column = table_row_params[:file_column].presence
    memo_column = table_row_params[:memo_column].presence
    table_code = table_row_params[:table_code].presence
    payload[:value] ||= {}

    photo_file_key = uploaded_photo_file_key(param_value(row_params, :photo))
    if file_column.present? && photo_file_key.present?
      payload[:value][file_column] = { value: [{ fileKey: photo_file_key }] }
    end

    if memo_column.present? && param_present_key?(row_params, :memo)
      memo_value = param_value(row_params, :memo).to_s
      if numeric_memo_field?(table_code, memo_column, source_row)
        memo_value = normalize_numeric_memo_value(memo_value)
      end
      payload[:value][memo_column] = { value: memo_value }
    end
    payload
  end

  def param_present_key?(params_hash, key)
    params_hash.respond_to?(:key?) &&
      (params_hash.key?(key) || params_hash.key?(key.to_s))
  end

  def param_value(params_hash, key)
    return params_hash[key] if params_hash.respond_to?(:key?) && params_hash.key?(key)
    return params_hash[key.to_s] if params_hash.respond_to?(:key?) && params_hash.key?(key.to_s)

    nil
  end

  def numeric_memo_field?(table_code, memo_column, source_row = nil)
    (source_row.present? && detail_cell(source_row, memo_column)&.dig("type") == "NUMBER") ||
      numeric_memo_hint?(table_code, memo_column)
  end

  def numeric_memo_hint?(table_code, column)
    text = [detail_table_label(table_code), column].compact.join(" ")
    NUMBER_MEMO_TABLE_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def normalize_numeric_memo_value(value)
    normalized = value.to_s.tr("０-９．，－", "0-9.,-")
    match = normalized.match(/-?\d+(?:[.,]\d+)?/)
    match ? match[0].tr(",", ".") : ""
  end

  def uploaded_photo_file_key(photo)
    photo = Array(photo).find do |file|
      file.present? && (!file.respond_to?(:size) || file.size.to_i.positive?)
    end
    return if photo.blank?

    KintoneSync::File.new(photos_app_id, photos_guest_space_id).upload(
      data: photo.read,
      content_type: photo.content_type,
      filename: photo.original_filename
    )
  end

  def kintone_table_row_payload(row)
    payload = { value: {} }
    payload[:id] = row["id"] if row["id"].present?
    row.fetch("value", {}).each do |field_code, field|
      payload[:value][field_code] = { value: kintone_field_update_value(field) }
    end
    payload
  end

  def kintone_field_update_value(field)
    return Array(field["value"]).filter_map { |file| { fileKey: file["fileKey"] } if file["fileKey"].present? } if field["type"] == "FILE"

    field["value"]
  end

  def order_detail_table_columns(rows, columns, _table_code)
    columns.sort_by do |column|
      file_column = rows.any? { |row| detail_file_cell?(row, column) }
      [
        memo_column?(column) ? 1 : 0,
        file_column ? 0 : 1,
        column.to_s
      ]
    end
  end

  def memo_column?(column)
    column.to_s.start_with?("メモ")
  end

  def table_subfield_codes(table_code)
    table_subfield_properties(table_code).keys
  end

  def table_subfield_type(table_code, column)
    table_subfield_properties(table_code).dig(column.to_s, "type")
  end

  def table_subfield_properties(table_code)
    return {} if table_code.blank?

    @table_subfield_properties ||= {}
    @table_subfield_properties[table_code.to_s] ||= begin
      field = photos_form_properties[table_code.to_s]
      field&.dig("fields") || {}
    end
  rescue StandardError => e
    Rails.logger.warn("Kintone table fields lookup skipped: #{e.class}: #{e.message.to_s.truncate(200)}")
    @table_subfield_properties[table_code.to_s] = {}
  end

  def photos_form_properties
    return @photos_form_properties if defined?(@photos_form_properties)

    @photos_form_properties = photos_record_client.properties
  rescue StandardError => e
    Rails.logger.warn("Kintone form fields lookup skipped: #{e.class}: #{e.message.to_s.truncate(200)}")
    @photos_form_properties = {}
  end

  def photos_record_client
    @photos_record_client ||= KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
  end

  def fallback_table_columns(table_code)
    label = detail_table_label(table_code)
    [label, fallback_memo_column(table_code, [])].compact_blank
  end

  def fallback_memo_column(table_code, columns)
    return if table_code.blank?

    label = detail_table_label(table_code)
    return "メモ（その他）" if label == "その他"

    preferred = "メモ#{label}"
    columns.include?(preferred) ? preferred : preferred
  end

  def record_field_keys(records)
    sample = Array(records).find(&:present?)
    sample.respond_to?(:keys) ? sample.keys : []
  end

  def record_field_preview(records)
    sample = Array(records).find(&:present?)
    return {} unless sample.respond_to?(:each)

    sample.each_with_object({}) do |(key, field), result|
      result[key] = field.is_a?(Hash) ? field["value"] : field
    end
  end

  def photos_app_id
    (ENV["APP_PHOTOS"].presence || ENV["APP_PHOTO"].presence || 779).to_i
  end

  def photos_guest_space_id
    ENV["GUEST_SPACE"].presence&.to_i || 57
  end
end
