require 'digest/sha1'

class PhotosController < ApplicationController
  before_action :authentication

  PICTURE_FLAG_DONE = "完了"
  PICTURE_FLAG_INCOMPLETE = "未完了"
  COMPLETION_EXCLUDED_TABLES = %w[その他 テーブルその他].freeze
  SUMMARY_CACHE_VERSION = "v5"
  SUMMARY_CACHE_TTL = 10.minutes
  SUMMARY_SYSTEM_FIELDS = %w[$id レコード番号].freeze
  DOCUMENT_CONTACT_NOTE_FIELD_CODE = "施工後連絡事項"
  BLACKBOARD_PILES_PROVISIONAL_PATTERN = /推定|概算|未定|確認中|調整中|仮/.freeze
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
    end_date: %w[施工終了日 終了日 完了予定日 工期終了日 終了予定日],
    company: %w[発注会社名 会社名 取引先名 顧客名 運用会社名 施工会社 施工会社名],
    prime_contractor: %w[元請名 元請 元請会社 元請会社名],
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

  DOCUMENT_CATEGORIES = {
    receipt: {
      label: "レシート",
      field_codes: %w[現場直送レシート レシート 資料レシート レシートPDF レシート資料]
    },
    delivery_note: {
      label: "納品書",
      field_codes: %w[現場直送納品書 納品書 資料納品書 納品書PDF 納品書資料]
    },
    completion_drawing: {
      label: "施工後図面",
      field_codes: %w[現場直送施工後図面 施工後図面 資料施工後図面 施工後図面PDF 施工後図面資料]
    },
    other_document: {
      label: "その他資料",
      field_codes: %w[現場直送その他資料 その他資料 資料その他 その他資料PDF その他資料添付]
    }
  }.freeze

  def index
    @machine_name = params[:machine].to_s.strip
    @machine_search_values = machine_search_values(@machine_name, params[:machine_model])
    @records = @machine_name.present? ? photo_records_for(@machine_search_values) : []
    refresh_photo_summary_statuses!(@records)
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
    @back_url = photos_path(photo_index_return_params(@machine_name))
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

  def documents
    @record = photo_record(params[:id])
    @machine_name = params[:machine].presence || field_value(@record, :machine)
    @back_url = photo_path(params[:id], photo_return_params)

    # 診断情報: フィールド未検出問題の原因を特定するために一時的に追加
    @diag_form_properties_count = photos_form_properties.size
    @diag_form_file_fields = photos_form_properties.select { |_k, v| v["type"] == "FILE" }.keys
    @diag_record_keys = @record&.keys&.sort || []
    target_codes = %w[現場直送レシート 現場直送納品書 現場直送施工後図面 現場直送その他資料]
    @diag_record_target_check = target_codes.map { |code| { code: code, in_record: @record&.key?(code), type: @record&.dig(code, "type"), in_form: photos_form_properties.key?(code), form_type: photos_form_properties.dig(code, "type") } }
  rescue StandardError => e
    Rails.logger.error("Photo documents fetch failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    @photo_error = e
    @record = nil
  end

  def upload_document
    record = photo_record(params[:id])
    category_key = params[:document_category].to_s
    category = document_category(category_key)
    raise "資料種別を選択してください。" if category.blank?

    field_code = document_field_code(category, record)
    raise "#{category[:label]} の添付ファイルフィールドがkintone側に見つかりません。" if field_code.blank?

    document = params[:document_pdf]
    raise "PDFファイルを取得できませんでした。" if document.blank? || document.size.to_i <= 0

    file_key = KintoneSync::File.new(photos_app_id, photos_guest_space_id).upload(
      data: document.read,
      content_type: "application/pdf",
      filename: document.original_filename.presence || document_pdf_filename(category)
    )
    latest_record = photo_record(params[:id])
    existing_files = document_file_keys(latest_record, field_code)
    update_document_file_field(params[:id], field_code, existing_files, file_key)
    log_photo_upload_event(
      "photos.upload.success",
      {
        record_id: params[:id],
        table_code: category[:label],
        file_name: document.original_filename,
        content_type: "application/pdf",
        file_size: document.size,
        row_id: nil
      }
    )
    clear_photo_summary_cache(latest_record)

    if request.xhr? || request.headers["X-CSRF-Token"].present?
      render json: {
        status: "success",
        message: "#{category[:label]}PDFをアップロードしました。",
        field_code: field_code,
        file_key: file_key,
        existing_count: existing_files.count
      }
    else
      redirect_to documents_photo_path(params[:id], photo_return_params), notice: "#{category[:label]}PDFをアップロードしました。"
    end
  rescue StandardError => e
    Rails.logger.error("Photo document upload failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    if request.xhr? || request.headers["X-CSRF-Token"].present?
      render json: {
        status: "error",
        message: "資料PDFのアップロードに失敗しました。#{e.message}",
        error_class: e.class.name
      }, status: :unprocessable_entity
    else
      redirect_to documents_photo_path(params[:id], photo_return_params), alert: "資料PDFのアップロードに失敗しました。#{e.message}"
    end
  end

  def delete_document
    record = photo_record(params[:id])
    category_key = params[:document_category].to_s
    category = document_category(category_key)
    raise "資料種別を選択してください。" if category.blank?

    field_code = document_field_code(category, record)
    raise "#{category[:label]} の添付ファイルフィールドがkintone側に見つかりません。" if field_code.blank?

    target_file_key = params[:file_key].to_s
    raise "削除対象のファイルを取得できませんでした。" if target_file_key.blank?

    existing_files = document_file_keys(record, field_code)
    remaining_files = existing_files.reject { |file| file[:fileKey].to_s == target_file_key }
    raise "削除対象のファイルが見つかりませんでした。" if remaining_files.length == existing_files.length

    replace_document_file_field(params[:id], field_code, remaining_files)
    log_photo_upload_event(
      "documents.delete.success",
      {
        record_id: params[:id],
        table_code: category[:label],
        file_name: params[:file_name],
        content_type: "application/pdf",
        file_size: 0,
        row_id: nil
      }
    )
    clear_photo_summary_cache(record)

    redirect_to documents_photo_path(params[:id], photo_return_params), notice: "#{category[:label]}PDFを削除しました。"
  rescue StandardError => e
    Rails.logger.error("Photo document delete failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to documents_photo_path(params[:id], photo_return_params), alert: "資料PDFの削除に失敗しました。#{e.message}"
  end

  def update_document_contact_note
    record = photo_record(params[:id])
    field_code = document_contact_note_field_code(record)
    raise "施工後連絡事項フィールドがkintone側に見つかりません。" if field_code.blank?

    photos_record_client.update(params[:id], field_code => { value: params[:document_contact_note].to_s })
    clear_photo_summary_cache(record)

    redirect_to documents_photo_path(params[:id], photo_return_params), notice: "施工後連絡事項を保存しました。"
  rescue StandardError => e
    Rails.logger.error("Photo document contact note update failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    redirect_to documents_photo_path(params[:id], photo_return_params), alert: "施工後連絡事項の保存に失敗しました。#{e.message}"
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
    table_code = resolve_detail_table_code(record, table_row_params[:table_code])
    rows = detail_table_rows(record, table_code).map { |row| kintone_table_row_payload(row) }
    rows << new_table_row_payload(table_code: table_code)
    update_table_rows(params[:id], table_code, rows, source_record: record)

    redirect_to photo_detail_return_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row add failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    respond_photo_table_error("写真・メモの追加に失敗しました。")
  end

  def update_table_row
    record = photo_record(params[:id])
    table_code = resolve_detail_table_code(record, table_row_params[:table_code])
    target_row_id = table_row_params[:row_id].to_s
    rows = detail_table_rows(record, table_code).map do |row|
      payload = kintone_table_row_payload(row)
      apply_table_row_params(payload, source_row: row, table_code: table_code) if row["id"].to_s == target_row_id
      payload
    end
    update_table_rows(params[:id], table_code, rows, source_record: record)

    redirect_to photo_detail_return_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row update failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    respond_photo_table_error("写真・メモの編集に失敗しました。")
  end

  def update_table_rows_batch
    record = photo_record(params[:id])
    table_code = resolve_detail_table_code(record, table_row_params[:table_code])
    submitted_rows = params.fetch(:table_rows, {})
    rows = detail_table_rows(record, table_code).map do |row|
      payload = kintone_table_row_payload(row)
      row_params = submitted_rows[row["id"].to_s] || {}
      apply_table_row_params(payload, row_params, source_row: row, table_code: table_code)
      payload
    end
    update_table_rows(params[:id], table_code, rows, source_record: record)

    redirect_to photo_detail_return_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table rows batch update failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    respond_photo_table_error("写真・メモの保存に失敗しました。")
  end

  def delete_table_row
    record = photo_record(params[:id])
    table_code = resolve_detail_table_code(record, table_row_params[:table_code])
    target_row_id = table_row_params[:row_id].to_s
    rows = detail_table_rows(record, table_code).filter_map do |row|
      next if row["id"].to_s == target_row_id

      kintone_table_row_payload(row)
    end
    update_table_rows(params[:id], table_code, rows, source_record: record)

    redirect_to photo_detail_return_path(params[:id])
  rescue StandardError => e
    Rails.logger.error("Photo table row delete failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    respond_photo_table_error("写真・メモの削除に失敗しました。")
  end

  private

  def respond_photo_table_error(message)
    if request.xhr?
      render plain: message, status: :unprocessable_entity
    else
      redirect_to photo_detail_return_path(params[:id]), alert: message
    end
  end

  def photo_detail_return_path(record_id)
    photo_path(record_id, photo_return_params)
  end

  def photo_return_params
    {
      machine: params[:machine].presence,
      machine_model: params[:machine_model].presence,
      date: params[:date].presence
    }.compact_blank
  end

  def photo_index_return_params(machine_name = nil)
    photo_return_params.merge(machine: params[:machine].presence || machine_name).compact_blank
  end

  def document_categories
    DOCUMENT_CATEGORIES
  end
  helper_method :document_categories

  def document_contact_note_field_code(record = nil)
    field_code = DOCUMENT_CONTACT_NOTE_FIELD_CODE
    return field_code if record&.key?(field_code) || photos_form_properties.key?(field_code)

    nil
  end
  helper_method :document_contact_note_field_code

  def document_contact_note(record)
    field_code = document_contact_note_field_code(record)
    return "" if field_code.blank?

    record&.dig(field_code, "value").to_s
  end
  helper_method :document_contact_note

  def document_category(key)
    DOCUMENT_CATEGORIES[key.to_s.to_sym]
  end

  def document_field_code(category, record = nil)
    candidates = document_field_candidates(category)
    record_match = candidates.find { |field_code| record&.dig(field_code, "type") == "FILE" }
    return record_match if record_match.present?

    exact_match = candidates.find { |field_code| photos_form_properties.dig(field_code, "type") == "FILE" }
    return exact_match if exact_match.present?

    normalized_candidates = candidates.map { |value| normalize_document_field_name(value) }
    label_match = photos_form_properties.find do |field_code, property|
      next false unless property["type"] == "FILE"

      document_field_name_match?(field_code, normalized_candidates) ||
        document_field_name_match?(property["label"], normalized_candidates)
    end
    return label_match.first if label_match.present?

    Rails.logger.warn(
      "Document FILE field not found: label=#{category[:label]} " \
      "candidates=#{candidates.join(', ')} available=#{available_document_file_fields.join(', ')}"
    )
    nil
  end
  helper_method :document_field_code

  def document_field_candidates(category)
    (Array(category[:field_codes]) + [category[:label]]).compact.map(&:to_s).uniq
  end

  def normalize_document_field_name(value)
    value.to_s.gsub(/[[:space:]　"'“”‘’「」『』]/, "")
  end

  def document_field_name_match?(value, normalized_candidates)
    normalized_value = normalize_document_field_name(value)
    normalized_candidates.any? do |candidate|
      normalized_value == candidate ||
        normalized_value.end_with?(candidate) ||
        normalized_value.include?(candidate)
    end
  end

  def available_document_file_fields
    photos_form_properties.filter_map do |field_code, property|
      next unless property["type"] == "FILE"

      label = property["label"].presence
      label.present? && label != field_code ? "#{field_code}(#{label})" : field_code
    end
  end

  def document_files(record, category)
    field_code = document_field_code(category, record)
    return [] if field_code.blank?

    Array(record&.dig(field_code, "value"))
  end
  helper_method :document_files

  def document_file_keys(record, field_code)
    Array(record&.dig(field_code, "value")).filter_map do |file|
      { fileKey: file["fileKey"] } if file["fileKey"].present?
    end
  end

  def update_document_file_field(record_id, field_code, existing_files, new_file_key)
    replace_document_file_field(record_id, field_code, existing_files + [{ fileKey: new_file_key }])
  end

  def replace_document_file_field(record_id, field_code, files)
    payload = { field_code.to_s => { value: files } }
    Rails.logger.info(
      "Document PDF field replace: record_id=#{record_id} field_code=#{field_code} " \
      "files=#{files.count} payload_keys=#{payload.keys.join(',')}"
    )
    photos_record_client.update(record_id, payload)
  end

  def document_pdf_filename(category)
    timestamp = Time.zone.now.strftime("%Y%m%d_%H%M%S")
    "#{category[:label]}_#{timestamp}.pdf"
  end

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

  def record_end_date(record)
    value = field_value(record, :end_date)
    parse_date(value)
  end
  helper_method :record_end_date

  def blackboard_date_text(record)
    start_date = record_date(record)
    end_date = record_end_date(record)
    fallback = field_value(record, :date).to_s
    return fallback if start_date.blank?
    return japanese_date(start_date) if end_date.blank? || end_date == start_date

    "#{japanese_date(start_date)}～#{japanese_date(end_date)}"
  end
  helper_method :blackboard_date_text

  def blackboard_piles_text(record)
    sanitize_blackboard_piles(field_value(record, :detail))
  end
  helper_method :blackboard_piles_text

  def parse_date(value)
    return value if value.is_a?(Date)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def japanese_date(date)
    "#{date.year}年#{date.month}月#{date.day}日"
  end

  def sanitize_blackboard_piles(value)
    text = value.to_s.tr("，", ",").tr("★☆", "").squish
    text = text.split(/[→⇒]/).first.to_s
    text = text.sub(/[、,]\s*(?:JIS\b|H-?CPT|カーボン|キュア|.*材|.*追加|.*破損|.*折れ).*\z/i, "")
    text = text.sub(/\s+(?:JIS\b|H-?CPT|カーボン|キュア|.*材).*\z/i, "")
    text.strip!
    return "" if text.match?(BLACKBOARD_PILES_PROVISIONAL_PATTERN)

    text.match?(/[mMｍＭ]/) ? text : ""
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
    [field_value(record, :prime_contractor), field_value(record, :site), field_value(record, :detail)].compact_blank.join("　")
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
    return "その他" if other_table_code?(table_code)

    table_code.to_s.sub(/\Aテーブル/, "")
  end
  helper_method :detail_table_label

  def detail_column_label(table_code, column)
    return "その他" if other_table_code?(table_code) && column.to_s == "テーブルその他"

    column
  end
  helper_method :detail_column_label

  def detail_table_rows(record, table_code)
    resolved_table_code = resolve_detail_table_code(record, table_code)
    Array(record&.dig(resolved_table_code, "value"))
  end
  helper_method :detail_table_rows

  def detail_table_columns(rows, table_code = nil)
    columns = rows.flat_map { |row| row.dig("value")&.keys || [] }.uniq
    columns = fallback_table_columns(table_code) if columns.blank? && table_code.present?
    order_detail_table_columns(rows, columns, table_code)
  end
  helper_method :detail_table_columns

  def detail_file_column(rows, columns, table_code = nil)
    table_subfield_codes(table_code).find { |column| table_subfield_type(table_code, column) == "FILE" } ||
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
      tables = section[:tables].filter_map do |configured_table_code|
        table_code = resolve_detail_table_code(record, configured_table_code)
        label = detail_table_label(configured_table_code)
        resolved_label = detail_table_label(table_code)
        rows = detail_table_rows(record, table_code)
        if enabled.present?
          table_code if enabled.include?(label) || enabled.include?(resolved_label) || other_table_code?(configured_table_code)
        else
          table_code if table_has_visible_content?(rows) || other_table_code?(configured_table_code)
        end
      end.uniq
      next if tables.blank?

      section.merge(tables: tables)
    end
  end

  def resolve_detail_table_code(record, table_code)
    candidates = detail_table_code_candidates(table_code)
    candidates.find { |candidate| record_table_field?(record, candidate) && form_table_field?(candidate) } ||
      candidates.find { |candidate| form_table_field?(candidate) } ||
      candidates.find { |candidate| record_table_field?(record, candidate) } ||
      table_code.to_s
  end

  def resolve_form_table_code(table_code)
    detail_table_code_candidates(table_code).find { |candidate| form_table_field?(candidate) } || table_code.to_s
  end

  def detail_table_code_candidates(table_code)
    raw = table_code.to_s
    return %w[その他 テーブルその他] if other_table_code?(raw)

    label = detail_table_label(raw)
    [raw, "テーブル#{label}", label].compact_blank.uniq
  end

  def form_table_field?(table_code)
    photos_form_properties.dig(table_code.to_s, "type") == "SUBTABLE"
  end

  def record_table_field?(record, table_code)
    field = record&.dig(table_code.to_s)
    field&.dig("type") == "SUBTABLE" || field&.dig("value").is_a?(Array)
  end

  def other_table_code?(table_code)
    raw = table_code.to_s
    raw == "その他" || raw == "テーブルその他"
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

  def refresh_photo_summary_statuses!(records)
    record_ids = records.filter_map { |record| record_id(record).presence }
                        .map(&:to_i)
                        .reject(&:zero?)
                        .uniq
    return if record_ids.blank?

    record_client = KintoneSync::Record.new(photos_app_id, photos_guest_space_id)
    available_codes = available_field_codes(record_client)
    status_field_codes = FIELD_ALIASES[:photo_status].select { |field_code| available_codes.include?(field_code) }
    return if status_field_codes.blank?

    fields = (SUMMARY_SYSTEM_FIELDS + status_field_codes).uniq
    fresh_records = record_ids.each_slice(100).flat_map do |ids|
      fetch_all_photo_records("$id in (#{ids.join(',')})", record_client: record_client, fields: fields)
    end
    fresh_records_by_id = fresh_records.index_by { |record| record_id(record).to_s }

    records.each do |record|
      fresh_record = fresh_records_by_id[record_id(record).to_s]
      next unless fresh_record

      status_field_codes.each do |field_code|
        record[field_code] = fresh_record[field_code] if fresh_record.key?(field_code)
      end
    end
  rescue StandardError => e
    Rails.logger.warn("Photo summary status refresh skipped: #{e.class}: #{e.message}")
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

  def update_table_rows(record_id, table_code, rows, source_record: nil)
    update_payload = { table_code => { value: rows } }
    upload_logs = pending_photo_upload_logs.dup
    photos_record_client.update(record_id, update_payload)
    log_photo_upload_successes(upload_logs)
    log_photo_table_update_success(record_id, table_code) if upload_logs.blank?
    refresh_photo_completion_status(record_id)
    clear_photo_summary_cache(source_record) if source_record.present?
  rescue StandardError => e
    log_photo_upload_failures(upload_logs || [], e)
    raise
  ensure
    clear_pending_photo_upload_logs
  end

  def refresh_photo_completion_status(record_id)
    record = photo_record(record_id)
    status_field = photo_status_field_code(record)
    return if status_field.blank?

    status = photo_completion_status(record)
    return if photo_status(record) == status

    photos_record_client.update(record_id, status_field => { value: status })
  end

  def photo_status_field_code(record)
    preferred_field = "写真完了フラグ"
    return preferred_field if record&.key?(preferred_field) || photos_form_properties.key?(preferred_field)

    FIELD_ALIASES[:photo_status].find { |field_code| photos_form_properties.key?(field_code) } ||
      FIELD_ALIASES[:photo_status].find { |field_code| record&.key?(field_code) }
  end

  def photo_completion_status(record)
    all_required_photo_tables_complete?(record) ? PICTURE_FLAG_DONE : PICTURE_FLAG_INCOMPLETE
  end

  def all_required_photo_tables_complete?(record)
    required_tables = required_photo_table_codes(record)
    return false if required_tables.blank?

    required_tables.all? do |table_code|
      table_photo_attached?(record, table_code)
    end
  end

  def required_photo_table_codes(record)
    visible_detail_sections(record).flat_map { |section| section[:tables] }
                                  .reject { |table_code| completion_excluded_table?(table_code) }
  end

  def completion_excluded_table?(table_code)
    table_text = [table_code, detail_table_label(table_code)].compact.join(" ")
    COMPLETION_EXCLUDED_TABLES.any? { |excluded| table_text.include?(excluded) } ||
      table_text.include?("その他")
  end

  def table_photo_attached?(record, table_code)
    rows = detail_table_rows(record, table_code)
    return false if rows.blank?

    file_columns = table_file_columns(table_code, rows)
    return false if file_columns.blank?

    rows.any? do |row|
      file_columns.any? { |column| file_value_present?(detail_cell_value(row, column)) }
    end
  end

  def table_file_columns(table_code, rows)
    current_file_column = table_row_params[:file_column].presence if table_code.to_s == table_row_params[:table_code].to_s
    Array(current_file_column).presence ||
      table_subfield_codes(table_code).select { |column| table_subfield_type(table_code, column) == "FILE" }.presence ||
      detail_table_columns(rows, table_code).select { |column| rows.any? { |row| detail_file_cell?(row, column) } }
  end

  def file_value_present?(value)
    Array(value).any? do |file|
      file.is_a?(Hash) ? file["fileKey"].present? || file["name"].present? : file.present?
    end
  end

  def clear_photo_summary_cache(record)
    Rails.cache.delete(photo_summary_cache_key)
    requested_machine_values = machine_search_values(params[:machine], params[:machine_model])
    Rails.cache.delete(photo_summary_cache_key(requested_machine_values)) if requested_machine_values.present?
    machine = field_value(record, :machine)
    Rails.cache.delete(photo_summary_cache_key(machine_search_values(machine))) if machine.present?
    Rails.cache.delete_matched("photos-summary:*")
  rescue StandardError => e
    Rails.logger.warn("Photo summary cache clear skipped: #{e.class}: #{e.message}")
  end

  def new_table_row_payload(table_code: nil)
    payload = { value: {} }
    apply_table_row_params(payload, table_code: table_code)
    payload
  end

  def apply_table_row_params(payload, row_params = table_row_params, source_row: nil, table_code: nil)
    table_code = table_code.presence || table_row_params[:table_code].presence
    file_column = resolved_file_column(table_code, table_row_params[:file_column].presence, payload)
    memo_column = table_row_params[:memo_column].presence
    payload[:value] ||= {}

    photo_file_key = uploaded_photo_file_key(
      param_value(row_params, :photo),
      table_code: table_code,
      row_id: source_row&.dig("id") || table_row_params[:row_id]
    )
    if photo_file_key.blank? && selected_photo_param?(row_params, :photo)
      raise "写真ファイルを取得できませんでした。カメラアプリから空のファイルが返された可能性があります。"
    end
    if photo_file_key.present? && file_column.blank?
      raise "添付先のファイル列を特定できませんでした。"
    elsif file_column.present? && photo_file_key.present?
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

  def resolved_file_column(table_code, requested_file_column, payload)
    inferred_column = inferred_file_column(table_code, payload)
    return requested_file_column if requested_file_column.present? && inferred_column.blank?
    return requested_file_column if requested_file_column.present? && table_subfield_type(table_code, requested_file_column) == "FILE"

    if requested_file_column.present? && inferred_column.present? && requested_file_column != inferred_column
      Rails.logger.warn("Photo file column corrected: table=#{table_code} requested=#{requested_file_column} resolved=#{inferred_column}")
    end
    inferred_column
  end

  def inferred_file_column(table_code, payload)
    table_subfield_codes(table_code).find { |column| table_subfield_type(table_code, column) == "FILE" } ||
      payload.fetch(:value, {}).keys.find { |column| table_subfield_type(table_code, column) == "FILE" } ||
      fallback_file_column(table_code)
  end

  def fallback_file_column(table_code)
    label = detail_table_label(table_code)
    if label == "その他"
      return table_subfield_codes(table_code).find { |column| column.to_s == "その他" && table_subfield_type(table_code, column) == "FILE" } ||
        table_subfield_codes(table_code).find { |column| table_subfield_type(table_code, column) == "FILE" } ||
        "テーブルその他"
    end

    label.presence
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

  def selected_photo_param?(params_hash, key)
    return false unless param_present_key?(params_hash, key)

    Array(param_value(params_hash, key)).any? do |file|
      next false if file.blank?

      (file.respond_to?(:original_filename) && file.original_filename.present?) ||
        (file.respond_to?(:size) && file.size.to_i >= 0)
    end
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

  def uploaded_photo_file_key(photo, table_code: nil, row_id: nil)
    photo = Array(photo).find do |file|
      file.present? && (!file.respond_to?(:size) || file.size.to_i.positive?)
    end
    return if photo.blank?

    upload_log = photo_upload_log_attributes(photo, table_code: table_code, row_id: row_id)
    KintoneSync::File.new(photos_app_id, photos_guest_space_id).upload(
      data: photo.read,
      content_type: photo.content_type,
      filename: photo.original_filename
    ).tap do
      pending_photo_upload_logs << upload_log
    end
  rescue StandardError => e
    log_photo_upload_failure(upload_log, e) if upload_log
    raise
  end

  def photo_upload_log_attributes(photo, table_code:, row_id:)
    {
      record_id: params[:id],
      table_code: table_code,
      row_id: row_id,
      file_name: photo.respond_to?(:original_filename) ? photo.original_filename : nil,
      content_type: photo.respond_to?(:content_type) ? photo.content_type : nil,
      file_size: photo.respond_to?(:size) ? photo.size : nil
    }
  end

  def pending_photo_upload_logs
    @pending_photo_upload_logs ||= []
  end

  def clear_pending_photo_upload_logs
    @pending_photo_upload_logs = []
  end

  def log_photo_upload_start(upload_log)
    log_photo_upload_event("photos.upload.start", upload_log)
  end

  def log_photo_upload_successes(upload_logs)
    Array(upload_logs).each { |upload_log| log_photo_upload_event("photos.upload.success", upload_log) }
  end

  def log_photo_upload_failure(upload_log, error)
    log_photo_upload_event("photos.upload.failure", upload_log, error: error)
  end

  def log_photo_upload_failures(upload_logs, error)
    Array(upload_logs).each { |upload_log| log_photo_upload_failure(upload_log, error) }
  end

  def log_photo_upload_event(key, upload_log, error: nil)
    ActionLogger.photo_upload_async(
      key,
      request: request,
      account: current_account,
      record_id: upload_log[:record_id],
      table_code: upload_log[:table_code],
      file_name: upload_log[:file_name],
      content_type: upload_log[:content_type],
      file_size: upload_log[:file_size],
      row_id: upload_log[:row_id],
      error: error&.message
    )
  end

  def log_photo_table_update_success(record_id, table_code)
    ActionLogger.photo_table_update_success_async(
      request: request,
      account: current_account,
      record_id: record_id,
      table_code: table_code
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

  def order_detail_table_columns(rows, columns, table_code)
    columns.sort_by do |column|
      file_column = table_subfield_type(table_code, column) == "FILE" ||
        rows.any? { |row| detail_file_cell?(row, column) }
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

    resolved_table_code = resolve_form_table_code(table_code)
    @table_subfield_properties ||= {}
    @table_subfield_properties[resolved_table_code.to_s] ||= begin
      field = photos_form_properties[resolved_table_code.to_s]
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
    subfield_codes = table_subfield_codes(table_code)
    return order_detail_table_columns([], subfield_codes, table_code) if subfield_codes.present?

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
